#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Main orchestrator script for development environment setup
.DESCRIPTION
    Coordinates the execution of all setup scripts in the correct order.
    This script manages the complete development environment installation process.
.PARAMETER ConfigPath
    Path to the configuration file (default: .\config\tools-config.json)
.PARAMETER SkipSystemCheck
    Skip system requirements validation
.PARAMETER ToolsOnly
    Only install development tools (default behavior)
.EXAMPLE
    .\setup.ps1
.EXAMPLE
    .\setup.ps1 -SkipSystemCheck
.NOTES
    This script must be run as Administrator
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "$PSScriptRoot\config\tools-config.json",

    [Parameter(Mandatory = $false)]
    [switch]$SkipSystemCheck,

    [Parameter(Mandatory = $false)]
    [switch]$ToolsOnly
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
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

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
        [switch]$SkipSystemCheck
    )

    Write-SectionHeader "Pre-Flight Checks"

    # Check 1: Admin privileges
    Write-ProgressMessage "Checking administrator privileges..."
    Assert-IsAdmin -ScriptName "Development Environment Setup"

    # Check 2: Configuration file
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

    # Check 3: System requirements
    if (-not $SkipSystemCheck) {
        Write-ProgressMessage "Checking system requirements..."
        $systemInfo = Get-SystemInformation
        Show-SystemInformation -SystemInfo $systemInfo

        Test-SystemRequirements -ConfigPath $ConfigPath | Out-Null
        Test-InternetConnection | Out-Null
    }
    else {
        Write-WarningMessage "System requirements check skipped (as requested)"
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
        [string]$ConfigPath,

        [Parameter(Mandatory = $false)]
        [switch]$SkipSystemCheck
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

        if ($SkipSystemCheck) {
            $params.SkipSystemCheck = $true
        }

        & $scriptPath @params

        if ($LASTEXITCODE -eq 0) {
            Write-SuccessMessage "Development tools installation completed"
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
        Write-ColorOutput "`nREQUIRED NEXT STEPS:" -Color Green
        Write-ColorOutput "===================" -Color Green
        Write-ColorOutput "1. CLOSE this PowerShell window" -Color White
        Write-ColorOutput "2. OPEN a new PowerShell window as Administrator" -Color White
        Write-ColorOutput "3. Run the following commands to verify installations:" -Color White
        Write-ColorOutput "" -Color White
        Write-ColorOutput "   choco --version" -Color Cyan
        Write-ColorOutput "   nvm version" -Color Cyan
        Write-ColorOutput "   node --version" -Color Cyan
        Write-ColorOutput "   yarn --version" -Color Cyan
        Write-ColorOutput "   dotnet --version" -Color Cyan
        Write-ColorOutput "   aws --version" -Color Cyan
        Write-ColorOutput "   docker --version" -Color Cyan
        Write-ColorOutput "" -Color White
        Write-ColorOutput "4. Review any warnings or errors listed above" -Color White
    }
    else {
        Write-ColorOutput "`nSETUP FAILED" -Color Red
        Write-ColorOutput "============" -Color Red
        Write-ColorOutput "Please review the errors above and:" -Color White
        Write-ColorOutput "1. Address any system requirement issues" -Color White
        Write-ColorOutput "2. Check your internet connection" -Color White
        Write-ColorOutput "3. Review the configuration file for correctness" -Color White
        Write-ColorOutput "4. Re-run this script after resolving issues" -Color White
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

    # Show welcome banner
    Show-WelcomeBanner

    # Confirm user wants to proceed
    if (-not (Confirm-Proceed)) {
        exit 0
    }

    # Pre-flight checks
    Write-ColorOutput "`nStarting setup process..." -Color Cyan
    $preFlightSuccess = Invoke-PreFlightChecks -ConfigPath $ConfigPath -SkipSystemCheck:$SkipSystemCheck

    if (-not $preFlightSuccess) {
        Write-ErrorLog -Message "Pre-flight checks failed. Setup cannot continue." -Fatal
    }

    # Execute installation scripts
    $installSuccess = $true

    # Install development tools (always runs as this is the first script)
    $installSuccess = Invoke-DevelopmentToolsInstallation -ConfigPath $ConfigPath -SkipSystemCheck:$SkipSystemCheck

    # Display final summary
    Show-FinalSummary -Success $installSuccess

    # Exit with appropriate code
    if ($installSuccess) {
        Write-SuccessMessage "`nSetup completed successfully!"
        exit 0
    }
    else {
        Write-ErrorMessage "`nSetup completed with errors. Please review the log above."
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
