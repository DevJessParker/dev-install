#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs development tools based on configuration file
.DESCRIPTION
    Installs and configures development tools including Node.js, .NET, AWS CLI, Docker, and more
    based on versions specified in config/tools-config.json
.PARAMETER ConfigPath
    Path to the configuration file (default: ..\config\tools-config.json)
.PARAMETER SkipSystemCheck
    Skip system requirements validation
.EXAMPLE
    .\Install-DevelopmentTools.ps1
.EXAMPLE
    .\Install-DevelopmentTools.ps1 -ConfigPath "C:\custom\config.json"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "$PSScriptRoot\..\config\tools-config.json",

    [Parameter(Mandatory = $false)]
    [switch]$SkipSystemCheck
)

# Script initialization
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Import required modules
$modulePath = "$PSScriptRoot\..\modules"
Import-Module "$modulePath\AdminCheck.psm1" -Force
Import-Module "$modulePath\ColorConfig.psm1" -Force
Import-Module "$modulePath\ErrorHandling.psm1" -Force
Import-Module "$modulePath\SystemCheck.psm1" -Force
Import-Module "$modulePath\VersionManagement.psm1" -Force

# Script-level variables
$script:installedTools = @()
$script:skippedTools = @()
$script:failedTools = @()
$script:updatedTools = @()

function Install-Chocolatey {
    <#
    .SYNOPSIS
        Installs Chocolatey package manager if not already installed
    #>
    [CmdletBinding()]
    param()

    Write-ProgressMessage "Checking Chocolatey installation..."

    try {
        $chocoCmd = Get-Command choco -ErrorAction SilentlyContinue

        if ($chocoCmd) {
            $chocoVersion = choco --version 2>$null
            Write-SuccessMessage "Chocolatey is already installed (version: $chocoVersion)"
            return $true
        }

        Write-InfoMessage "Chocolatey not found. Installing Chocolatey..."

        # Set execution policy for this process
        Set-ExecutionPolicy Bypass -Scope Process -Force

        # Download and install Chocolatey
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

        $installScript = Invoke-WebRequest -Uri 'https://community.chocolatey.org/install.ps1' -UseBasicParsing

        Invoke-Expression $installScript.Content

        # Refresh environment variables
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

        # Verify installation
        $chocoCmd = Get-Command choco -ErrorAction SilentlyContinue
        if ($chocoCmd) {
            $chocoVersion = choco --version 2>$null
            Write-SuccessMessage "Chocolatey installed successfully (version: $chocoVersion)"

            # Configure Chocolatey
            choco feature enable -n allowGlobalConfirmation 2>&1 | Out-Null
            Write-InfoMessage "Chocolatey global confirmation enabled"

            return $true
        }
        else {
            Write-ErrorLog -Message "Chocolatey installation verification failed" -Fatal
            return $false
        }
    }
    catch {
        Write-ErrorLog -Message "Failed to install Chocolatey" -Exception $_.Exception -Fatal
        return $false
    }
}

function Install-ChocolateyPackage {
    <#
    .SYNOPSIS
        Installs a package using Chocolatey
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$ToolName,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    Write-ProgressMessage "Installing $ToolName via Chocolatey..."

    try {
        $chocoArgs = @("install", $PackageName, "-y")

        # Add version if not "latest"
        if ($Version -ne "latest") {
            $chocoArgs += "--version=$Version"
        }

        if ($Force) {
            $chocoArgs += "--force"
        }

        # Install package
        & choco @chocoArgs 2>&1 | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-SuccessMessage "$ToolName installed successfully"
            $script:installedTools += $ToolName
            return $true
        }
        else {
            Write-ErrorLog -Message "Failed to install $ToolName (exit code: $LASTEXITCODE)"
            $script:failedTools += $ToolName
            return $false
        }
    }
    catch {
        Write-ErrorLog -Message "Exception during $ToolName installation" -Exception $_.Exception
        $script:failedTools += $ToolName
        return $false
    }
}

function Install-PowerShellModule {
    <#
    .SYNOPSIS
        Installs a PowerShell module from PowerShell Gallery
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$ToolName,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    Write-ProgressMessage "Installing $ToolName from PowerShell Gallery..."

    try {
        $installParams = @{
            Name               = $ModuleName
            Force              = $Force.IsPresent
            AllowClobber       = $true
            Scope              = "AllUsers"
            SkipPublisherCheck = $true
        }

        # Add version if not "latest"
        if ($Version -ne "latest") {
            $installParams.RequiredVersion = $Version
        }

        Install-Module @installParams -ErrorAction Stop

        Write-SuccessMessage "$ToolName installed successfully"
        $script:installedTools += $ToolName
        return $true
    }
    catch {
        Write-ErrorLog -Message "Failed to install $ToolName" -Exception $_.Exception
        $script:failedTools += $ToolName
        return $false
    }
}

function Install-NodeViaNvm {
    <#
    .SYNOPSIS
        Installs Node.js via NVM and sets it as default
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    Write-ProgressMessage "Installing Node.js $Version via NVM..."

    try {
        # Refresh environment to ensure nvm is available
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

        # Check if NVM is available
        $nvmCmd = Get-Command nvm -ErrorAction SilentlyContinue
        if (-not $nvmCmd) {
            Write-ErrorLog -Message "NVM is not available. Please ensure NVM is installed first." -Fatal
            return $false
        }

        # Install Node version
        Write-InfoMessage "Running: nvm install $Version"
        nvm install $Version 2>&1 | Out-Null

        if ($LASTEXITCODE -ne 0) {
            Write-ErrorLog -Message "Failed to install Node.js $Version via NVM"
            $script:failedTools += "Node.js $Version"
            return $false
        }

        # Set as default
        Write-InfoMessage "Setting Node.js $Version as default"
        nvm use $Version 2>&1 | Out-Null

        if ($LASTEXITCODE -ne 0) {
            Write-WarningLog "Failed to set Node.js $Version as default"
        }

        # Verify installation
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        $nodeVersion = node --version 2>$null

        if ($nodeVersion) {
            Write-SuccessMessage "Node.js installed successfully (version: $nodeVersion)"
            $script:installedTools += "Node.js $Version"
            return $true
        }
        else {
            Write-WarningLog "Node.js installation could not be verified"
            return $false
        }
    }
    catch {
        Write-ErrorLog -Message "Exception during Node.js installation" -Exception $_.Exception
        $script:failedTools += "Node.js $Version"
        return $false
    }
}

function Update-EnvironmentPath {
    <#
    .SYNOPSIS
        Refreshes the PATH environment variable
    #>
    [CmdletBinding()]
    param()

    try {
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        Write-InfoMessage "Environment PATH refreshed"
    }
    catch {
        Write-WarningLog "Failed to refresh environment PATH: $($_.Exception.Message)"
    }
}

function Install-DevelopmentTools {
    <#
    .SYNOPSIS
        Main function to install all development tools
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    Write-HeaderMessage "Development Tools Installation"

    # Validate config file exists
    if (-not (Test-Path $ConfigPath)) {
        Write-ErrorLog -Message "Configuration file not found: $ConfigPath" -Fatal
        return $false
    }

    # Load configuration
    try {
        $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
        Write-SuccessMessage "Configuration loaded from: $ConfigPath"
    }
    catch {
        Write-ErrorLog -Message "Failed to load configuration file" -Exception $_.Exception -Fatal
        return $false
    }

    # Get installation order
    $installOrder = $config.installationOrder
    $tools = $config.developmentTools

    Write-InfoMessage "Total tools to process: $($installOrder.Count)"

    # Process each tool in order
    $stepNumber = 1
    $totalSteps = $installOrder.Count

    foreach ($toolKey in $installOrder) {
        Write-StepMessage -StepNumber $stepNumber -TotalSteps $totalSteps -Message "Processing: $toolKey"

        $tool = $tools.$toolKey
        if (-not $tool) {
            Write-WarningLog "Tool configuration not found for: $toolKey"
            $stepNumber++
            continue
        }

        $toolName = $toolKey
        $version = $tool.version
        $source = $tool.source
        $packageName = if ($tool.packageName) { $tool.packageName } else { $toolKey }

        # Special handling for Chocolatey
        if ($toolKey -eq "chocolatey") {
            Install-Chocolatey
            $stepNumber++
            continue
        }

        # Check current version
        $installedVersion = Get-InstalledToolVersion -ToolName $toolKey -PackageName $packageName -Source $source
        $versionCheck = Test-ToolVersion -InstalledVersion $installedVersion -RequiredVersion $version -ToolName $toolName -AllowNewer $false

        # Determine action needed
        if ($versionCheck.VersionMatch -and -not $versionCheck.NeedsInstall) {
            Write-InfoMessage "$toolName is already at the correct version ($installedVersion)"
            $script:skippedTools += $toolName
            $stepNumber++
            continue
        }

        # Uninstall if version mismatch
        if ($versionCheck.IsInstalled -and ($versionCheck.NeedsUpgrade -or $versionCheck.NeedsDowngrade)) {
            Write-WarningMessage "Removing existing $toolName version $installedVersion"

            if ($source -eq "chocolatey") {
                choco uninstall $packageName -y 2>&1 | Out-Null
            }
            elseif ($source -eq "powershellgallery") {
                Uninstall-Module -Name $packageName -AllVersions -Force -ErrorAction SilentlyContinue
            }

            Update-EnvironmentPath
            $script:updatedTools += "$toolName (upgraded from $installedVersion to $version)"
        }

        # Install based on source
        switch ($source.ToLower()) {
            "chocolatey" {
                Install-ChocolateyPackage -PackageName $packageName -Version $version -ToolName $toolName -Force
            }
            "powershellgallery" {
                Install-PowerShellModule -ModuleName $packageName -Version $version -ToolName $toolName -Force
            }
            "nvm" {
                # Special handling for Node.js via NVM
                Install-NodeViaNvm -Version $version
            }
            default {
                Write-WarningLog "Unknown installation source: $source for $toolName"
            }
        }

        # Refresh environment after installation
        Update-EnvironmentPath

        $stepNumber++
    }

    Write-SuccessMessage "Tool installation process completed"
    return $true
}

# Main execution
try {
    Write-HeaderMessage "Development Environment Setup - Tool Installation"

    # Step 1: Verify admin privileges
    Write-StepMessage -StepNumber 1 -TotalSteps 5 -Message "Verifying administrator privileges"
    Assert-IsAdmin -ScriptName "Install-DevelopmentTools.ps1"

    # Step 2: Gather and display system information
    Write-StepMessage -StepNumber 2 -TotalSteps 5 -Message "Gathering system information"
    $systemInfo = Get-SystemInformation
    Show-SystemInformation -SystemInfo $systemInfo

    # Step 3: Check system requirements
    if (-not $SkipSystemCheck) {
        Write-StepMessage -StepNumber 3 -TotalSteps 5 -Message "Validating system requirements"
        Test-SystemRequirements -ConfigPath $ConfigPath
        Test-InternetConnection | Out-Null
    }
    else {
        Write-WarningMessage "System requirements check skipped"
    }

    # Step 4: Install development tools
    Write-StepMessage -StepNumber 4 -TotalSteps 5 -Message "Installing development tools"
    Install-DevelopmentTools -ConfigPath $ConfigPath

    # Step 5: Display summary
    Write-StepMessage -StepNumber 5 -TotalSteps 5 -Message "Generating summary report"

    $summaryData = [ordered]@{
        "Installed Tools"      = if ($script:installedTools.Count -gt 0) { $script:installedTools } else { @("None") }
        "Updated Tools"        = if ($script:updatedTools.Count -gt 0) { $script:updatedTools } else { @("None") }
        "Skipped Tools"        = if ($script:skippedTools.Count -gt 0) { $script:skippedTools } else { @("None") }
        "Failed Tools"         = if ($script:failedTools.Count -gt 0) { $script:failedTools } else { @("None") }
        "Total Errors"         = (Get-ErrorLog).Count
        "Total Warnings"       = (Get-WarningLog).Count
        "Script Duration"      = "{0:N2} minutes" -f ((Get-Date) - $PSCommandPath.StartTime).TotalMinutes
        "Completion Time"      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }

    Write-DevSummary -Title "DEVELOPMENT TOOLS INSTALLATION - SUMMARY" -Sections $summaryData

    # Show detailed error summary if errors occurred
    if ((Get-ErrorLog).Count -gt 0 -or (Get-WarningLog).Count -gt 0) {
        Show-ErrorSummary
    }

    # Prompt user for next steps
    Write-ColorOutput "`nNext Steps:" -Color Cyan
    Write-ColorOutput "1. Close and reopen your terminal to refresh environment variables" -Color White
    Write-ColorOutput "2. Verify installations by running version checks for each tool" -Color White
    Write-ColorOutput "3. Review any warnings or errors listed above" -Color White

    if ($script:failedTools.Count -gt 0) {
        Write-ColorOutput "`nWARNING: Some tools failed to install. Please review the errors above." -Color Yellow
        exit 1
    }

    Write-SuccessMessage "Development tools installation completed successfully!"
    exit 0
}
catch {
    Write-ErrorLog -Message "Unhandled exception in installation script" -Exception $_.Exception -Fatal
    exit 1
}
