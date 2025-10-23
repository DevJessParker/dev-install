#Requires -Version 5.1

<#
.SYNOPSIS
    Version management module for checking and comparing tool versions
.DESCRIPTION
    Provides functions to check installed versions, compare with required versions,
    and manage version-specific installations
.NOTES
    This module requires ColorConfig and ErrorHandling modules to be imported
    before using its functions in your scripts.
#>

function Get-ChocoPackageVersion {
    <#
    .SYNOPSIS
        Gets the installed version of a Chocolatey package
    .PARAMETER PackageName
        Name of the Chocolatey package
    .EXAMPLE
        Get-ChocoPackageVersion -PackageName "nodejs"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName
    )

    try {
        $chocoList = choco list --local-only --exact $PackageName --limit-output 2>$null

        if ($LASTEXITCODE -eq 0 -and $chocoList) {
            # Chocolatey output format: package|version
            $version = ($chocoList -split '\|')[1]
            return $version.Trim()
        }

        return $null
    }
    catch {
        Write-WarningLog "Failed to check Chocolatey package version for $PackageName : $($_.Exception.Message)"
        return $null
    }
}

function Get-PowerShellModuleVersion {
    <#
    .SYNOPSIS
        Gets the installed version of a PowerShell module
    .PARAMETER ModuleName
        Name of the PowerShell module
    .EXAMPLE
        Get-PowerShellModuleVersion -ModuleName "AWS.Tools.S3"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )

    try {
        $module = Get-Module -ListAvailable -Name $ModuleName -ErrorAction SilentlyContinue |
                  Sort-Object Version -Descending |
                  Select-Object -First 1

        if ($module) {
            return $module.Version.ToString()
        }

        return $null
    }
    catch {
        Write-WarningLog "Failed to check PowerShell module version for $ModuleName : $($_.Exception.Message)"
        return $null
    }
}

function Get-NodeVersion {
    <#
    .SYNOPSIS
        Gets the currently active Node.js version
    .EXAMPLE
        Get-NodeVersion
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    try {
        $nodeVersion = node --version 2>$null

        if ($LASTEXITCODE -eq 0 -and $nodeVersion) {
            # Remove 'v' prefix if present
            return $nodeVersion.Trim().TrimStart('v')
        }

        return $null
    }
    catch {
        return $null
    }
}

function Get-NvmVersion {
    <#
    .SYNOPSIS
        Gets the installed version of NVM for Windows
    .EXAMPLE
        Get-NvmVersion
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    try {
        $nvmVersion = nvm version 2>$null

        if ($LASTEXITCODE -eq 0 -and $nvmVersion) {
            # Extract version number from output
            if ($nvmVersion -match '(\d+\.\d+\.\d+)') {
                return $matches[1]
            }
        }

        return $null
    }
    catch {
        return $null
    }
}

function Get-CommandVersion {
    <#
    .SYNOPSIS
        Gets version of a command-line tool using --version flag
    .PARAMETER CommandName
        Name of the command
    .PARAMETER VersionFlag
        Flag to use for version check (default: --version)
    .EXAMPLE
        Get-CommandVersion -CommandName "docker" -VersionFlag "--version"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [Parameter(Mandatory = $false)]
        [string]$VersionFlag = "--version"
    )

    try {
        $versionOutput = & $CommandName $VersionFlag 2>$null

        if ($LASTEXITCODE -eq 0 -and $versionOutput) {
            # Try to extract version number using common patterns
            if ($versionOutput -match '(\d+\.\d+\.\d+)') {
                return $matches[1]
            }
            elseif ($versionOutput -match 'version\s+(\d+\.\d+\.\d+)') {
                return $matches[1]
            }

            return $versionOutput.Trim()
        }

        return $null
    }
    catch {
        return $null
    }
}

function Test-ToolVersion {
    <#
    .SYNOPSIS
        Compares installed version with required version
    .PARAMETER InstalledVersion
        Currently installed version
    .PARAMETER RequiredVersion
        Required version
    .PARAMETER ToolName
        Name of the tool for display purposes
    .PARAMETER AllowNewer
        Whether newer versions are acceptable (default: $true)
    .EXAMPLE
        Test-ToolVersion -InstalledVersion "18.19.1" -RequiredVersion "18.19.1" -ToolName "Node.js"
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$InstalledVersion,

        [Parameter(Mandatory = $true)]
        [string]$RequiredVersion,

        [Parameter(Mandatory = $true)]
        [string]$ToolName,

        [Parameter(Mandatory = $false)]
        [bool]$AllowNewer = $true
    )

    $result = @{
        IsInstalled      = $false
        VersionMatch     = $false
        NeedsInstall     = $true
        NeedsUpgrade     = $false
        NeedsDowngrade   = $false
        InstalledVersion = $InstalledVersion
        RequiredVersion  = $RequiredVersion
    }

    # Handle "latest" version requirement
    if ($RequiredVersion -eq "latest") {
        if ($InstalledVersion) {
            $result.IsInstalled = $true
            $result.VersionMatch = $true
            $result.NeedsInstall = $false
            Write-InfoMessage "$ToolName is installed (version: $InstalledVersion). Required: latest"
        }
        else {
            Write-InfoMessage "$ToolName is not installed. Will install latest version."
        }
        return $result
    }

    # Check if tool is installed
    if (-not $InstalledVersion) {
        Write-InfoMessage "$ToolName is not installed. Required version: $RequiredVersion"
        return $result
    }

    $result.IsInstalled = $true

    # Try to parse as versions for comparison
    try {
        $installedVer = [version]$InstalledVersion
        $requiredVer = [version]$RequiredVersion

        if ($installedVer -eq $requiredVer) {
            $result.VersionMatch = $true
            $result.NeedsInstall = $false
            Write-SuccessMessage "$ToolName version matches: $InstalledVersion"
        }
        elseif ($installedVer -gt $requiredVer) {
            if ($AllowNewer) {
                $result.VersionMatch = $true
                $result.NeedsInstall = $false
                Write-InfoMessage "$ToolName has newer version: $InstalledVersion (required: $RequiredVersion)"
            }
            else {
                $result.NeedsDowngrade = $true
                Write-WarningMessage "$ToolName version $InstalledVersion is newer than required $RequiredVersion and will be replaced"
            }
        }
        else {
            $result.NeedsUpgrade = $true
            Write-WarningMessage "$ToolName version $InstalledVersion is older than required $RequiredVersion and will be replaced"
        }
    }
    catch {
        # String comparison fallback
        if ($InstalledVersion -eq $RequiredVersion) {
            $result.VersionMatch = $true
            $result.NeedsInstall = $false
            Write-SuccessMessage "$ToolName version matches: $InstalledVersion"
        }
        else {
            Write-WarningMessage "$ToolName version mismatch. Installed: $InstalledVersion, Required: $RequiredVersion"
        }
    }

    return $result
}

function Get-InstalledToolVersion {
    <#
    .SYNOPSIS
        Gets the installed version of a tool based on its source
    .PARAMETER ToolName
        Name of the tool
    .PARAMETER PackageName
        Package name (may differ from tool name)
    .PARAMETER Source
        Installation source (chocolatey, powershellgallery, nvm, etc.)
    .EXAMPLE
        Get-InstalledToolVersion -ToolName "node" -PackageName "nodejs" -Source "chocolatey"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolName,

        [Parameter(Mandatory = $false)]
        [string]$PackageName,

        [Parameter(Mandatory = $true)]
        [string]$Source
    )

    $pkgName = if ($PackageName) { $PackageName } else { $ToolName }

    switch ($Source.ToLower()) {
        "chocolatey" {
            return Get-ChocoPackageVersion -PackageName $pkgName
        }
        "powershellgallery" {
            return Get-PowerShellModuleVersion -ModuleName $pkgName
        }
        "nvm" {
            return Get-NodeVersion
        }
        "command" {
            return Get-CommandVersion -CommandName $ToolName
        }
        default {
            Write-WarningLog "Unknown source type: $Source for $ToolName"
            return $null
        }
    }
}

function Show-ToolVersionStatus {
    <#
    .SYNOPSIS
        Displays a formatted table of tool version statuses
    .PARAMETER ToolStatuses
        Array of tool status hashtables
    .EXAMPLE
        Show-ToolVersionStatus -ToolStatuses $statuses
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$ToolStatuses
    )

    Write-SectionHeader "Tool Version Status Summary"

    foreach ($status in $ToolStatuses) {
        $statusSymbol = if ($status.VersionMatch) { "[OK]" } elseif ($status.IsInstalled) { "[UPDATE]" } else { "[INSTALL]" }
        $statusColor = if ($status.VersionMatch) { $Script:ColorScheme.Success } elseif ($status.IsInstalled) { $Script:ColorScheme.Warning } else { $Script:ColorScheme.Info }

        Write-ColorOutput "$statusSymbol $($status.ToolName)" -Color $statusColor -NoNewline
        Write-ColorOutput " - Installed: $($status.InstalledVersion ?? 'Not installed'), Required: $($status.RequiredVersion)" -Color White
    }
}

# Export module members
Export-ModuleMember -Function Get-ChocoPackageVersion, Get-PowerShellModuleVersion,
                              Get-NodeVersion, Get-NvmVersion, Get-CommandVersion,
                              Test-ToolVersion, Get-InstalledToolVersion, Show-ToolVersionStatus
