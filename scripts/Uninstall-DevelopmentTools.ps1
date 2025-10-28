#Requires -Version 5.1
<#
.SYNOPSIS
    Uninstalls development tools based on configuration
.DESCRIPTION
    Removes all development tools including Chocolatey packages, PowerShell modules,
    and NVM/Node installations. Tools are uninstalled in reverse dependency order
    to avoid breaking dependent tools.
.PARAMETER ConfigPath
    Path to the tools configuration file
.PARAMETER KeepChocolatey
    Keep Chocolatey package manager installed (only remove other tools)
.NOTES
    This script is called by uninstall.ps1 and should not be run directly.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false)]
    [switch]$KeepChocolatey
)

# Script configuration
$ErrorActionPreference = 'Stop'
$script:IsBeingDotSourced = $false

# Import required modules
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath ".." | Join-Path -ChildPath "modules"
Import-Module (Join-Path -Path $modulePath -ChildPath "ColorConfig.psm1") -Force
Import-Module (Join-Path -Path $modulePath -ChildPath "ErrorHandling.psm1") -Force
Import-Module (Join-Path -Path $modulePath -ChildPath "VersionManagement.psm1") -Force
Import-Module (Join-Path -Path $modulePath -ChildPath "ComplianceAudit.psm1") -Force

# ============================================================================
# TRACKING VARIABLES
# ============================================================================
$script:removedTools = @()
$script:skippedTools = @()
$script:failedTools = @()

# ============================================================================
# TRACKING FUNCTIONS
# ============================================================================

function Add-RemovedTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$Version = "Unknown"
    )

    $script:removedTools += @{
        Name = $Name
        Version = $Version
    }
}

function Add-SkippedTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Reason
    )

    $script:skippedTools += @{
        Name = $Name
        Reason = $Reason
    }
}

function Add-FailedTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Reason
    )

    $script:failedTools += @{
        Name = $Name
        Reason = $Reason
    }
}

# ============================================================================
# UNINSTALL FUNCTIONS
# ============================================================================

function Uninstall-ChocolateyPackage {
    <#
    .SYNOPSIS
        Uninstalls a Chocolatey package
    .PARAMETER PackageName
        Name of the Chocolatey package
    .PARAMETER ToolName
        Display name of the tool
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName,

        [Parameter(Mandatory = $true)]
        [string]$ToolName
    )

    Write-ProgressMessage "Uninstalling $ToolName via Chocolatey..."

    try {
        # Check if package is installed
        $installed = choco list --local-only --exact $PackageName --limit-output 2>&1
        if ($LASTEXITCODE -ne 0 -or -not $installed) {
            Write-InfoMessage "$ToolName is not installed (skipping)"
            Add-SkippedTool -Name $ToolName -Reason "Not installed"
            return
        }

        # Get version before uninstalling
        $version = ($installed -split '\|')[1]

        # Uninstall package
        Write-InfoMessage "Removing $PackageName..."
        $output = choco uninstall $PackageName -y --remove-dependencies 2>&1
        $outputString = $output | Out-String

        if ($LASTEXITCODE -eq 0) {
            Write-SuccessMessage "$ToolName removed successfully"
            Add-RemovedTool -Name $ToolName -Version $version

            # Compliance audit logging
            if (Get-Command -Name Write-PackageAudit -ErrorAction SilentlyContinue) {
                Write-PackageAudit -Action "Remove" -PackageName $PackageName `
                    -Version $version -Source "chocolatey" -Status "Success" `
                    -Details "Chocolatey package removed successfully"
            }
        }
        else {
            Write-ErrorLog -Message "Failed to uninstall $ToolName (exit code: $LASTEXITCODE)"
            Write-ColorOutput "Chocolatey Error Output:" -Color Red
            Write-ColorOutput $outputString -Color DarkRed
            Add-FailedTool -Name $ToolName -Reason "Chocolatey exit code: $LASTEXITCODE"

            # Compliance audit logging
            if (Get-Command -Name Write-PackageAudit -ErrorAction SilentlyContinue) {
                Write-PackageAudit -Action "Remove" -PackageName $PackageName `
                    -Version $version -Source "chocolatey" -Status "Failed" `
                    -Details "Chocolatey uninstall failed with exit code $LASTEXITCODE"
            }
        }
    }
    catch {
        Write-ErrorLog -Message "Exception during $ToolName uninstall" -Exception $_.Exception
        Write-ColorOutput "Exception Details:" -Color Red
        Write-ColorOutput "  $($_.Exception.Message)" -Color DarkRed
        Add-FailedTool -Name $ToolName -Reason $_.Exception.Message

        # Compliance audit logging
        if (Get-Command -Name Write-PackageAudit -ErrorAction SilentlyContinue) {
            Write-PackageAudit -Action "Remove" -PackageName $PackageName `
                -Version "Unknown" -Source "chocolatey" -Status "Failed" `
                -Details "Exception during uninstall: $($_.Exception.Message)"
        }
    }
}

function Uninstall-PowerShellModule {
    <#
    .SYNOPSIS
        Uninstalls a PowerShell module
    .PARAMETER ModuleName
        Name of the PowerShell module
    .PARAMETER ToolName
        Display name of the tool
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName,

        [Parameter(Mandatory = $true)]
        [string]$ToolName
    )

    Write-ProgressMessage "Uninstalling $ToolName from PowerShell Gallery..."

    try {
        # Check if module is installed
        $module = Get-Module -ListAvailable -Name $ModuleName | Select-Object -First 1
        if (-not $module) {
            Write-InfoMessage "$ToolName is not installed (skipping)"
            Add-SkippedTool -Name $ToolName -Reason "Not installed"
            return
        }

        $version = $module.Version.ToString()

        # Uninstall module
        Write-InfoMessage "Removing $ModuleName..."
        Uninstall-Module -Name $ModuleName -AllVersions -Force -ErrorAction Stop

        Write-SuccessMessage "$ToolName removed successfully"
        Add-RemovedTool -Name $ToolName -Version $version

        # Compliance audit logging
        if (Get-Command -Name Write-PackageAudit -ErrorAction SilentlyContinue) {
            Write-PackageAudit -Action "Remove" -PackageName $ModuleName `
                -Version $version -Source "powershellgallery" -Status "Success" `
                -Details "PowerShell module removed successfully"
        }
    }
    catch {
        Write-ErrorLog -Message "Failed to uninstall $ToolName" -Exception $_.Exception
        Write-ColorOutput "PowerShell Gallery Error Details:" -Color Red
        Write-ColorOutput "  $($_.Exception.Message)" -Color DarkRed
        Add-FailedTool -Name $ToolName -Reason $_.Exception.Message

        # Compliance audit logging
        if (Get-Command -Name Write-PackageAudit -ErrorAction SilentlyContinue) {
            Write-PackageAudit -Action "Remove" -PackageName $ModuleName `
                -Version "Unknown" -Source "powershellgallery" -Status "Failed" `
                -Details "Exception during uninstall: $($_.Exception.Message)"
        }
    }
}

function Uninstall-NodeAndNvm {
    <#
    .SYNOPSIS
        Uninstalls all Node.js versions and NVM
    #>
    [CmdletBinding()]
    param()

    Write-ProgressMessage "Uninstalling Node.js and NVM..."

    try {
        # Refresh environment to ensure nvm is available
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

        # Check if NVM is available
        $nvmCmd = Get-Command nvm -ErrorAction SilentlyContinue
        if (-not $nvmCmd) {
            Write-InfoMessage "NVM is not installed (skipping Node.js/NVM uninstall)"
            Add-SkippedTool -Name "nvm" -Reason "Not installed"
            Add-SkippedTool -Name "node" -Reason "NVM not installed"
            return
        }

        # List all installed Node versions
        $nvmList = nvm list 2>&1
        if ($LASTEXITCODE -eq 0) {
            $versions = $nvmList | Where-Object { $_ -match 'v\d+\.\d+\.\d+' } | ForEach-Object {
                if ($_ -match '(v\d+\.\d+\.\d+)') {
                    $matches[1]
                }
            }

            if ($versions) {
                Write-InfoMessage "Found $($versions.Count) Node.js version(s) installed"
                foreach ($version in $versions) {
                    Write-InfoMessage "Uninstalling Node.js $version..."
                    nvm uninstall $version 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-SuccessMessage "Node.js $version removed"
                    }
                }
                Add-RemovedTool -Name "node" -Version "All versions"
            }
            else {
                Write-InfoMessage "No Node.js versions found"
                Add-SkippedTool -Name "node" -Reason "No versions installed"
            }
        }

        # Note: NVM itself will be uninstalled via Chocolatey
        Write-InfoMessage "Node.js versions removed. NVM will be removed via Chocolatey."

        # Compliance audit logging
        if (Get-Command -Name Write-PackageAudit -ErrorAction SilentlyContinue) {
            Write-PackageAudit -Action "Remove" -PackageName "node" `
                -Version "All versions" -Source "nvm" -Status "Success" `
                -Details "All Node.js versions removed via NVM"
        }
    }
    catch {
        Write-ErrorLog -Message "Failed to uninstall Node.js/NVM" -Exception $_.Exception
        Write-ColorOutput "Error Details:" -Color Red
        Write-ColorOutput "  $($_.Exception.Message)" -Color DarkRed
        Add-FailedTool -Name "node/nvm" -Reason $_.Exception.Message
    }
}

function Remove-Chocolatey {
    <#
    .SYNOPSIS
        Completely removes Chocolatey package manager
    #>
    [CmdletBinding()]
    param()

    Write-ProgressMessage "Removing Chocolatey package manager..."

    try {
        # Check if Chocolatey is installed
        $chocoCmd = Get-Command choco -ErrorAction SilentlyContinue
        if (-not $chocoCmd) {
            Write-InfoMessage "Chocolatey is not installed (skipping)"
            Add-SkippedTool -Name "Chocolatey" -Reason "Not installed"
            return
        }

        # Get Chocolatey version
        $chocoVersion = (choco --version 2>&1) | Out-String
        $chocoVersion = $chocoVersion.Trim()

        # Remove Chocolatey directory
        $chocoInstall = $env:ChocolateyInstall
        if (-not $chocoInstall) {
            $chocoInstall = "C:\ProgramData\chocolatey"
        }

        if (Test-Path $chocoInstall) {
            Write-InfoMessage "Removing Chocolatey installation directory: $chocoInstall"

            # Remove Chocolatey from PATH
            $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
            $newPath = ($machinePath -split ';' | Where-Object { $_ -notlike "*chocolatey*" }) -join ';'
            [System.Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")

            $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
            $newUserPath = ($userPath -split ';' | Where-Object { $_ -notlike "*chocolatey*" }) -join ';'
            [System.Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")

            # Remove Chocolatey directory
            Remove-Item -Path $chocoInstall -Recurse -Force -ErrorAction SilentlyContinue

            Write-SuccessMessage "Chocolatey removed successfully"
            Add-RemovedTool -Name "Chocolatey" -Version $chocoVersion

            # Compliance audit logging
            if (Get-Command -Name Write-PackageAudit -ErrorAction SilentlyContinue) {
                Write-PackageAudit -Action "Remove" -PackageName "chocolatey" `
                    -Version $chocoVersion -Source "script" -Status "Success" `
                    -Details "Chocolatey package manager removed completely"
            }
        }
        else {
            Write-WarningMessage "Chocolatey directory not found: $chocoInstall"
            Add-SkippedTool -Name "Chocolatey" -Reason "Installation directory not found"
        }
    }
    catch {
        Write-ErrorLog -Message "Failed to remove Chocolatey" -Exception $_.Exception
        Write-ColorOutput "Error Details:" -Color Red
        Write-ColorOutput "  $($_.Exception.Message)" -Color DarkRed
        Add-FailedTool -Name "Chocolatey" -Reason $_.Exception.Message
    }
}

# ============================================================================
# MAIN UNINSTALL LOGIC
# ============================================================================

function Start-Uninstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,

        [Parameter(Mandatory = $false)]
        [switch]$KeepChocolatey
    )

    Write-HeaderMessage "Development Environment Uninstall"

    # Initialize compliance audit if not already initialized
    if (-not (Get-Command -Name Get-SessionId -ErrorAction SilentlyContinue) -or -not (Get-SessionId)) {
        $scriptRoot = Split-Path -Parent $PSScriptRoot
        Initialize-ComplianceAudit -LogDirectory (Join-Path -Path $scriptRoot -ChildPath "logs")
    }

    # Load configuration
    Write-ProgressMessage "Loading configuration..."
    try {
        $configContent = Get-Content -Path $ConfigPath -Raw
        $config = $configContent | ConvertFrom-Json
        Write-SuccessMessage "Configuration loaded from: $ConfigPath"
    }
    catch {
        Write-ErrorLog -Message "Failed to load configuration file" -Exception $_.Exception -Fatal
    }

    # Get tools and installation order
    $tools = $config.developmentTools
    $installationOrder = $config.installationOrder

    # Reverse the installation order for uninstalling (handle dependencies correctly)
    [Array]::Reverse($installationOrder)

    Write-InfoMessage "Total tools to process: $($installationOrder.Count)"

    if ($KeepChocolatey) {
        Write-WarningMessage "Chocolatey will be kept installed (as requested)"
    }

    Write-Host ""

    # Process each tool
    $current = 0
    foreach ($toolKey in $installationOrder) {
        $current++

        # Skip Chocolatey if KeepChocolatey flag is set
        if ($toolKey -eq "chocolatey" -and $KeepChocolatey) {
            Write-InfoMessage "[$current/$($installationOrder.Count)] Skipping chocolatey (keeping installed)"
            Add-SkippedTool -Name "chocolatey" -Reason "KeepChocolatey flag set"
            continue
        }

        # Skip PowerShellGet (bootstrap module)
        if ($toolKey -eq "powershellget") {
            Write-InfoMessage "[$current/$($installationOrder.Count)] Skipping powershellget (system module)"
            Add-SkippedTool -Name "powershellget" -Reason "System module"
            continue
        }

        $tool = $tools.$toolKey
        if (-not $tool) {
            Write-WarningMessage "[$current/$($installationOrder.Count)] Tool configuration not found: $toolKey"
            Add-SkippedTool -Name $toolKey -Reason "Configuration not found"
            continue
        }

        Write-Host "[$current/$($installationOrder.Count)] Processing: $toolKey" -ForegroundColor Cyan

        $source = $tool.source
        $packageName = if ($tool.packageName) { $tool.packageName } else { $toolKey }
        $description = if ($tool.description) { $tool.description } else { $toolKey }

        switch ($source) {
            "chocolatey" {
                Uninstall-ChocolateyPackage -PackageName $packageName -ToolName $toolKey
            }
            "powershellgallery" {
                Uninstall-PowerShellModule -ModuleName $packageName -ToolName $toolKey
            }
            "nvm" {
                # Node.js installed via NVM - handle specially
                Uninstall-NodeAndNvm
            }
            "script" {
                # Special handling for Chocolatey itself
                if ($toolKey -eq "chocolatey") {
                    Remove-Chocolatey
                }
                else {
                    Write-WarningMessage "Script-based tool uninstall not implemented for: $toolKey"
                    Add-SkippedTool -Name $toolKey -Reason "Script-based uninstall not implemented"
                }
            }
            "bootstrap" {
                Write-InfoMessage "$toolKey is a bootstrap component (skipping)"
                Add-SkippedTool -Name $toolKey -Reason "Bootstrap component"
            }
            default {
                Write-WarningMessage "Unknown source type for $toolKey`: $source"
                Add-SkippedTool -Name $toolKey -Reason "Unknown source type: $source"
            }
        }

        Write-Host ""
    }

    Write-SuccessMessage "Uninstall process completed ($($installationOrder.Count) tools processed)"
    Write-Host ""

    # Display summary
    Write-SectionHeader "Uninstall Summary"
    Write-Host ""
    Write-Host "Overall Statistics:" -ForegroundColor White
    Write-Host "  Total Removed: $($script:removedTools.Count)" -ForegroundColor Gray
    Write-Host "  Total Skipped: $($script:skippedTools.Count)" -ForegroundColor Gray
    Write-Host "  Total Failed: $($script:failedTools.Count)" -ForegroundColor Gray
    Write-Host ""

    # Removed Tools
    if ($script:removedTools.Count -gt 0) {
        Write-SectionHeader "Removed Tools"
        Write-Host ""
        foreach ($tool in $script:removedTools) {
            Write-ColorOutput "  $($tool.Name)" -Color Green -NoNewline
            Write-ColorOutput " - " -Color DarkGray -NoNewline
            Write-ColorOutput "v$($tool.Version)" -Color Cyan
        }
        Write-Host ""
    }

    # Skipped Tools
    if ($script:skippedTools.Count -gt 0) {
        Write-SectionHeader "Skipped Tools"
        Write-Host ""
        foreach ($tool in $script:skippedTools) {
            Write-ColorOutput "  $($tool.Name)" -Color Yellow -NoNewline
            Write-ColorOutput " - $($tool.Reason)" -Color DarkGray
        }
        Write-Host ""
    }

    # Failed Tools
    if ($script:failedTools.Count -gt 0) {
        Write-SectionHeader "Failed Tools"
        Write-Host ""
        foreach ($tool in $script:failedTools) {
            Write-ColorOutput "  $($tool.Name)" -Color Red
            Write-ColorOutput "    Reason: $($tool.Reason)" -Color DarkRed
        }
        Write-Host ""
    }

    # Show error summary
    if ((Get-ErrorLog).Count -gt 0 -or (Get-WarningLog).Count -gt 0) {
        Show-ErrorSummary
    }

    # Close compliance audit
    if (Get-Command -Name Get-SessionId -ErrorAction SilentlyContinue) {
        Close-ComplianceAudit
    }

    if ($script:failedTools.Count -gt 0) {
        Write-ColorOutput "`nWARNING: Some tools failed to uninstall. Please review the errors above." -Color Yellow
        exit 1
    }

    exit 0
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
if (-not $script:IsBeingDotSourced) {
    try {
        Start-Uninstall -ConfigPath $ConfigPath -KeepChocolatey:$KeepChocolatey
    }
    catch {
        Write-ErrorLog -Message "Unhandled exception in uninstall script" -Exception $_.Exception -Fatal
        exit 1
    }
}
