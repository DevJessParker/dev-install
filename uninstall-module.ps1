#Requires -Version 5.1
<#
.SYNOPSIS
    Completely uninstalls a PowerShell module and removes associated aliases.

.DESCRIPTION
    Intelligently removes modules and aliases from:
    - Current PowerShell session (memory)
    - All module installation directories (discovered via PSModulePath)
    - PowerShell profile (alias persistence)

    Works for any developer by dynamically discovering installation paths.

.PARAMETER ModuleName
    Name of the module or alias to uninstall. If omitted, prompts interactively.

.PARAMETER KeepProfile
    If specified, keeps the alias in the PowerShell profile (only removes from session and disk).

.PARAMETER WhatIf
    Shows what would be removed without actually removing anything.

.EXAMPLE
    .\uninstall-module.ps1
    Interactive mode: Prompts for module/alias name

.EXAMPLE
    .\uninstall-module.ps1 -ModuleName "IGScan"
    Uninstalls IGScan module completely

.EXAMPLE
    .\uninstall-module.ps1 -ModuleName "igscan" -WhatIf
    Shows what would be removed without removing it

.NOTES
    Author: DevJessParker
    Requires: PowerShell 5.1+
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$ModuleName,

    [Parameter(Mandatory = $false)]
    [switch]$KeepProfile,

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

#region Helper Functions

function Write-StatusMessage {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Type = 'Info'
    )

    $colors = @{
        Info    = 'Cyan'
        Success = 'Green'
        Warning = 'Yellow'
        Error   = 'Red'
    }

    $prefix = switch ($Type) {
        'Info'    { '[INFO] ' }
        'Success' { '[OK]   ' }
        'Warning' { '[WARN] ' }
        'Error'   { '[ERROR]' }
    }

    Write-Host "$prefix $Message" -ForegroundColor $colors[$Type]
}

function Find-ModuleByAlias {
    <#
    .SYNOPSIS
        Attempts to find the actual module name from an alias.
    #>
    param([string]$AliasName)

    try {
        $aliasCmd = Get-Alias -Name $AliasName -ErrorAction SilentlyContinue

        if ($null -ne $aliasCmd) {
            $targetFunction = $aliasCmd.Definition

            # Try to find which module exports this function
            $module = Get-Command -Name $targetFunction -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty ModuleName -ErrorAction SilentlyContinue

            if ($null -ne $module) {
                return $module
            }

            # Fallback: Extract IG module name from function name
            if ($targetFunction -match '\b(IG[A-Za-z0-9]+)\b') {
                return $Matches[1]
            }
        }
    }
    catch {
        # Continue to manual search
    }

    return $null
}

function Get-AllModuleInstallations {
    <#
    .SYNOPSIS
        Finds all installations of a module across all PSModulePath locations.
    #>
    param([string]$ModuleName)

    $installations = @()

    # Get all module paths
    $modulePaths = $env:PSModulePath -split [IO.Path]::PathSeparator |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    Write-StatusMessage "Searching $($modulePaths.Count) module directories..." -Type Info

    foreach ($basePath in $modulePaths) {
        if (Test-Path $basePath) {
            # Look for exact module name (case-insensitive)
            $modulePath = Join-Path $basePath $ModuleName

            if (Test-Path $modulePath) {
                $installations += [PSCustomObject]@{
                    Path     = $modulePath
                    BasePath = $basePath
                    Exists   = $true
                }
            }

            # Also check for case variations
            Get-ChildItem -Path $basePath -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ieq $ModuleName -and $_.FullName -ne $modulePath } |
                ForEach-Object {
                    $installations += [PSCustomObject]@{
                        Path     = $_.FullName
                        BasePath = $basePath
                        Exists   = $true
                    }
                }
        }
    }

    return $installations
}

function Remove-AliasFromProfile {
    <#
    .SYNOPSIS
        Removes alias definitions from PowerShell profile.
    #>
    param([string]$AliasName)

    $profilePath = $PROFILE

    if (-not (Test-Path $profilePath)) {
        Write-StatusMessage "No PowerShell profile found at: $profilePath" -Type Info
        return $false
    }

    try {
        $content = Get-Content $profilePath -Raw -ErrorAction Stop

        if ([string]::IsNullOrWhiteSpace($content)) {
            Write-StatusMessage "Profile is empty" -Type Info
            return $false
        }

        # Pattern to match alias lines (flexible matching)
        $pattern = "^\s*Set-Alias\s+(-Name\s+)?['""]?$([regex]::Escape($AliasName))['""]?\s+.*$"

        $lines = $content -split "`r?`n"
        $originalCount = $lines.Count
        $newLines = $lines | Where-Object { $_ -notmatch $pattern }

        if ($newLines.Count -lt $originalCount) {
            $removed = $originalCount - $newLines.Count

            if ($WhatIf) {
                Write-StatusMessage "Would remove $removed alias line(s) from profile" -Type Warning
                return $true
            }

            $newContent = $newLines -join "`r`n"
            Set-Content -Path $profilePath -Value $newContent -Force -ErrorAction Stop

            Write-StatusMessage "Removed $removed alias line(s) from profile: $profilePath" -Type Success
            return $true
        }
        else {
            Write-StatusMessage "No alias found in profile" -Type Info
            return $false
        }
    }
    catch {
        Write-StatusMessage "Failed to update profile: $($_.Exception.Message)" -Type Error
        return $false
    }
}

#endregion

#region Main Script

Write-Host ""
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  PowerShell Module Uninstaller" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

# Prompt for module/alias name if not provided
if ([string]::IsNullOrWhiteSpace($ModuleName)) {
    Write-Host "Enter the module name or alias to uninstall" -ForegroundColor White
    Write-Host "Examples: IGScan, igscan, MyModule" -ForegroundColor Gray
    Write-Host ""
    $ModuleName = Read-Host "Module/Alias Name"
}

if ([string]::IsNullOrWhiteSpace($ModuleName)) {
    Write-StatusMessage "No module name provided. Exiting." -Type Error
    exit 1
}

$ModuleName = $ModuleName.Trim()

Write-Host ""
Write-Host "Searching for: $ModuleName" -ForegroundColor Cyan
Write-Host ""

# Track what we find
$foundItems = @{
    LoadedModule     = $false
    LoadedAlias      = $false
    InstalledModule  = $false
    ProfileAlias     = $false
}

$actualModuleName = $ModuleName

# ============================================================================
# Step 1: Check if it's a loaded module
# ============================================================================

$loadedModule = Get-Module -Name $ModuleName -ErrorAction SilentlyContinue

if ($null -ne $loadedModule) {
    Write-StatusMessage "Found loaded module: $($loadedModule.Name) v$($loadedModule.Version)" -Type Info
    $foundItems.LoadedModule = $true
    $actualModuleName = $loadedModule.Name
}

# ============================================================================
# Step 2: Check if it's an alias
# ============================================================================

$aliasCmd = Get-Alias -Name $ModuleName -ErrorAction SilentlyContinue

if ($null -ne $aliasCmd) {
    Write-StatusMessage "Found alias: $ModuleName -> $($aliasCmd.Definition)" -Type Info
    $foundItems.LoadedAlias = $true

    # Try to determine the actual module name
    $moduleFromAlias = Find-ModuleByAlias -AliasName $ModuleName
    if ($null -ne $moduleFromAlias) {
        Write-StatusMessage "Alias belongs to module: $moduleFromAlias" -Type Info
        $actualModuleName = $moduleFromAlias
    }
}

# ============================================================================
# Step 3: Find all module installations
# ============================================================================

$installations = Get-AllModuleInstallations -ModuleName $actualModuleName

if ($installations.Count -gt 0) {
    Write-StatusMessage "Found $($installations.Count) module installation(s):" -Type Info
    foreach ($install in $installations) {
        Write-Host "  - $($install.Path)" -ForegroundColor Gray
    }
    $foundItems.InstalledModule = $true
}

# Also check for installations with original name if it differs
if ($actualModuleName -ne $ModuleName) {
    $altInstallations = Get-AllModuleInstallations -ModuleName $ModuleName
    if ($altInstallations.Count -gt 0) {
        Write-StatusMessage "Also found installations with original name '$ModuleName':" -Type Info
        foreach ($install in $altInstallations) {
            Write-Host "  - $($install.Path)" -ForegroundColor Gray
        }
        $installations += $altInstallations
        $foundItems.InstalledModule = $true
    }
}

# ============================================================================
# Step 4: Check PowerShell profile
# ============================================================================

if (Test-Path $PROFILE) {
    $profileContent = Get-Content $PROFILE -Raw
    $aliasPattern = "Set-Alias\s+.*?$([regex]::Escape($ModuleName))"

    if ($profileContent -match $aliasPattern) {
        Write-StatusMessage "Found alias in PowerShell profile: $PROFILE" -Type Info
        $foundItems.ProfileAlias = $true
    }
}

# ============================================================================
# Step 5: Check if anything was found
# ============================================================================

if (-not ($foundItems.Values -contains $true)) {
    Write-Host ""
    Write-StatusMessage "No module, alias, or installation found for: $ModuleName" -Type Warning
    Write-Host ""
    Write-Host "Suggestions:" -ForegroundColor Yellow
    Write-Host "  - Check spelling" -ForegroundColor Gray
    Write-Host "  - List all modules: Get-Module -ListAvailable" -ForegroundColor Gray
    Write-Host "  - List all aliases: Get-Alias" -ForegroundColor Gray
    Write-Host ""
    exit 0
}

# ============================================================================
# Step 6: Confirm removal
# ============================================================================

Write-Host ""
Write-Host "================================================================================" -ForegroundColor Yellow
Write-Host "  REMOVAL SUMMARY" -ForegroundColor Yellow
Write-Host "================================================================================" -ForegroundColor Yellow
Write-Host ""

$itemCount = 0

if ($foundItems.LoadedModule) {
    Write-Host "[X] Remove module from current session" -ForegroundColor Yellow
    $itemCount++
}

if ($foundItems.LoadedAlias) {
    Write-Host "[X] Remove alias '$ModuleName' from current session" -ForegroundColor Yellow
    $itemCount++
}

if ($foundItems.InstalledModule) {
    Write-Host "[X] Delete $($installations.Count) module installation(s) from disk" -ForegroundColor Yellow
    $itemCount++
}

if ($foundItems.ProfileAlias -and -not $KeepProfile) {
    Write-Host "[X] Remove alias from PowerShell profile" -ForegroundColor Yellow
    $itemCount++
}
elseif ($foundItems.ProfileAlias -and $KeepProfile) {
    Write-Host "[ ] Keep alias in PowerShell profile (KeepProfile flag set)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Total items to remove: $itemCount" -ForegroundColor White
Write-Host ""

if ($WhatIf) {
    Write-Host "WhatIf mode: No changes will be made" -ForegroundColor Cyan
    Write-Host ""
    exit 0
}

Write-Host "Proceed with removal? (Y/N): " -ForegroundColor Red -NoNewline
$confirmation = Read-Host

if ($confirmation -notmatch '^[Yy]') {
    Write-Host ""
    Write-StatusMessage "Cancelled by user" -Type Warning
    exit 0
}

# ============================================================================
# Step 7: Perform removal
# ============================================================================

Write-Host ""
Write-Host "Removing..." -ForegroundColor Cyan
Write-Host ""

$removalSuccess = $true

# Remove from session
if ($foundItems.LoadedModule) {
    try {
        Remove-Module -Name $actualModuleName -Force -ErrorAction Stop
        Write-StatusMessage "Removed module from session: $actualModuleName" -Type Success
    }
    catch {
        Write-StatusMessage "Failed to remove module from session: $($_.Exception.Message)" -Type Error
        $removalSuccess = $false
    }
}

# Remove alias from session
if ($foundItems.LoadedAlias) {
    try {
        Remove-Item -Path "Alias:\$ModuleName" -Force -ErrorAction Stop
        Write-StatusMessage "Removed alias from session: $ModuleName" -Type Success
    }
    catch {
        Write-StatusMessage "Failed to remove alias from session: $($_.Exception.Message)" -Type Error
        $removalSuccess = $false
    }
}

# Delete installations from disk
if ($foundItems.InstalledModule) {
    foreach ($install in $installations) {
        try {
            if (Test-Path $install.Path) {
                Remove-Item -Path $install.Path -Recurse -Force -ErrorAction Stop
                Write-StatusMessage "Deleted: $($install.Path)" -Type Success
            }
        }
        catch {
            Write-StatusMessage "Failed to delete: $($install.Path) - $($_.Exception.Message)" -Type Error
            $removalSuccess = $false
        }
    }
}

# Remove from profile
if ($foundItems.ProfileAlias -and -not $KeepProfile) {
    Remove-AliasFromProfile -AliasName $ModuleName
}

# ============================================================================
# Final Summary
# ============================================================================

Write-Host ""
Write-Host "================================================================================" -ForegroundColor Cyan

if ($removalSuccess) {
    Write-Host "  UNINSTALL COMPLETE" -ForegroundColor Green
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-StatusMessage "Successfully removed: $ModuleName" -Type Success

    if ($foundItems.ProfileAlias -and -not $KeepProfile) {
        Write-Host ""
        Write-Host "IMPORTANT: Profile was modified" -ForegroundColor Yellow
        Write-Host "           Open a new PowerShell session to ensure changes take effect" -ForegroundColor Yellow
    }
}
else {
    Write-Host "  UNINSTALL INCOMPLETE" -ForegroundColor Yellow
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-StatusMessage "Some items could not be removed. See errors above." -Type Warning
    Write-Host ""
    Write-Host "Common issues:" -ForegroundColor Yellow
    Write-Host "  - Files in use: Close programs using the module" -ForegroundColor Gray
    Write-Host "  - Permission denied: Run PowerShell as Administrator" -ForegroundColor Gray
    Write-Host "  - Profile read-only: Check file permissions on $PROFILE" -ForegroundColor Gray
}

Write-Host ""

#endregion
