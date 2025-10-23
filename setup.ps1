#Requires -Version 5.1

<#
.SYNOPSIS
    Main orchestrator script for development environment setup
.DESCRIPTION
    Coordinates the execution of all setup scripts in the correct order.
    This script manages the complete development environment installation process.

    DEFAULT BEHAVIOR: Runs in CI/CD mode (non-interactive, minimal checks)
    Use -LocalDeveloper flag for interactive local development installation
.PARAMETER ConfigPath
    Path to the configuration file (default: .\config\tools-config.json)
.PARAMETER LocalDeveloper
    Run in local developer mode with admin checks, system validation, and user prompts
    Without this flag, runs in CI/CD mode (non-interactive, skips unnecessary checks)
.EXAMPLE
    .\setup.ps1
    # Runs in CI/CD mode (default) - no prompts, minimal checks
.EXAMPLE
    .\setup.ps1 -LocalDeveloper
    # Runs in local developer mode - admin checks, system validation, user prompts
.NOTES
    CI/CD Mode (default): Optimized for automated environments
    Local Developer Mode: Full validation and interactive prompts
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "$PSScriptRoot\config\tools-config.json",

    [Parameter(Mandatory = $false)]
    [switch]$LocalDeveloper
)

# Script initialization
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:SetupStartTime = Get-Date

# Import required modules
$modulePath = "$PSScriptRoot\modules"
Import-Module "$modulePath\AdminCheck.psm1" -Force
Import-Module "$modulePath\ColorConfig.psm1" -Force
Import-Module "$modulePath\ErrorHandling.psm1" -Force
Import-Module "$modulePath\SystemCheck.psm1" -Force

function Show-WelcomeBanner {
    <#
    .SYNOPSIS
        Displays welcome banner
    #>
    [CmdletBinding()]
    param()

    $banner = @"

================================================================================
        DEVELOPMENT ENVIRONMENT SETUP
================================================================================

This script will install and configure your development environment with the
following tools and frameworks:

  - Chocolatey Package Manager
  - Node Version Manager (NVM) for Windows
  - Node.js 18.19.1
  - Yarn Package Manager
  - .NET Core SDK
  - AWS CLI and PowerShell Tools
  - Docker Desktop
  - 7-Zip, cURL, K6, and more

All installations will be performed according to the configuration file at:
$ConfigPath

IMPORTANT NOTES:
  - This script requires Administrator privileges
  - Your system will be checked for minimum requirements
  - Existing tools may be upgraded or downgraded to match exact versions
  - You may be prompted to restart your terminal after completion

================================================================================
"@

    Write-ColorOutput $banner -Color Cyan
}

function Confirm-Proceed {
    <#
    .SYNOPSIS
        Prompts user to confirm proceeding with installation
    .PARAMETER LocalDeveloper
        Show interactive prompt for local developer mode
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$LocalDeveloper
    )

    if (-not $LocalDeveloper) {
        Write-InfoMessage "Running in CI/CD mode. Proceeding automatically..."
        return $true
    }

    Write-ColorOutput "`nDo you want to proceed with the installation? (Y/N): " -Color Yellow -NoNewline
    $response = Read-Host

    if ($response -match '^[Yy]') {
        return $true
    }

    Write-InfoMessage "Installation cancelled by user"
    return $false
}

function Invoke-PreFlightChecks {
    <#
    .SYNOPSIS
        Performs pre-flight checks before starting installation
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,

        [Parameter(Mandatory = $false)]
        [switch]$LocalDeveloper
    )

    Write-SectionHeader "Pre-Flight Checks"

    # Check 1: Admin privileges (only in LocalDeveloper mode)
    if ($LocalDeveloper) {
        Write-ProgressMessage "Checking administrator privileges..."
        Assert-IsAdmin -ScriptName "Development Environment Setup"
    }

    # Check 2: Configuration file (always check)
    Write-ProgressMessage "Validating configuration file..."
    if (-not (Test-Path $ConfigPath)) {
        Write-ErrorLog -Message "Configuration file not found: $ConfigPath" -Fatal
        return $false
    }

    try {
        $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
        Write-SuccessMessage "Configuration file validated"
    }
    catch {
        Write-ErrorLog -Message "Invalid configuration file format" -Exception $_.Exception -Fatal
        return $false
    }

    # Check 3: System requirements (only in LocalDeveloper mode)
    if ($LocalDeveloper) {
        Write-ProgressMessage "Checking system requirements..."
        $systemInfo = Get-SystemInformation
        Show-SystemInformation -SystemInfo $systemInfo

        Test-SystemRequirements -ConfigPath $ConfigPath | Out-Null
        Test-InternetConnection | Out-Null
    }

    Write-SuccessMessage "All pre-flight checks passed"
    return $true
}

function Invoke-DevelopmentToolsInstallation {
    <#
    .SYNOPSIS
        Executes the development tools installation script
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    Write-SectionHeader "Installing Development Tools"

    $scriptPath = "$PSScriptRoot\scripts\Install-DevelopmentTools.ps1"

    if (-not (Test-Path $scriptPath)) {
        Write-ErrorLog -Message "Installation script not found: $scriptPath" -Fatal
        return $false
    }

    try {
        $params = @{
            ConfigPath = $ConfigPath
        }

        # Execute script and redirect output to console (don't capture in return value)
        & $scriptPath @params | Out-Default

        if ($LASTEXITCODE -eq 0) {
            return $true
        }
        else {
            Write-ErrorLog -Message "Development tools installation failed with exit code: $LASTEXITCODE"
            return $false
        }
    }
    catch {
        Write-ErrorLog -Message "Exception during development tools installation" -Exception $_.Exception
        return $false
    }
}

function Show-FinalSummary {
    <#
    .SYNOPSIS
        Displays final summary and next steps
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Success
    )

    $duration = (Get-Date) - $script:SetupStartTime

    $summaryData = [ordered]@{
        "Overall Status"       = if ($Success) { "SUCCESS" } else { "FAILED" }
        "Total Duration"       = "{0:N2} minutes" -f $duration.TotalMinutes
        "Completion Time"      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "Configuration File"   = $ConfigPath
        "Total Errors"         = (Get-ErrorLog).Count
        "Total Warnings"       = (Get-WarningLog).Count
    }

    Write-DevSummary -Title "SETUP COMPLETE - FINAL SUMMARY" -Sections $summaryData

    if ($Success) {
        Write-SuccessMessage "`nSetup completed successfully!"
        Write-InfoMessage "NOTE: Close and reopen your terminal to refresh environment variables"
    }
    else {
        Write-ColorOutput "`nSETUP FAILED" -Color Red
        Write-ColorOutput "============" -Color Red
        Write-ColorOutput "Please review the errors above and:" -Color White
        Write-ColorOutput "  1. Address any system requirement issues" -Color White
        Write-ColorOutput "  2. Check your internet connection" -Color White
        Write-ColorOutput "  3. Review the configuration file for correctness" -Color White
        Write-ColorOutput "  4. Re-run this script after resolving issues" -Color White
    }

    # Show error summary if there were errors
    if ((Get-ErrorLog).Count -gt 0 -or (Get-WarningLog).Count -gt 0) {
        Show-ErrorSummary
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

try {
    # Initialize
    Initialize-ErrorHandling

    # Show welcome banner (skip in CI/CD mode)
    if ($LocalDeveloper) {
        Show-WelcomeBanner
    }
    else {
        Write-InfoMessage "Running in CI/CD mode (non-interactive, minimal checks)"
    }

    # Confirm user wants to proceed (auto-proceeds in CI/CD mode)
    if (-not (Confirm-Proceed -LocalDeveloper:$LocalDeveloper)) {
        exit 0
    }

    # Pre-flight checks
    Write-ColorOutput "`nStarting setup process..." -Color Cyan
    $preFlightSuccess = Invoke-PreFlightChecks -ConfigPath $ConfigPath -LocalDeveloper:$LocalDeveloper

    if (-not $preFlightSuccess) {
        Write-ErrorLog -Message "Pre-flight checks failed. Setup cannot continue." -Fatal
    }

    # Execute installation scripts
    $installSuccess = $true

    # Install development tools
    $installSuccess = Invoke-DevelopmentToolsInstallation -ConfigPath $ConfigPath

    # Display final summary
    Show-FinalSummary -Success $installSuccess

    # Exit with appropriate code
    if ($installSuccess) {
        exit 0
    }
    else {
        exit 1
    }
}
catch {
    Write-ErrorLog -Message "Fatal error in setup script" -Exception $_.Exception -Fatal
    Show-FinalSummary -Success $false
    exit 1
}
finally {
    # Cleanup
    $ProgressPreference = 'Continue'
}
