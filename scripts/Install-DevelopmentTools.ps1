#Requires -Version 5.1

<#
.SYNOPSIS
    Installs development tools based on configuration file
.DESCRIPTION
    Installs and configures development tools including Node.js, .NET, AWS CLI, Docker, and more
    based on versions specified in config/tools-config.json

    NOTE: This script is called by setup.ps1 which handles admin checks and system requirements.
    Do not run this script directly unless you know what you're doing.
.PARAMETER ConfigPath
    Path to the configuration file (default: ..\config\tools-config.json)
.EXAMPLE
    .\Install-DevelopmentTools.ps1
.EXAMPLE
    .\Install-DevelopmentTools.ps1 -ConfigPath "C:\custom\config.json"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "$PSScriptRoot\..\config\tools-config.json"
)

# =============================================================================
# INITIALIZATION CODE
# Only runs when script is executed directly, not when dot-sourced
# =============================================================================
$script:IsBeingDotSourced = $MyInvocation.InvocationName -eq '.'

if (-not $script:IsBeingDotSourced) {
    # Resolve ConfigPath to absolute path immediately to avoid context issues in jobs
    if (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
        $ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath $ConfigPath | Resolve-Path -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path
        if (-not $ConfigPath) {
            # If Resolve-Path fails (file doesn't exist yet), construct absolute path manually
            $ConfigPath = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath "..\config\tools-config.json"))
        }
    }

    # Script initialization
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    $script:ScriptStartTime = Get-Date
    $script:CancellationRequested = $false

    # CTRL+C handler for graceful exit
    trap {
        $script:CancellationRequested = $true
        Write-Host "`n`nCTRL+C detected. Cleaning up and exiting..." -ForegroundColor Yellow

        # Clean up any running background jobs
        $runningJobs = Get-Job | Where-Object { $_.State -eq 'Running' }
        if ($runningJobs) {
            Write-Host "Stopping $($runningJobs.Count) background job(s)..." -ForegroundColor Yellow
            $runningJobs | Stop-Job
            $runningJobs | Remove-Job -Force
        }

        Write-Host "Cleanup complete. Exiting..." -ForegroundColor Gray
        exit 130  # Standard exit code for CTRL+C
    }

    # OS Detection
    $script:IsWindows = ($PSVersionTable.PSVersion.Major -le 5) -or $IsWindows
    $script:IsLinux = (Get-Variable -Name "IsLinux" -ErrorAction SilentlyContinue) -and $IsLinux
    $script:IsMacOS = (Get-Variable -Name "IsMacOS" -ErrorAction SilentlyContinue) -and $IsMacOS

    # Early exit for non-Windows platforms
    if (-not $script:IsWindows) {
        Write-Host "================================================================" -ForegroundColor Yellow
        Write-Host "     PLATFORM NOT SUPPORTED" -ForegroundColor Yellow
        Write-Host "================================================================" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "This installation script is designed for Windows environments." -ForegroundColor White
        Write-Host "Detected OS: $($PSVersionTable.OS)" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "For Linux/macOS installations, please use platform-specific" -ForegroundColor White
        Write-Host "package managers (apt, yum, brew, etc.)." -ForegroundColor White
        Write-Host ""
        Write-Host "Exiting gracefully..." -ForegroundColor Gray
        exit 0
    }

    # Import required modules (using Join-Path for cross-platform compatibility)
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath ".." | Join-Path -ChildPath "modules"
    Import-Module (Join-Path -Path $modulePath -ChildPath "AdminCheck.psm1") -Force
    Import-Module (Join-Path -Path $modulePath -ChildPath "ColorConfig.psm1") -Force
    Import-Module (Join-Path -Path $modulePath -ChildPath "ErrorHandling.psm1") -Force
    Import-Module (Join-Path -Path $modulePath -ChildPath "SystemCheck.psm1") -Force
    Import-Module (Join-Path -Path $modulePath -ChildPath "VersionManagement.psm1") -Force

    # Early validation: Fail fast if configuration file doesn't exist
    if (-not (Test-Path -Path $ConfigPath -PathType Leaf)) {
        Write-Host "================================================================" -ForegroundColor Red
        Write-Host "     CONFIGURATION FILE NOT FOUND" -ForegroundColor Red
        Write-Host "================================================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "ERROR: Configuration file not found:" -ForegroundColor Red
        Write-Host "  $ConfigPath" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Expected location:" -ForegroundColor White
        Write-Host "  $PSScriptRoot\..\config\tools-config.json" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Please ensure the configuration file exists before running this script." -ForegroundColor White
        Write-Host ""
        exit 1
    }
}

# =============================================================================
# SCRIPT-LEVEL VARIABLES
# Always initialized, regardless of how script is loaded
# =============================================================================
$script:installedTools = @()
$script:skippedTools = @()
$script:failedTools = @()
$script:updatedTools = @()

function Add-InstalledTool {
    <#
    .SYNOPSIS
        Adds a tool to the installed tools list with version information
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$Version = "Unknown"
    )

    $script:installedTools += [PSCustomObject]@{
        Name    = $Name
        Version = $Version
    }
}

function Add-SkippedTool {
    <#
    .SYNOPSIS
        Adds a tool to the skipped tools list with version information
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$Version = "Unknown",

        [Parameter(Mandatory = $false)]
        [string]$Reason = "Already installed"
    )

    $script:skippedTools += [PSCustomObject]@{
        Name    = $Name
        Version = $Version
        Reason  = $Reason
    }
}

function Add-UpdatedTool {
    <#
    .SYNOPSIS
        Adds a tool to the updated tools list with version information
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$OldVersion = "Unknown",

        [Parameter(Mandatory = $false)]
        [string]$NewVersion = "Unknown"
    )

    $script:updatedTools += [PSCustomObject]@{
        Name       = $Name
        OldVersion = $OldVersion
        NewVersion = $NewVersion
    }
}

function Add-FailedTool {
    <#
    .SYNOPSIS
        Adds a tool to the failed tools list
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$Reason = "Installation failed"
    )

    $script:failedTools += [PSCustomObject]@{
        Name   = $Name
        Reason = $Reason
    }
}

function Format-ToolTable {
    <#
    .SYNOPSIS
        Formats tool information as a readable table
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$Tools,

        [Parameter(Mandatory = $true)]
        [string]$Type
    )

    if ($Tools.Count -eq 0) {
        Write-ColorOutput "  None" -Color DarkGray
        return
    }

    Write-ColorOutput "" -Color White

    switch ($Type) {
        "Installed" {
            foreach ($tool in $Tools) {
                Write-ColorOutput "  $($tool.Name)" -Color Green -NoNewline
                Write-ColorOutput " - " -Color DarkGray -NoNewline
                Write-ColorOutput "v$($tool.Version)" -Color Cyan
            }
        }
        "Skipped" {
            foreach ($tool in $Tools) {
                Write-ColorOutput "  $($tool.Name)" -Color Yellow -NoNewline
                Write-ColorOutput " - " -Color DarkGray -NoNewline
                Write-ColorOutput "v$($tool.Version)" -Color Cyan -NoNewline
                Write-ColorOutput " ($($tool.Reason))" -Color DarkGray
            }
        }
        "Updated" {
            foreach ($tool in $Tools) {
                Write-ColorOutput "  $($tool.Name)" -Color Magenta -NoNewline
                Write-ColorOutput " - " -Color DarkGray -NoNewline
                Write-ColorOutput "v$($tool.OldVersion)" -Color Red -NoNewline
                Write-ColorOutput " → " -Color DarkGray -NoNewline
                Write-ColorOutput "v$($tool.NewVersion)" -Color Green
            }
        }
        "Failed" {
            foreach ($tool in $Tools) {
                Write-ColorOutput "  $($tool.Name)" -Color Red -NoNewline
                Write-ColorOutput " - $($tool.Reason)" -Color DarkGray
            }
        }
    }
}

function Initialize-PSGallery {
    <#
    .SYNOPSIS
        Sets PSGallery as trusted and installs NuGet provider
    .DESCRIPTION
        Configures PSGallery as a trusted repository and ensures NuGet provider
        is installed for CI/CD environments (TeamCity, GitHub Actions, etc.)
    #>
    [CmdletBinding()]
    param()

    Write-ProgressMessage "Configuring PSGallery and NuGet provider..."

    try {
        # Install NuGet provider if not present (required for PowerShell Gallery)
        Write-InfoMessage "Checking NuGet provider..."
        $nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue

        if (-not $nugetProvider) {
            Write-InfoMessage "Installing NuGet provider..."
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop | Out-Null
            Write-SuccessMessage "NuGet provider installed successfully"
        }
        else {
            Write-InfoMessage "NuGet provider already installed (version: $($nugetProvider.Version))"
        }

        # Set PSGallery as trusted
        Write-InfoMessage "Setting PSGallery as trusted repository..."
        $psGallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue

        if ($psGallery) {
            if ($psGallery.InstallationPolicy -ne 'Trusted') {
                Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
                Write-SuccessMessage "PSGallery set as trusted"
            }
            else {
                Write-InfoMessage "PSGallery is already trusted"
            }
        }
        else {
            Write-WarningLog "PSGallery repository not found. Registering..."
            Register-PSRepository -Default -ErrorAction Stop
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
            Write-SuccessMessage "PSGallery registered and set as trusted"
        }
    }
    catch {
        Write-WarningLog "Failed to configure PSGallery: $($_.Exception.Message)"
        # Non-fatal, continue execution
    }
}

function Install-PowerShellGet {
    <#
    .SYNOPSIS
        Installs or updates PowerShellGet module
    .DESCRIPTION
        Ensures PowerShellGet is installed and updated for module management.
        Handles common errors in CI/CD environments.
    #>
    [CmdletBinding()]
    param()

    Write-ProgressMessage "Checking PowerShellGet installation..."

    try {
        # Check current version
        $currentPSGet = Get-Module -Name PowerShellGet -ListAvailable |
                        Sort-Object Version -Descending |
                        Select-Object -First 1

        if ($currentPSGet) {
            Write-InfoMessage "PowerShellGet already installed (version: $($currentPSGet.Version))"

            # Check if update is needed
            $latestVersion = Find-Module -Name PowerShellGet -ErrorAction SilentlyContinue
            if ($latestVersion -and $latestVersion.Version -gt $currentPSGet.Version) {
                Write-InfoMessage "Updating PowerShellGet from $($currentPSGet.Version) to $($latestVersion.Version)..."

                try {
                    Install-Module -Name PowerShellGet -Force -AllowClobber -SkipPublisherCheck -Scope AllUsers -ErrorAction Stop
                    Write-SuccessMessage "PowerShellGet updated successfully"
                    Add-UpdatedTool -Name "PowerShellGet" -OldVersion $currentPSGet.Version -NewVersion $latestVersion.Version
                }
                catch {
                    Write-WarningLog "Could not update PowerShellGet: $($_.Exception.Message)"
                    Write-InfoMessage "Continuing with current version"
                }
            }
            else {
                Add-SkippedTool -Name "PowerShellGet" -Version $currentPSGet.Version -Reason "Already latest"
            }
        }
        else {
            Write-InfoMessage "Installing PowerShellGet..."
            Install-Module -Name PowerShellGet -Force -AllowClobber -SkipPublisherCheck -Scope AllUsers -ErrorAction Stop
            Write-SuccessMessage "PowerShellGet installed successfully"
            $latestInstalled = Get-Module -Name PowerShellGet -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
            Add-InstalledTool -Name "PowerShellGet" -Version $latestInstalled.Version
        }

        # Import the module
        Import-Module -Name PowerShellGet -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-WarningLog "Failed to install/update PowerShellGet: $($_.Exception.Message)"
        # Check if we can continue with existing version
        if (-not $currentPSGet) {
            Write-ErrorLog -Message "PowerShellGet is required but could not be installed" -Fatal
        }
        else {
            Write-InfoMessage "Continuing with existing PowerShellGet version"
        }
    }
}

function Import-ChocolateyProfile {
    <#
    .SYNOPSIS
        Imports the Chocolatey profile module for Update-SessionEnvironment
    #>
    [CmdletBinding()]
    param()

    try {
        $chocoProfilePath = Join-Path -Path $env:ChocolateyInstall -ChildPath "helpers\chocolateyProfile.psm1"

        if (Test-Path $chocoProfilePath) {
            Import-Module $chocoProfilePath -Force -ErrorAction SilentlyContinue
            Write-InfoMessage "Chocolatey profile imported (Update-SessionEnvironment available)"
            return $true
        }
        else {
            Write-WarningLog "Chocolatey profile not found at: $chocoProfilePath"
            return $false
        }
    }
    catch {
        Write-WarningLog "Failed to import Chocolatey profile: $($_.Exception.Message)"
        return $false
    }
}

function Update-SessionEnvironment {
    <#
    .SYNOPSIS
        Refreshes environment variables in the current session
    .DESCRIPTION
        Uses Chocolatey's Update-SessionEnvironment if available,
        otherwise falls back to manual refresh
    #>
    [CmdletBinding()]
    param()

    try {
        # Check if Chocolatey's Update-SessionEnvironment is available (not our own function)
        $chocoCommand = Get-Command Update-SessionEnvironment -ErrorAction SilentlyContinue |
            Where-Object { $_.Source -like '*chocolatey*' -or $_.ModuleName -like '*chocolatey*' }

        if ($chocoCommand) {
            # Call Chocolatey's Update-SessionEnvironment using the full command object
            & $chocoCommand
            Write-InfoMessage "Environment variables refreshed via Chocolatey's Update-SessionEnvironment"
        }
        else {
            # Fallback: Manual environment variable refresh
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
            Write-InfoMessage "Environment PATH refreshed (manual method)"
        }
    }
    catch {
        Write-WarningLog "Failed to refresh environment: $($_.Exception.Message)"
    }
}

function Install-Chocolatey {
    <#
    .SYNOPSIS
        Installs or upgrades Chocolatey package manager
    .DESCRIPTION
        Installs Chocolatey if not present, or upgrades to latest if outdated.
        Configures enhanced exit codes, proxy support, and retry logic.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        $Config
    )

    Write-ProgressMessage "Checking Chocolatey installation..."

    try {
        # Check if Chocolatey is installed
        $chocoCmd = Get-Command choco -ErrorAction SilentlyContinue

        # Get version, filtering out error messages
        $currentVersion = $null
        if ($chocoCmd) {
            $versionOutput = choco --version 2>&1 | Out-String
            # Extract only the version number (first line that looks like a version)
            $versionLine = $versionOutput -split "`n" | Where-Object { $_ -match '^\d+\.\d+\.\d+' } | Select-Object -First 1
            $currentVersion = $versionLine.Trim()

            # Check if we got errors instead of version
            if ([string]::IsNullOrEmpty($currentVersion) -or $versionOutput -match 'error|timeout|exception') {
                Write-WarningLog "Chocolatey command returned errors. It may be locked by another process."
                Write-InfoMessage "Chocolatey appears to be installed but may be in use. Continuing..."
                # Set a generic version to indicate it's installed
                $currentVersion = "installed"
            }
        }

        if ($chocoCmd -and $currentVersion) {
            Write-InfoMessage "Chocolatey is installed (version: $currentVersion)"

            # Check if upgrade is needed
            if ($Config -and $Config.upgradeIfOutdated) {
                Write-ProgressMessage "Checking for Chocolatey updates..."
                $upgradeOutput = choco upgrade chocolatey -y --limit-output 2>&1

                if ($LASTEXITCODE -eq 0) {
                    $newVersion = choco --version 2>$null
                    if ($newVersion -ne $currentVersion) {
                        Write-SuccessMessage "Chocolatey upgraded: $currentVersion → $newVersion"
                        Update-SessionEnvironment
                    }
                    else {
                        Write-InfoMessage "Chocolatey is already at the latest version"
                    }
                }
            }
        }
        else {
            Write-InfoMessage "Chocolatey not found. Installing Chocolatey..."

            # Set execution policy for this process
            Set-ExecutionPolicy Bypass -Scope Process -Force

            # Configure TLS 1.2
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

            # Set proxy if configured
            if ($env:HTTP_PROXY -or $env:HTTPS_PROXY) {
                Write-InfoMessage "HTTP/HTTPS proxy detected, using system proxy settings"
                [System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
            }

            # Download and install Chocolatey with retry logic
            $maxRetries = if ($Config -and $Config.retryCount) { $Config.retryCount } else { 3 }
            $retryDelay = if ($Config -and $Config.retryDelaySeconds) { $Config.retryDelaySeconds } else { 5 }
            $installed = $false
            $retryCount = 0

            while (-not $installed -and $retryCount -lt $maxRetries) {
                try {
                    Write-InfoMessage "Downloading Chocolatey installer (attempt $($retryCount + 1)/$maxRetries)..."
                    $installScript = Invoke-WebRequest -Uri 'https://community.chocolatey.org/install.ps1' -UseBasicParsing -TimeoutSec 30

                    Write-InfoMessage "Running Chocolatey installer..."
                    Invoke-Expression $installScript.Content

                    $installed = $true
                }
                catch {
                    $retryCount++
                    if ($retryCount -lt $maxRetries) {
                        Write-WarningLog "Download failed (attempt $retryCount/$maxRetries). Retrying in $retryDelay seconds..."
                        Start-Sleep -Seconds $retryDelay
                    }
                    else {
                        throw "Failed to download Chocolatey after $maxRetries attempts: $($_.Exception.Message)"
                    }
                }
            }

            # Refresh environment
            Update-SessionEnvironment

            # Verify installation
            $chocoCmd = Get-Command choco -ErrorAction SilentlyContinue
            if ($chocoCmd) {
                $chocoVersion = choco --version 2>$null
                Write-SuccessMessage "Chocolatey installed successfully (version: $chocoVersion)"
            }
            else {
                Write-ErrorLog -Message "Chocolatey installation verification failed" -Fatal
                return
            }
        }

        # Configure Chocolatey features
        Write-InfoMessage "Configuring Chocolatey features..."

        # Enable enhanced exit codes (0=success, non-zero with specific meanings)
        if ($Config -and $Config.useEnhancedExitCodes) {
            choco feature enable -n useEnhancedExitCodes 2>&1 | Out-Null
            Write-InfoMessage "Enhanced exit codes enabled"
        }

        # Note: NOT enabling allowGlobalConfirmation (use -y flag instead)
        Write-InfoMessage "Using -y flag for confirmations (not allowGlobalConfirmation)"

        # Import Chocolatey profile for Update-SessionEnvironment
        Import-ChocolateyProfile | Out-Null

        # Add Chocolatey to installed tools tracking
        $finalVersionOutput = choco --version 2>&1 | Out-String
        $finalVersionLine = $finalVersionOutput -split "`n" | Where-Object { $_ -match '^\d+\.\d+\.\d+' } | Select-Object -First 1
        $finalVersion = if ($finalVersionLine) { $finalVersionLine.Trim() } else { $currentVersion }

        # Ensure we have a string value
        if ([string]::IsNullOrEmpty($finalVersion)) {
            $finalVersion = "installed"
        }

        Add-InstalledTool -Name "Chocolatey" -Version $finalVersion

    }
    catch {
        Write-ErrorLog -Message "Failed to install/configure Chocolatey" -Exception $_.Exception -Fatal
    }
}

function Get-BaseVersionFromExpression {
    <#
    .SYNOPSIS
        Extracts the base version number from a version expression
    .DESCRIPTION
        Strips version range operators (~, ^, >=, >, <=, <) to get the base version number.
        This is needed for package managers that don't support semantic versioning operators.
    .PARAMETER VersionExpression
        The version expression (e.g., "~1.2.3", "^2.0.0", ">=3.1.0", "1.2.3", "latest")
    .EXAMPLE
        Get-BaseVersionFromExpression -VersionExpression "~1.22.22"
        Returns: "1.22.22"
    .EXAMPLE
        Get-BaseVersionFromExpression -VersionExpression ">=2.0.6"
        Returns: "2.0.6"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionExpression
    )

    # Return "latest" as-is
    if ($VersionExpression -eq "latest") {
        return "latest"
    }

    # Strip operators: ~, ^, >=, >, <=, <
    $baseVersion = $VersionExpression -replace '[\^~]|>=|>|<=|<', ''
    $baseVersion = $baseVersion.Trim()

    return $baseVersion
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
        # Extract base version (strip semantic version operators that Chocolatey doesn't understand)
        $chocoVersion = Get-BaseVersionFromExpression -VersionExpression $Version

        Write-InfoMessage "Requesting Chocolatey to install $PackageName version: $chocoVersion (from expression: $Version)"

        $chocoArgs = @("install", $PackageName, "-y")

        # Add version if not "latest"
        if ($chocoVersion -ne "latest") {
            $chocoArgs += "--version=$chocoVersion"
        }

        if ($Force) {
            $chocoArgs += "--force"
        }

        # Add CI/CD and TeamCity-friendly flags
        $chocoArgs += "--accept-license"           # Accept license agreements automatically
        $chocoArgs += "--no-progress"              # Disable progress bars (cleaner CI logs)
        $chocoArgs += "--allow-empty-checksums"    # Allow packages with empty checksums
        $chocoArgs += "--ignore-checksums"         # Skip checksum verification if needed

        # Install package and capture output
        $output = & choco @chocoArgs 2>&1
        $outputString = $output | Out-String

        if ($LASTEXITCODE -eq 0) {
            Write-SuccessMessage "$ToolName installed successfully"
            # Get the installed version
            $installedVer = Get-ChocoPackageVersion -PackageName $PackageName
            Add-InstalledTool -Name $ToolName -Version $(if ($installedVer) { $installedVer } else { $chocoVersion })
        }
        else {
            # Display detailed error information
            Write-ErrorLog -Message "Failed to install $ToolName (exit code: $LASTEXITCODE)"
            Write-ColorOutput "" -Color White
            Write-ColorOutput "Chocolatey Error Details:" -Color Red
            Write-ColorOutput "  Command: choco $($chocoArgs -join ' ')" -Color DarkGray
            Write-ColorOutput "  Exit Code: $LASTEXITCODE" -Color DarkRed
            Write-ColorOutput "" -Color White

            # Show relevant error lines from chocolatey output
            $errorLines = $output | Where-Object { $_ -and $_ -match 'ERROR|error|FAIL|fail|Unable|unable|not found|not installed|invalid|cannot|Cannot' } | Select-Object -First 10
            if ($errorLines -and $errorLines.Count -gt 0) {
                Write-ColorOutput "  Error Output:" -Color Red
                foreach ($line in $errorLines) {
                    $cleanLine = $line.ToString().Trim()
                    if ($cleanLine) {
                        Write-ColorOutput "    $cleanLine" -Color DarkRed
                    }
                }
            }
            else {
                Write-ColorOutput "  No specific error messages found in output." -Color DarkRed
                Write-ColorOutput "  Full output (last 15 lines):" -Color DarkGray
                $lastLines = $output | Select-Object -Last 15
                foreach ($line in $lastLines) {
                    if ($line) {
                        Write-ColorOutput "    $line" -Color DarkGray
                    }
                }
            }
            Write-ColorOutput "" -Color White

            Add-FailedTool -Name $ToolName -Reason "Chocolatey exit code: $LASTEXITCODE"
        }
    }
    catch {
        Write-ErrorLog -Message "Exception during $ToolName installation" -Exception $_.Exception
        Write-ColorOutput "Exception Details:" -Color Red
        Write-ColorOutput "  $($_.Exception.Message)" -Color DarkRed
        Add-FailedTool -Name $ToolName -Reason $_.Exception.Message
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
        # Extract base version (strip semantic version operators)
        $moduleVersion = Get-BaseVersionFromExpression -VersionExpression $Version

        Write-InfoMessage "Requesting PowerShell Gallery to install $ModuleName version: $moduleVersion (from expression: $Version)"

        $installParams = @{
            Name               = $ModuleName
            Force              = $true
            AllowClobber       = $true
            Scope              = "AllUsers"
            SkipPublisherCheck = $true
            Confirm            = $false
        }

        # Add AcceptLicense for CI/CD environments (TeamCity, GitHub Actions, etc.)
        # This prevents license prompts that would block automation
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            # PowerShell 6+ supports -AcceptLicense parameter
            $installParams.AcceptLicense = $true
        }

        # Add version if not "latest"
        if ($moduleVersion -ne "latest") {
            $installParams.RequiredVersion = $moduleVersion
        }

        # Attempt installation with retry logic for common CI/CD issues
        $maxRetries = 3
        $retryCount = 0
        $installed = $false

        while (-not $installed -and $retryCount -lt $maxRetries) {
            try {
                # For PowerShell 5.1, we need to handle license acceptance differently
                if ($PSVersionTable.PSVersion.Major -lt 6) {
                    # Set environment variable to accept license automatically
                    $env:ACCEPT_EULA = 'Y'
                }

                Install-Module @installParams -ErrorAction Stop

                $installed = $true
                Write-SuccessMessage "$ToolName installed successfully"
                # Get the installed version
                $installedVer = Get-PowerShellModuleVersion -ModuleName $ModuleName
                Add-InstalledTool -Name $ToolName -Version $(if ($installedVer) { $installedVer } else { $moduleVersion })
            }
            catch {
                $retryCount++
                if ($retryCount -lt $maxRetries) {
                    Write-WarningLog "Installation attempt $retryCount failed for $ToolName. Retrying..."
                    Start-Sleep -Seconds 2
                }
                else {
                    throw
                }
            }
        }
    }
    catch {
        # Handle common errors in CI/CD environments
        $errorMessage = $_.Exception.Message

        if ($errorMessage -like "*license*") {
            Write-WarningLog "License acceptance issue detected. Attempting workaround..."

            try {
                # Force installation without license check (CI/CD workaround)
                $installParams.Remove('AcceptLicense')
                $env:ACCEPT_EULA = 'Y'
                Install-Module @installParams -ErrorAction Stop
                Write-SuccessMessage "$ToolName installed successfully (license workaround applied)"
                $installedVer = Get-PowerShellModuleVersion -ModuleName $ModuleName
                Add-InstalledTool -Name $ToolName -Version $(if ($installedVer) { $installedVer } else { $moduleVersion })
            }
            catch {
                Write-ErrorLog -Message "Failed to install $ToolName even with license workaround" -Exception $_.Exception
                Write-ColorOutput "PowerShell Gallery Error Details:" -Color Red
                Write-ColorOutput "  $($_.Exception.Message)" -Color DarkRed
                Add-FailedTool -Name $ToolName -Reason "License acceptance failed"
            }
        }
        elseif ($errorMessage -like "*is already installed*") {
            Write-InfoMessage "$ToolName is already installed"
            $installedVer = Get-PowerShellModuleVersion -ModuleName $ModuleName
            Add-SkippedTool -Name $ToolName -Version $(if ($installedVer) { $installedVer } else { "Unknown" }) -Reason "Already installed"
        }
        else {
            Write-ErrorLog -Message "Failed to install $ToolName" -Exception $_.Exception
            Write-ColorOutput "PowerShell Gallery Error Details:" -Color Red
            Write-ColorOutput "  $($_.Exception.Message)" -Color DarkRed
            if ($_.Exception.InnerException) {
                Write-ColorOutput "  Inner Exception: $($_.Exception.InnerException.Message)" -Color DarkRed
            }
            Add-FailedTool -Name $ToolName -Reason $_.Exception.Message
        }
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
        # Extract base version (NVM doesn't understand semantic version operators)
        $nvmVersion = Get-BaseVersionFromExpression -VersionExpression $Version

        Write-InfoMessage "Requesting NVM to install Node.js version: $nvmVersion (from expression: $Version)"

        # Refresh environment to ensure nvm is available
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

        # Check if NVM is available
        $nvmCmd = Get-Command nvm -ErrorAction SilentlyContinue
        if (-not $nvmCmd) {
            Write-ErrorLog -Message "NVM is not available. Please ensure NVM is installed first."
            Write-ColorOutput "NVM Error Details:" -Color Red
            Write-ColorOutput "  NVM command not found. Ensure NVM for Windows is installed and in PATH." -Color DarkRed
            Add-FailedTool -Name "Node.js" -Reason "NVM not available"
            return
        }

        # Install Node version and capture output
        Write-InfoMessage "Running: nvm install $nvmVersion"
        $nvmOutput = nvm install $nvmVersion 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-ErrorLog -Message "Failed to install Node.js $nvmVersion via NVM (exit code: $LASTEXITCODE)"
            Write-ColorOutput "" -Color White
            Write-ColorOutput "NVM Error Details:" -Color Red
            Write-ColorOutput "  Command: nvm install $nvmVersion" -Color DarkGray
            Write-ColorOutput "  Exit Code: $LASTEXITCODE" -Color DarkRed
            Write-ColorOutput "" -Color White

            $errorLines = $nvmOutput | Where-Object { $_ -and $_ -match 'ERROR|error|could not|failed|unable|Cannot|cannot|not found' } | Select-Object -First 10
            if ($errorLines -and $errorLines.Count -gt 0) {
                Write-ColorOutput "  Error Output:" -Color Red
                foreach ($line in $errorLines) {
                    $cleanLine = $line.ToString().Trim()
                    if ($cleanLine) {
                        Write-ColorOutput "    $cleanLine" -Color DarkRed
                    }
                }
            } else {
                Write-ColorOutput "  Full output (last 10 lines):" -Color DarkGray
                $lastLines = $nvmOutput | Select-Object -Last 10
                foreach ($line in $lastLines) {
                    if ($line) {
                        Write-ColorOutput "    $line" -Color DarkGray
                    }
                }
            }
            Write-ColorOutput "" -Color White

            Add-FailedTool -Name "Node.js" -Reason "NVM install failed (exit code: $LASTEXITCODE)"
            return
        }

        # Set as default
        Write-InfoMessage "Setting Node.js $nvmVersion as default"
        nvm use $nvmVersion 2>&1 | Out-Null

        if ($LASTEXITCODE -ne 0) {
            Write-WarningLog "Failed to set Node.js $nvmVersion as default"
        }

        # Verify installation
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        $nodeVersion = node --version 2>$null

        if ($nodeVersion) {
            Write-SuccessMessage "Node.js installed successfully (version: $nodeVersion)"
            Add-InstalledTool -Name "Node.js" -Version $nodeVersion.TrimStart('v')
        }
        else {
            Write-WarningLog "Node.js installation could not be verified"
            Add-FailedTool -Name "Node.js" -Reason "Installation verification failed"
        }
    }
    catch {
        Write-ErrorLog -Message "Exception during Node.js installation" -Exception $_.Exception
        Write-ColorOutput "NVM Error Details:" -Color Red
        Write-ColorOutput "  $($_.Exception.Message)" -Color DarkRed
        Add-FailedTool -Name "Node.js" -Reason $_.Exception.Message
    }
}

function Get-InstallationWaves {
    <#
    .SYNOPSIS
        Organizes tools into installation waves based on dependencies
    .DESCRIPTION
        Groups tools so that:
        - Bootstrap tools (chocolatey, powershellget) are in Wave 0
        - Independent tools are grouped into Wave 1 for parallel installation
        - Tools with dependencies are placed in subsequent waves
    .PARAMETER InstallOrder
        Array of tool keys in installation order
    .PARAMETER Tools
        Hashtable of tool configurations
    .OUTPUTS
        Array of waves, where each wave is an array of tool keys that can be installed in parallel
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$InstallOrder,

        [Parameter(Mandatory = $true)]
        $Tools
    )

    $waves = @()
    $processedTools = @()

    # Wave 0: Bootstrap tools (must be sequential)
    $bootstrapTools = @("chocolatey", "powershellget")
    $waves += ,@($bootstrapTools | Where-Object { $_ -in $InstallOrder })
    $processedTools += $bootstrapTools

    # Build remaining waves based on dependencies
    $remainingTools = $InstallOrder | Where-Object { $_ -notin $processedTools }

    while ($remainingTools.Count -gt 0) {
        $currentWave = @()

        foreach ($toolKey in $remainingTools) {
            $tool = $Tools.$toolKey
            $dependencies = $tool.dependsOn

            # Check if all dependencies are satisfied
            $canInstall = $true
            if ($dependencies) {
                foreach ($dep in $dependencies) {
                    if ($dep -notin $processedTools) {
                        $canInstall = $false
                        break
                    }
                }
            }

            if ($canInstall) {
                $currentWave += $toolKey
            }
        }

        if ($currentWave.Count -eq 0) {
            # No tools can be installed (circular dependency or missing dependency)
            Write-WarningLog "Unable to resolve dependencies for remaining tools: $($remainingTools -join ', ')"
            break
        }

        $waves += ,$currentWave
        $processedTools += $currentWave
        $remainingTools = $remainingTools | Where-Object { $_ -notin $processedTools }
    }

    return $waves
}

function Install-ToolsInParallel {
    <#
    .SYNOPSIS
        Installs multiple tools in parallel using PowerShell jobs
    .PARAMETER ToolKeys
        Array of tool keys to install in parallel
    .PARAMETER Tools
        Hashtable of tool configurations
    .PARAMETER ConfigPath
        Path to configuration file
    .OUTPUTS
        Hashtable with results: @{ Succeeded = @(); Failed = @(); Skipped = @() }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$ToolKeys,

        [Parameter(Mandatory = $true)]
        $Tools,

        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    $results = @{
        Succeeded = @()
        Failed = @()
        Skipped = @()
    }

    # If only one tool, install sequentially (no parallelization overhead)
    if ($ToolKeys.Count -eq 1) {
        $toolKey = $ToolKeys[0]
        $tool = $Tools.$toolKey
        $result = Install-SingleTool -ToolKey $toolKey -Tool $tool -ConfigPath $ConfigPath

        # Update tracking based on result
        if ($result.Status -eq "Success") {
            $results.Succeeded += $result
            if ($result.IsUpdate) {
                Add-UpdatedTool -Name $result.ToolKey -OldVersion $result.OldVersion -NewVersion $result.Version
            }
            else {
                Add-InstalledTool -Name $result.ToolKey -Version $result.Version
            }
        }
        elseif ($result.Status -eq "Failed") {
            $results.Failed += $result
            Add-FailedTool -Name $result.ToolKey -Reason $result.Message
        }
        else {
            $results.Skipped += $result
            Add-SkippedTool -Name $result.ToolKey -Version $result.Version -Reason $result.Reason
        }

        return $results
    }

    # Parallel installation using jobs
    $jobs = @()
    $scriptPath = $PSScriptRoot

    foreach ($toolKey in $ToolKeys) {
        $tool = $Tools.$toolKey

        # Create job to install this tool
        $job = Start-Job -ScriptBlock {
            param($ToolKey, $Tool, $ConfigPath, $ScriptPath)

            # Import modules in job context
            $modulePath = Join-Path -Path $ScriptPath -ChildPath ".." | Join-Path -ChildPath "modules"
            Import-Module (Join-Path -Path $modulePath -ChildPath "ColorConfig.psm1") -Force
            Import-Module (Join-Path -Path $modulePath -ChildPath "ErrorHandling.psm1") -Force
            Import-Module (Join-Path -Path $modulePath -ChildPath "VersionManagement.psm1") -Force

            # Import main script functions (dot-source the script)
            $mainScript = Join-Path -Path $ScriptPath -ChildPath "Install-DevelopmentTools.ps1"
            . $mainScript

            # Install the tool
            try {
                $result = Install-SingleTool -ToolKey $ToolKey -Tool $Tool -ConfigPath $ConfigPath
                return $result
            }
            catch {
                return @{
                    ToolKey = $ToolKey
                    Status = "Failed"
                    Message = $_.Exception.Message
                }
            }
        } -ArgumentList $toolKey, $tool, $ConfigPath, $scriptPath

        $jobs += @{
            Job = $job
            ToolKey = $toolKey
        }
    }

    # Display initial job status
    Write-InfoMessage "Started $($jobs.Count) parallel installation jobs"
    Write-InfoMessage "Job IDs: $(($jobs | ForEach-Object { "$($_.ToolKey)=$($_.Job.Id)" }) -join ', ')"

    # Wait for all jobs with progress indication
    $completed = 0
    $total = $jobs.Count
    $progressCounter = 0
    $lastProgressUpdate = Get-Date

    while ($completed -lt $total -and -not $script:CancellationRequested) {
        Start-Sleep -Milliseconds 500
        $progressCounter++

        # Show progress every 10 seconds (20 iterations * 500ms)
        if ($progressCounter -ge 20) {
            $progressCounter = 0
            $runningJobs = ($jobs | Where-Object { -not $_.Processed -and $_.Job.State -eq 'Running' }).Count
            $waitingJobs = $total - $completed - $runningJobs
            $elapsed = ((Get-Date) - $lastProgressUpdate).TotalSeconds

            Write-InfoMessage "Progress: $completed/$total completed | $runningJobs running | $waitingJobs waiting..."

            # Show which tools are currently running (for troubleshooting)
            $runningTools = $jobs | Where-Object { -not $_.Processed -and $_.Job.State -eq 'Running' } |
                ForEach-Object { $_.ToolKey }
            if ($runningTools.Count -gt 0) {
                Write-InfoMessage "Currently installing: $($runningTools -join ', ')"
            }

            $lastProgressUpdate = Get-Date
        }

        foreach ($jobInfo in $jobs) {
            if ($jobInfo.Job.State -eq 'Completed' -and -not $jobInfo.Processed) {
                $jobInfo.Processed = $true
                $completed++

                # Receive job result
                $result = Receive-Job -Job $jobInfo.Job
                Remove-Job -Job $jobInfo.Job

                # Update tracking based on result
                if ($result.Status -eq "Success") {
                    $results.Succeeded += $result
                    if ($result.IsUpdate) {
                        Add-UpdatedTool -Name $result.ToolKey -OldVersion $result.OldVersion -NewVersion $result.Version
                    }
                    else {
                        Add-InstalledTool -Name $result.ToolKey -Version $result.Version
                    }
                    Write-SuccessMessage "[$completed/$total] $($jobInfo.ToolKey) - Installed"
                }
                elseif ($result.Status -eq "Failed") {
                    $results.Failed += $result
                    Add-FailedTool -Name $result.ToolKey -Reason $result.Message
                    Write-ErrorMessage "[$completed/$total] $($jobInfo.ToolKey) - Failed"
                }
                else {
                    $results.Skipped += $result
                    Add-SkippedTool -Name $result.ToolKey -Version $result.Version -Reason $result.Reason
                    Write-InfoMessage "[$completed/$total] $($jobInfo.ToolKey) - Skipped"
                }

                # TeamCity service message
                if ($env:TEAMCITY_VERSION) {
                    $status = if ($result.Status -eq "Success") { "NORMAL" } else { "WARNING" }
                    Write-Output "##teamcity[message text='$($jobInfo.ToolKey): $($result.Status)' status='$status']"
                }
            }
            elseif ($jobInfo.Job.State -eq 'Failed' -and -not $jobInfo.Processed) {
                $jobInfo.Processed = $true
                $completed++

                $failedResult = @{
                    ToolKey = $jobInfo.ToolKey
                    Status = "Failed"
                    Message = "Job execution failed"
                }
                $results.Failed += $failedResult
                Add-FailedTool -Name $jobInfo.ToolKey -Reason "Job execution failed"

                Write-ErrorMessage "[$completed/$total] $($jobInfo.ToolKey) - Job Failed"
                Remove-Job -Job $jobInfo.Job -Force
            }
        }
    }

    # If cancelled, clean up remaining jobs
    if ($script:CancellationRequested) {
        Write-WarningMessage "Installation cancelled by user. Cleaning up remaining jobs..."
        foreach ($jobInfo in $jobs) {
            if (-not $jobInfo.Processed -and $jobInfo.Job) {
                if ($jobInfo.Job.State -eq 'Running') {
                    Stop-Job -Job $jobInfo.Job
                }
                Remove-Job -Job $jobInfo.Job -Force -ErrorAction SilentlyContinue
            }
        }
    }

    return $results
}

function Install-SingleTool {
    <#
    .SYNOPSIS
        Installs a single tool (used by both sequential and parallel installation)
    .PARAMETER ToolKey
        Tool identifier key
    .PARAMETER Tool
        Tool configuration object
    .PARAMETER ConfigPath
        Path to configuration file
    .OUTPUTS
        Hashtable with result: @{ ToolKey = ""; Status = "Success|Failed|Skipped"; Version = ""; Message = "" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolKey,

        [Parameter(Mandatory = $true)]
        $Tool,

        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    $toolName = $ToolKey
    $version = $Tool.version
    $source = $Tool.source
    $packageName = if ($Tool.packageName) { $Tool.packageName } else { $ToolKey }

    try {
        # Check current version
        $installedVersion = Get-InstalledToolVersion -ToolName $ToolKey -PackageName $packageName -Source $source
        $versionCheck = Test-ToolVersion -InstalledVersion $installedVersion -RequiredVersion $version -ToolName $toolName -AllowNewer $false

        # Already at correct version
        if ($versionCheck.VersionMatch -and -not $versionCheck.NeedsInstall) {
            return @{
                ToolKey = $ToolKey
                Status = "Skipped"
                Version = $installedVersion
                Message = "Already at correct version"
                Reason = "Correct version already installed"
            }
        }

        # Uninstall if version mismatch
        $isUpdate = $false
        if ($versionCheck.IsInstalled -and ($versionCheck.NeedsUpgrade -or $versionCheck.NeedsDowngrade)) {
            if ($source -eq "chocolatey") {
                choco uninstall $packageName -y 2>&1 | Out-Null
            }
            elseif ($source -eq "powershellgallery") {
                Uninstall-Module -Name $packageName -AllVersions -Force -ErrorAction SilentlyContinue
            }

            Update-SessionEnvironment
            $isUpdate = $true
        }

        # Install based on source
        $installSuccess = $false
        switch ($source.ToLower()) {
            "chocolatey" {
                Install-ChocolateyPackage -PackageName $packageName -Version $version -ToolName $toolName -Force | Out-Null
                $installSuccess = ($LASTEXITCODE -eq 0 -or (Get-ChocoPackageVersion -PackageName $packageName))
            }
            "powershellgallery" {
                Install-PowerShellModule -ModuleName $packageName -Version $version -ToolName $toolName -Force | Out-Null
                $installSuccess = (Get-PowerShellModuleVersion -ModuleName $packageName)
            }
            "nvm" {
                Install-NodeViaNvm -Version $version | Out-Null
                $installSuccess = (Get-NodeVersion)
            }
            default {
                return @{
                    ToolKey = $ToolKey
                    Status = "Failed"
                    Message = "Unknown source: $source"
                }
            }
        }

        # Refresh environment after installation
        Update-SessionEnvironment

        if ($installSuccess) {
            $newVersion = Get-InstalledToolVersion -ToolName $ToolKey -PackageName $packageName -Source $source
            return @{
                ToolKey = $ToolKey
                Status = "Success"
                Version = $newVersion
                Message = "Installed successfully"
                IsUpdate = $isUpdate
                OldVersion = if ($isUpdate) { $installedVersion } else { $null }
            }
        }
        else {
            return @{
                ToolKey = $ToolKey
                Status = "Failed"
                Message = "Installation command returned error"
            }
        }
    }
    catch {
        return @{
            ToolKey = $ToolKey
            Status = "Failed"
            Message = $_.Exception.Message
        }
    }
}

function Install-DevelopmentTools {
    <#
    .SYNOPSIS
        Main function to install all development tools with parallel installation support
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

    # Organize tools into installation waves based on dependencies
    $waves = Get-InstallationWaves -InstallOrder $installOrder -Tools $tools

    Write-InfoMessage "Installation organized into $($waves.Count) waves"

    $totalToolsProcessed = 0
    $totalSteps = $installOrder.Count

    # Process each wave
    for ($waveIndex = 0; $waveIndex -lt $waves.Count; $waveIndex++) {
        # Check for cancellation
        if ($script:CancellationRequested) {
            Write-WarningMessage "Installation cancelled by user"
            break
        }

        $currentWave = $waves[$waveIndex]
        $waveNumber = $waveIndex + 1

        Write-HeaderMessage "Wave $waveNumber/$($waves.Count): $($currentWave.Count) tool(s)"

        # Wave 0 (Bootstrap): Install sequentially
        if ($waveIndex -eq 0 -and ($currentWave -contains "chocolatey" -or $currentWave -contains "powershellget")) {
            Write-InfoMessage "Installing bootstrap tools sequentially..."

            foreach ($toolKey in $currentWave) {
                # Check for cancellation
                if ($script:CancellationRequested) {
                    Write-WarningMessage "Installation cancelled by user"
                    break
                }

                $totalToolsProcessed++
                Write-StepMessage -StepNumber $totalToolsProcessed -TotalSteps $totalSteps -Message "Processing: $toolKey"

                $tool = $tools.$toolKey
                if (-not $tool) {
                    Write-WarningLog "Tool configuration not found for: $toolKey"
                    continue
                }

                # Special handling for Chocolatey
                if ($toolKey -eq "chocolatey") {
                    Install-Chocolatey -Config $tool | Out-Null
                    continue
                }

                # Special handling for PowerShellGet
                if ($toolKey -eq "powershellget") {
                    Install-PowerShellGet | Out-Null
                    continue
                }
            }
        }
        # Subsequent waves: Install in parallel
        else {
            Write-InfoMessage "Installing $($currentWave.Count) tools in parallel..."
            Write-InfoMessage "Tools in this wave: $($currentWave -join ', ')"

            $waveResults = Install-ToolsInParallel -ToolKeys $currentWave -Tools $tools -ConfigPath $ConfigPath

            # Update tool tracking based on results
            foreach ($result in $waveResults.Succeeded) {
                $totalToolsProcessed++
            }
            foreach ($result in $waveResults.Failed) {
                $totalToolsProcessed++
            }
            foreach ($result in $waveResults.Skipped) {
                $totalToolsProcessed++
            }

            # Display wave summary
            if ($waveResults.Succeeded.Count -gt 0) {
                Write-SuccessMessage "Wave ${waveNumber}: $($waveResults.Succeeded.Count) tool(s) installed successfully"
            }
            if ($waveResults.Failed.Count -gt 0) {
                Write-WarningMessage "Wave ${waveNumber}: $($waveResults.Failed.Count) tool(s) failed"
            }
            if ($waveResults.Skipped.Count -gt 0) {
                Write-InfoMessage "Wave ${waveNumber}: $($waveResults.Skipped.Count) tool(s) skipped"
            }
        }

        # Refresh environment after each wave
        Update-SessionEnvironment

        # Close wave block (TeamCity collapsible section)
        if (Test-TeamCityEnvironment) {
            Close-TeamCityBlock -Name "Wave $waveNumber/$($waves.Count): $($currentWave.Count) tool(s)"
        }

        Write-ColorOutput "" -Color White
    }

    Write-SuccessMessage "Tool installation process completed ($totalToolsProcessed tools processed)"

    # Close main function block
    if (Test-TeamCityEnvironment) {
        Close-TeamCityBlock -Name "Development Tools Installation"
    }

    return $true
}

# =============================================================================
# MAIN EXECUTION
# Only runs when script is executed directly, not when dot-sourced
# =============================================================================
if (-not $script:IsBeingDotSourced) {
    try {
        Write-HeaderMessage "Development Environment Setup - Tool Installation"

    # Step 1: Initialize PSGallery and prerequisites (critical for CI/CD)
    Write-StepMessage -StepNumber 1 -TotalSteps 3 -Message "Configuring PSGallery and NuGet provider"
    Initialize-PSGallery | Out-Null

    # Step 2: Install development tools
    Write-StepMessage -StepNumber 2 -TotalSteps 3 -Message "Installing development tools"
    Install-DevelopmentTools -ConfigPath $ConfigPath | Out-Null

    # Step 3: Display summary
    Write-StepMessage -StepNumber 3 -TotalSteps 3 -Message "Generating summary report"

    Write-HeaderMessage "DEVELOPMENT TOOLS INSTALLATION - SUMMARY"

    # Summary statistics
    Write-ColorOutput "Overall Statistics:" -Color Cyan
    Write-ColorOutput "  Total Installed: " -Color White -NoNewline
    Write-ColorOutput "$($script:installedTools.Count)" -Color Green
    Write-ColorOutput "  Total Updated: " -Color White -NoNewline
    Write-ColorOutput "$($script:updatedTools.Count)" -Color Magenta
    Write-ColorOutput "  Total Skipped: " -Color White -NoNewline
    Write-ColorOutput "$($script:skippedTools.Count)" -Color Yellow
    Write-ColorOutput "  Total Failed: " -Color White -NoNewline
    Write-ColorOutput "$($script:failedTools.Count)" -Color Red
    Write-ColorOutput "  Total Errors: " -Color White -NoNewline
    Write-ColorOutput "$($(Get-ErrorLog).Count)" -Color $(if ((Get-ErrorLog).Count -gt 0) { "Red" } else { "Green" })
    Write-ColorOutput "  Total Warnings: " -Color White -NoNewline
    Write-ColorOutput "$($(Get-WarningLog).Count)" -Color $(if ((Get-WarningLog).Count -gt 0) { "Yellow" } else { "Green" })
    Write-ColorOutput "  Duration: " -Color White -NoNewline
    Write-ColorOutput ("{0:N2} minutes" -f ((Get-Date) - $script:ScriptStartTime).TotalMinutes) -Color Cyan
    Write-ColorOutput "" -Color White

    # Installed Tools
    if ($script:installedTools.Count -gt 0) {
        Write-SectionHeader "Installed Tools"
        Format-ToolTable -Tools $script:installedTools -Type "Installed"
        Write-ColorOutput "" -Color White
        if (Test-TeamCityEnvironment) {
            Close-TeamCityBlock -Name "Installed Tools"
        }
    }
    else {
        Write-SectionHeader "Installed Tools"
        Write-ColorOutput "  None" -Color DarkGray
        Write-ColorOutput "" -Color White
        if (Test-TeamCityEnvironment) {
            Close-TeamCityBlock -Name "Installed Tools"
        }
    }

    # Updated Tools
    if ($script:updatedTools.Count -gt 0) {
        Write-SectionHeader "Updated Tools"
        Format-ToolTable -Tools $script:updatedTools -Type "Updated"
        Write-ColorOutput "" -Color White
        if (Test-TeamCityEnvironment) {
            Close-TeamCityBlock -Name "Updated Tools"
        }
    }

    # Skipped Tools
    if ($script:skippedTools.Count -gt 0) {
        Write-SectionHeader "Skipped Tools"
        Format-ToolTable -Tools $script:skippedTools -Type "Skipped"
        Write-ColorOutput "" -Color White
        if (Test-TeamCityEnvironment) {
            Close-TeamCityBlock -Name "Skipped Tools"
        }
    }

    # Failed Tools
    if ($script:failedTools.Count -gt 0) {
        Write-SectionHeader "Failed Tools"
        Format-ToolTable -Tools $script:failedTools -Type "Failed"
        Write-ColorOutput "" -Color White
        if (Test-TeamCityEnvironment) {
            Close-TeamCityBlock -Name "Failed Tools"
        }
    }

    # Show detailed error summary if errors occurred
    if ((Get-ErrorLog).Count -gt 0 -or (Get-WarningLog).Count -gt 0) {
        Show-ErrorSummary
    }

    # Close main TeamCity block
    if (Test-TeamCityEnvironment) {
        Close-TeamCityBlock -Name "Development Environment Setup - Tool Installation"
    }

    if ($script:failedTools.Count -gt 0) {
        Write-ColorOutput "`nWARNING: Some tools failed to install. Please review the errors above." -Color Yellow
        exit 1
    }

        exit 0
    }
    catch {
        Write-ErrorLog -Message "Unhandled exception in installation script" -Exception $_.Exception -Fatal

        # Close main TeamCity block on error
        if (Test-TeamCityEnvironment) {
            Close-TeamCityBlock -Name "Development Environment Setup - Tool Installation"
        }

        exit 1
    }
}
