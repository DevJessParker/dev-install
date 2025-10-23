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

function Test-VersionExpression {
    <#
    .SYNOPSIS
        Tests if an installed version satisfies a version expression
    .PARAMETER InstalledVersion
        The installed version string (e.g., "1.2.3")
    .PARAMETER VersionExpression
        Version expression supporting:
        - "latest" - any version
        - "1.2.3" - exact match
        - ">=1.2.3" - greater than or equal
        - ">1.2.3" - greater than
        - "<=1.2.3" - less than or equal
        - "<1.2.3" - less than
        - "^1.2.3" - caret range (>=1.2.3 <2.0.0)
        - "~1.2.3" - tilde range (>=1.2.3 <1.3.0)
    .EXAMPLE
        Test-VersionExpression -InstalledVersion "1.5.0" -VersionExpression ">=1.2.0"
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstalledVersion,

        [Parameter(Mandatory = $true)]
        [string]$VersionExpression
    )

    # Handle "latest" - any version is acceptable
    if ($VersionExpression -eq "latest") {
        return $true
    }

    try {
        $installedVer = [version]$InstalledVersion

        # Handle caret range (^): Compatible with major version
        # ^1.2.3 means >=1.2.3 <2.0.0
        if ($VersionExpression -match '^\^(\d+)\.(\d+)\.(\d+)') {
            $major = [int]$matches[1]
            $minor = [int]$matches[2]
            $patch = [int]$matches[3]
            $minVersion = [version]"$major.$minor.$patch"
            $maxVersion = [version]"$($major + 1).0.0"

            return ($installedVer -ge $minVersion -and $installedVer -lt $maxVersion)
        }

        # Handle tilde range (~): Compatible with minor version
        # ~1.2.3 means >=1.2.3 <1.3.0
        if ($VersionExpression -match '^\~(\d+)\.(\d+)\.(\d+)') {
            $major = [int]$matches[1]
            $minor = [int]$matches[2]
            $patch = [int]$matches[3]
            $minVersion = [version]"$major.$minor.$patch"
            $maxVersion = [version]"$major.$($minor + 1).0"

            return ($installedVer -ge $minVersion -and $installedVer -lt $maxVersion)
        }

        # Handle >= operator
        if ($VersionExpression -match '^>=(.+)') {
            $requiredVer = [version]$matches[1]
            return ($installedVer -ge $requiredVer)
        }

        # Handle > operator
        if ($VersionExpression -match '^>(.+)') {
            $requiredVer = [version]$matches[1]
            return ($installedVer -gt $requiredVer)
        }

        # Handle <= operator
        if ($VersionExpression -match '^<=(.+)') {
            $requiredVer = [version]$matches[1]
            return ($installedVer -le $requiredVer)
        }

        # Handle < operator
        if ($VersionExpression -match '^<(.+)') {
            $requiredVer = [version]$matches[1]
            return ($installedVer -lt $requiredVer)
        }

        # Exact version match
        $requiredVer = [version]$VersionExpression
        return ($installedVer -eq $requiredVer)
    }
    catch {
        # Fallback to string comparison
        return ($InstalledVersion -eq $VersionExpression)
    }
}

function Test-ToolVersion {
    <#
    .SYNOPSIS
        Compares installed version with required version expression
    .PARAMETER InstalledVersion
        Currently installed version
    .PARAMETER RequiredVersion
        Required version expression (supports >=, >, <=, <, ^, ~, exact, latest)
    .PARAMETER ToolName
        Name of the tool for display purposes
    .PARAMETER AllowNewer
        Whether newer versions are acceptable for exact matches (default: $true)
    .EXAMPLE
        Test-ToolVersion -InstalledVersion "18.19.1" -RequiredVersion ">=18.0.0" -ToolName "Node.js"
    .EXAMPLE
        Test-ToolVersion -InstalledVersion "1.5.0" -RequiredVersion "^1.2.0" -ToolName "MyTool"
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

    # Check if tool is installed
    if (-not $InstalledVersion) {
        Write-InfoMessage "$ToolName is not installed. Required: $RequiredVersion"
        return $result
    }

    $result.IsInstalled = $true

    # Test if installed version satisfies the required version expression
    $satisfies = Test-VersionExpression -InstalledVersion $InstalledVersion -VersionExpression $RequiredVersion

    if ($satisfies) {
        $result.VersionMatch = $true
        $result.NeedsInstall = $false
        Write-SuccessMessage "$ToolName version $InstalledVersion satisfies requirement: $RequiredVersion"
    }
    else {
        # Determine if upgrade or downgrade is needed
        try {
            $installedVer = [version]$InstalledVersion

            # Extract base version from expression for comparison
            $baseVersion = $RequiredVersion
            if ($RequiredVersion -match '[\^~>=<]+(.+)') {
                $baseVersion = $matches[1]
            }

            $requiredVer = [version]$baseVersion

            if ($installedVer -lt $requiredVer) {
                $result.NeedsUpgrade = $true
                Write-WarningMessage "$ToolName version $InstalledVersion does not satisfy $RequiredVersion. Upgrade needed."
            }
            else {
                $result.NeedsDowngrade = $true
                Write-WarningMessage "$ToolName version $InstalledVersion does not satisfy $RequiredVersion. Reinstall needed."
            }
        }
        catch {
            Write-WarningMessage "$ToolName version $InstalledVersion does not satisfy $RequiredVersion"
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

        # PowerShell 5.1 compatible null check
        $installedVersionDisplay = if ($status.InstalledVersion) { $status.InstalledVersion } else { 'Not installed' }

        Write-ColorOutput "$statusSymbol $($status.ToolName)" -Color $statusColor -NoNewline
        Write-ColorOutput " - Installed: $installedVersionDisplay, Required: $($status.RequiredVersion)" -Color White
    }
}

# Export module members
Export-ModuleMember -Function Get-ChocoPackageVersion, Get-PowerShellModuleVersion,
                              Get-NodeVersion, Get-NvmVersion, Get-CommandVersion,
                              Test-VersionExpression, Test-ToolVersion, Get-InstalledToolVersion,
                              Show-ToolVersionStatus
