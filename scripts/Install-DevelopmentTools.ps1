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
$script:ScriptStartTime = Get-Date

# Import required modules
$modulePath = "$PSScriptRoot\..\modules"
Import-Module "$modulePath\AdminCheck.psm1" -Force
Import-Module "$modulePath\ColorConfig.psm1" -Force
Import-Module "$modulePath\ErrorHandling.psm1" -Force
Import-Module "$modulePath\SystemCheck.psm1" -Force
Import-Module "$modulePath\VersionManagement.psm1" -Force

# Script-level variables (tracking tool installation with versions)
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

        return $true
    }
    catch {
        Write-WarningLog "Failed to configure PSGallery: $($_.Exception.Message)"
        # Non-fatal, continue execution
        return $false
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

        return $true
    }
    catch {
        Write-WarningLog "Failed to install/update PowerShellGet: $($_.Exception.Message)"
        # Check if we can continue with existing version
        if ($currentPSGet) {
            Write-InfoMessage "Continuing with existing PowerShellGet version"
            return $true
        }
        else {
            Write-ErrorLog -Message "PowerShellGet is required but could not be installed" -Fatal
            return $false
        }
    }
}

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

        # Add CI/CD and TeamCity-friendly flags
        $chocoArgs += "--accept-license"           # Accept license agreements automatically
        $chocoArgs += "--no-progress"              # Disable progress bars (cleaner CI logs)
        $chocoArgs += "--limit-output"             # Limit output for cleaner CI logs
        $chocoArgs += "--allow-empty-checksums"    # Allow packages with empty checksums
        $chocoArgs += "--ignore-checksums"         # Skip checksum verification if needed

        # Install package
        & choco @chocoArgs 2>&1 | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-SuccessMessage "$ToolName installed successfully"
            # Get the installed version
            $installedVer = Get-ChocoPackageVersion -PackageName $PackageName
            Add-InstalledTool -Name $ToolName -Version $(if ($installedVer) { $installedVer } else { $Version })
            return $true
        }
        else {
            Write-ErrorLog -Message "Failed to install $ToolName (exit code: $LASTEXITCODE)"
            Add-FailedTool -Name $ToolName -Reason "Exit code: $LASTEXITCODE"
            return $false
        }
    }
    catch {
        Write-ErrorLog -Message "Exception during $ToolName installation" -Exception $_.Exception
        Add-FailedTool -Name $ToolName -Reason $_.Exception.Message
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
        if ($Version -ne "latest") {
            $installParams.RequiredVersion = $Version
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
                Add-InstalledTool -Name $ToolName -Version $(if ($installedVer) { $installedVer } else { $Version })
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

        return $true
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
                Add-InstalledTool -Name $ToolName -Version $(if ($installedVer) { $installedVer } else { $Version })
                return $true
            }
            catch {
                Write-ErrorLog -Message "Failed to install $ToolName even with license workaround" -Exception $_.Exception
                Add-FailedTool -Name $ToolName -Reason "License acceptance failed"
                return $false
            }
        }
        elseif ($errorMessage -like "*is already installed*") {
            Write-InfoMessage "$ToolName is already installed"
            $installedVer = Get-PowerShellModuleVersion -ModuleName $ModuleName
            Add-SkippedTool -Name $ToolName -Version $(if ($installedVer) { $installedVer } else { "Unknown" }) -Reason "Already installed"
            return $true
        }
        else {
            Write-ErrorLog -Message "Failed to install $ToolName" -Exception $_.Exception
            Add-FailedTool -Name $ToolName -Reason $_.Exception.Message
            return $false
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
            Add-FailedTool -Name "Node.js" -Reason "NVM install failed"
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
            Add-InstalledTool -Name "Node.js" -Version $nodeVersion.TrimStart('v')
            return $true
        }
        else {
            Write-WarningLog "Node.js installation could not be verified"
            return $false
        }
    }
    catch {
        Write-ErrorLog -Message "Exception during Node.js installation" -Exception $_.Exception
        Add-FailedTool -Name "Node.js" -Reason $_.Exception.Message
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

        # Special handling for PowerShellGet (bootstrap)
        if ($toolKey -eq "powershellget") {
            Install-PowerShellGet
            $stepNumber++
            continue
        }

        # Check current version
        $installedVersion = Get-InstalledToolVersion -ToolName $toolKey -PackageName $packageName -Source $source
        $versionCheck = Test-ToolVersion -InstalledVersion $installedVersion -RequiredVersion $version -ToolName $toolName -AllowNewer $false

        # Determine action needed
        if ($versionCheck.VersionMatch -and -not $versionCheck.NeedsInstall) {
            Write-InfoMessage "$toolName is already at the correct version ($installedVersion)"
            Add-SkippedTool -Name $toolName -Version $installedVersion -Reason "Correct version already installed"
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
            Add-UpdatedTool -Name $toolName -OldVersion $installedVersion -NewVersion $version
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
    Write-StepMessage -StepNumber 1 -TotalSteps 6 -Message "Verifying administrator privileges"
    Assert-IsAdmin -ScriptName "Install-DevelopmentTools.ps1"

    # Step 2: Initialize PSGallery and prerequisites (critical for CI/CD)
    Write-StepMessage -StepNumber 2 -TotalSteps 6 -Message "Configuring PSGallery and NuGet provider"
    Initialize-PSGallery

    # Step 3: Gather and display system information
    Write-StepMessage -StepNumber 3 -TotalSteps 6 -Message "Gathering system information"
    $systemInfo = Get-SystemInformation
    Show-SystemInformation -SystemInfo $systemInfo

    # Step 4: Check system requirements
    if (-not $SkipSystemCheck) {
        Write-StepMessage -StepNumber 4 -TotalSteps 6 -Message "Validating system requirements"
        Test-SystemRequirements -ConfigPath $ConfigPath
        Test-InternetConnection | Out-Null
    }
    else {
        Write-WarningMessage "System requirements check skipped"
    }

    # Step 5: Install development tools
    Write-StepMessage -StepNumber 5 -TotalSteps 6 -Message "Installing development tools"
    Install-DevelopmentTools -ConfigPath $ConfigPath

    # Step 6: Display summary
    Write-StepMessage -StepNumber 6 -TotalSteps 6 -Message "Generating summary report"

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
    Write-SectionHeader "Installed Tools"
    Format-ToolTable -Tools $script:installedTools -Type "Installed"
    Write-ColorOutput "" -Color White

    # Updated Tools
    if ($script:updatedTools.Count -gt 0) {
        Write-SectionHeader "Updated Tools"
        Format-ToolTable -Tools $script:updatedTools -Type "Updated"
        Write-ColorOutput "" -Color White
    }

    # Skipped Tools
    if ($script:skippedTools.Count -gt 0) {
        Write-SectionHeader "Skipped Tools"
        Format-ToolTable -Tools $script:skippedTools -Type "Skipped"
        Write-ColorOutput "" -Color White
    }

    # Failed Tools
    if ($script:failedTools.Count -gt 0) {
        Write-SectionHeader "Failed Tools"
        Format-ToolTable -Tools $script:failedTools -Type "Failed"
        Write-ColorOutput "" -Color White
    }

    # Show detailed error summary if errors occurred
    if ((Get-ErrorLog).Count -gt 0 -or (Get-WarningLog).Count -gt 0) {
        Show-ErrorSummary
    }

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
