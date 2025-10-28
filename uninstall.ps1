#Requires -Version 5.1
<#
.SYNOPSIS
    Uninstalls all development tools and resets the developer environment
.DESCRIPTION
    This script safely removes all development tools installed by setup.ps1,
    including Chocolatey packages, PowerShell modules, and Node.js versions.
    Includes compliance audit logging for all uninstall operations.
.PARAMETER ConfigPath
    Path to the tools configuration file (default: .\config\tools-config.json)
.PARAMETER LocalDeveloper
    Runs in LocalDeveloper mode with confirmation prompts and safety checks
.PARAMETER Force
    Skip confirmation prompts (use with caution!)
.PARAMETER KeepChocolatey
    Keep Chocolatey package manager installed (only remove other tools)
.EXAMPLE
    .\uninstall.ps1 -LocalDeveloper
    Uninstalls all tools with confirmation prompts (recommended for local developers)
.EXAMPLE
    .\uninstall.ps1 -Force
    Uninstalls all tools without confirmation (CI/CD mode)
.EXAMPLE
    .\uninstall.ps1 -LocalDeveloper -KeepChocolatey
    Uninstalls all tools but keeps Chocolatey package manager
.NOTES
    Author: Development Team
    WARNING: This script will remove installed development tools.
    Make sure you have backups of any important data before proceeding.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "$PSScriptRoot\config\tools-config.json",

    [Parameter(Mandatory = $false)]
    [switch]$LocalDeveloper,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$KeepChocolatey
)

# Script configuration
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:UninstallStartTime = Get-Date

# Import required modules
$modulePath = "$PSScriptRoot\modules"
Import-Module "$modulePath\AdminCheck.psm1" -Force
Import-Module "$modulePath\ColorConfig.psm1" -Force
Import-Module "$modulePath\ErrorHandling.psm1" -Force
Import-Module "$modulePath\SystemCheck.psm1" -Force
Import-Module "$modulePath\ComplianceAudit.psm1" -Force

# ============================================================================
# FAIL-FAST: Validate configuration file exists
# ============================================================================
if (-not (Test-Path $ConfigPath)) {
    Write-Host "================================================================" -ForegroundColor Red
    Write-Host "  ERROR: Configuration file not found" -ForegroundColor Red
    Write-Host "================================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Expected location: $ConfigPath" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Please ensure the configuration file exists before running uninstall." -ForegroundColor White
    Write-Host ""
    exit 1
}

# ============================================================================
# DETECT ENVIRONMENT
# ============================================================================
$isCiCd = Test-CiCdEnvironment

if ($isCiCd -and -not $LocalDeveloper) {
    Write-InfoMessage "Detected CI/CD environment - running in automated mode"
}
elseif (-not $LocalDeveloper -and -not $isCiCd -and -not $Force) {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Yellow
    Write-Host "  WARNING: Running without -LocalDeveloper flag" -ForegroundColor Yellow
    Write-Host "================================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "This machine does not appear to be a CI/CD environment." -ForegroundColor White
    Write-Host ""
    Write-Host "If you are a local developer, please run with -LocalDeveloper flag:" -ForegroundColor White
    Write-Host "  .\uninstall.ps1 -LocalDeveloper" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Do you want to continue in CI/CD mode anyway? (Y/N): " -NoNewline -ForegroundColor Yellow
    $response = Read-Host
    if ($response -ne 'Y' -and $response -ne 'y') {
        Write-Host "Exiting gracefully..." -ForegroundColor Gray
        exit 0
    }
    Write-Host ""
    Write-Host "Continuing in CI/CD mode as requested..." -ForegroundColor Yellow
    Write-Host ""
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Show-UninstallBanner {
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Red
    Write-Host "                     DEVELOPMENT ENVIRONMENT UNINSTALL" -ForegroundColor Red
    Write-Host "================================================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "  This script will REMOVE the following:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    • All Chocolatey packages (Node.js, Docker, .NET, AWS CLI, etc.)" -ForegroundColor White
    Write-Host "    • All PowerShell modules (PSake, AWS.Tools, SqlServer, etc.)" -ForegroundColor White
    Write-Host "    • NVM and all Node.js versions" -ForegroundColor White
    if (-not $KeepChocolatey) {
        Write-Host "    • Chocolatey package manager" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "  Configuration: $ConfigPath" -ForegroundColor Gray
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Red
    Write-Host ""
}

function Confirm-Uninstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$LocalDeveloper
    )

    if ($LocalDeveloper) {
        Write-Host "Are you ABSOLUTELY SURE you want to uninstall all development tools? (Y/N): " -NoNewline -ForegroundColor Yellow
        $response = Read-Host

        if ($response -ne 'Y' -and $response -ne 'y') {
            Write-Host ""
            Write-Host "Uninstall cancelled by user." -ForegroundColor Cyan
            return $false
        }

        Write-Host ""
        Write-Host "Type 'UNINSTALL' to confirm: " -NoNewline -ForegroundColor Red
        $confirmation = Read-Host

        if ($confirmation -ne 'UNINSTALL') {
            Write-Host ""
            Write-Host "Confirmation failed. Uninstall cancelled." -ForegroundColor Cyan
            return $false
        }

        Write-Host ""
        Write-Host "Proceeding with uninstall..." -ForegroundColor Yellow
        Write-Host ""
        return $true
    }
    else {
        # CI/CD mode - auto-proceed with Force flag or CI environment
        Write-InfoMessage "Running in automated mode. Proceeding with uninstall..."
        return $true
    }
}

function Show-FinalSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Success,

        [Parameter(Mandatory = $false)]
        [switch]$LocalDeveloper
    )

    $duration = (Get-Date) - $script:UninstallStartTime
    $durationMinutes = [math]::Round($duration.TotalMinutes, 2)

    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "                    UNINSTALL COMPLETE - FINAL SUMMARY" -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host ""
    Write-Host "Total Duration:" -ForegroundColor White
    Write-Host "  $durationMinutes minutes" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Configuration File:" -ForegroundColor White
    Write-Host "  $ConfigPath" -ForegroundColor Gray
    Write-Host ""

    # Show error/warning counts
    $errorCount = (Get-ErrorLog).Count
    $warningCount = (Get-WarningLog).Count

    if ($errorCount -gt 0) {
        Write-Host "Total Errors:" -ForegroundColor White
        Write-Host "  $errorCount" -ForegroundColor Red
        Write-Host ""
    }

    if ($warningCount -gt 0) {
        Write-Host "Total Warnings:" -ForegroundColor White
        Write-Host "  $warningCount" -ForegroundColor Yellow
        Write-Host ""
    }

    Write-Host "Completion Time:" -ForegroundColor White
    Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host ""

    if ($Success) {
        Write-Host "Overall Status:" -ForegroundColor White
        Write-Host "  SUCCESS" -ForegroundColor Green
        Write-Host ""
        Write-Host "================================================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host ""
        Write-Host "UNINSTALL SUCCESSFUL" -ForegroundColor Green
        Write-Host "===================" -ForegroundColor Green
        Write-Host "Your development environment has been reset." -ForegroundColor White
        Write-Host ""
        Write-Host "Next Steps:" -ForegroundColor Cyan
        Write-Host "  • Close this PowerShell window" -ForegroundColor White
        Write-Host "  • Open a new Administrator PowerShell window" -ForegroundColor White
        Write-Host "  • Run setup.ps1 to reinstall tools if needed" -ForegroundColor White
        Write-Host ""
    }
    else {
        Write-Host "Overall Status:" -ForegroundColor White
        Write-Host "  FAILED" -ForegroundColor Red
        Write-Host ""
        Write-Host "================================================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host ""
        Write-Host "UNINSTALL FAILED" -ForegroundColor Red
        Write-Host "===============" -ForegroundColor Red
        Write-Host "Please review the errors above and:" -ForegroundColor White
        Write-Host "  1. Review the configuration file for correctness" -ForegroundColor White
        Write-Host "  2. Check the error logs above" -ForegroundColor White
        Write-Host "  3. Re-run this script after resolving issues" -ForegroundColor White
        Write-Host ""

        if ($errorCount -gt 0) {
            Write-Host "Errors Encountered:" -ForegroundColor Red
            foreach ($error in (Get-ErrorLog)) {
                Write-Host "  [$($error.Timestamp)] $($error.Message)" -ForegroundColor Red
            }
            Write-Host ""
        }
    }

    # Display audit log location
    $auditLog = Get-AuditLogPath
    if ($auditLog) {
        Write-Host "Compliance audit log finalized: $auditLog" -ForegroundColor Gray
    }

    Write-Host ""
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

try {
    # Initialize
    Initialize-ErrorHandling

    # Initialize compliance audit (SOC2/HIPAA requirement)
    Initialize-ComplianceAudit -LogDirectory "$PSScriptRoot\logs"

    # Show uninstall banner (skip in CI/CD mode with Force)
    if ($LocalDeveloper -or (-not $Force -and -not $isCiCd)) {
        Show-UninstallBanner
    }
    else {
        Write-InfoMessage "Running in automated mode (non-interactive uninstall)"
    }

    # Confirm user wants to proceed
    if (-not (Confirm-Uninstall -LocalDeveloper:$LocalDeveloper) -and -not $Force) {
        exit 0
    }

    Write-Host "Starting uninstall process..." -ForegroundColor Cyan
    Write-Host ""

    # Check 1: Admin privileges (only in LocalDeveloper mode)
    if ($LocalDeveloper) {
        Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Gray
        Write-Host "Pre-Flight Checks" -ForegroundColor Cyan
        Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Gray
        Write-ProgressMessage "Checking administrator privileges..."
        Assert-IsAdmin -ScriptName "Development Environment Uninstall"

        # Audit: Admin privilege check
        if (Get-Command -Name Write-SecurityAudit -ErrorAction SilentlyContinue) {
            $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            Write-SecurityAudit -Action "AdminCheck" -Component "Uninstall Script" `
                -Status $(if ($isAdmin) { "Success" } else { "Failed" }) `
                -Details "Administrator privilege verification for uninstall: $(if ($isAdmin) { 'Elevated' } else { 'Not elevated' })" `
                -Severity $(if ($isAdmin) { "Info" } else { "Critical" })
        }

        Write-SuccessMessage "All pre-flight checks passed"
        Write-Host ""
    }

    # Execute uninstall script
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Gray
    Write-Host "Uninstalling Development Tools" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Gray
    Write-Host ""

    $uninstallScriptPath = Join-Path -Path $PSScriptRoot -ChildPath "scripts" | Join-Path -ChildPath "Uninstall-DevelopmentTools.ps1"

    if (-not (Test-Path $uninstallScriptPath)) {
        Write-ErrorLog -Message "Uninstall script not found: $uninstallScriptPath" -Fatal
    }

    # Run uninstall script
    $uninstallParams = @{
        ConfigPath = $ConfigPath
    }

    if ($KeepChocolatey) {
        $uninstallParams.KeepChocolatey = $true
    }

    & $uninstallScriptPath @uninstallParams

    if ($LASTEXITCODE -ne 0) {
        Write-ErrorLog -Message "Development tools uninstall failed with exit code: $LASTEXITCODE" -Fatal
    }

    Write-SuccessMessage "Uninstall process completed successfully"

    Show-FinalSummary -Success $true -LocalDeveloper:$LocalDeveloper
    exit 0
}
catch {
    Write-ErrorLog -Message "Fatal error in uninstall script" -Exception $_.Exception -Fatal
    Show-FinalSummary -Success $false -LocalDeveloper:$LocalDeveloper
    exit 1
}
finally {
    # Close compliance audit session
    Close-ComplianceAudit

    # Cleanup
    $ProgressPreference = 'Continue'
}
