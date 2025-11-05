#Requires -Version 5.1
<#
.SYNOPSIS
    Diagnoses module installation and visibility issues.

.DESCRIPTION
    Checks for common problems that prevent modules from being detected by Get-Module -ListAvailable:
    - Verifies module files exist on disk
    - Checks if module location is in PSModulePath
    - Validates manifest file structure
    - Tests module import capability
    - Provides actionable recommendations

.PARAMETER ModuleName
    Name of the module to diagnose (e.g., "IGScan")

.EXAMPLE
    .\diagnose-module.ps1 -ModuleName "IGScan"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$ModuleName
)

function Write-DiagnosticMessage {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Section')]
        [string]$Type = 'Info'
    )

    $colors = @{
        Info    = 'Cyan'
        Success = 'Green'
        Warning = 'Yellow'
        Error   = 'Red'
        Section = 'White'
    }

    $prefix = switch ($Type) {
        'Info'    { '[INFO] ' }
        'Success' { '[OK]   ' }
        'Warning' { '[!]    ' }
        'Error'   { '[X]    ' }
        'Section' { '' }
    }

    Write-Host "$prefix$Message" -ForegroundColor $colors[$Type]
}

function Invoke-ModuleCleanup {
    <#
    .SYNOPSIS
        Cleans up incorrectly installed modules and their aliases.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName,

        [Parameter(Mandatory = $true)]
        [array]$Locations
    )

    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Yellow
    Write-Host "  CLEANUP INCORRECT INSTALLATION" -ForegroundColor Yellow
    Write-Host "================================================================================" -ForegroundColor Yellow
    Write-Host ""

    Write-Host "This will remove:" -ForegroundColor White
    Write-Host ""

    # Show what will be removed
    $itemCount = 0

    # Modules from disk
    foreach ($location in $Locations) {
        Write-Host "  [X] Module folder: $($location.Path)" -ForegroundColor Yellow
        if ($location.CaseMismatch) {
            Write-Host "      (Incorrect casing: '$($location.ActualName)')" -ForegroundColor DarkYellow
        }
        $itemCount++
    }

    # Check for loaded module
    $loadedModule = Get-Module -Name $ModuleName -ErrorAction SilentlyContinue
    if ($null -ne $loadedModule) {
        Write-Host "  [X] Loaded module from memory" -ForegroundColor Yellow
        $itemCount++
    }

    # Check for aliases
    $aliases = Get-Alias | Where-Object {
        $_.Definition -match $ModuleName -or $_.Name -match $ModuleName
    }
    if ($aliases.Count -gt 0) {
        foreach ($alias in $aliases) {
            Write-Host "  [X] Alias: $($alias.Name) -> $($alias.Definition)" -ForegroundColor Yellow
            $itemCount++
        }
    }

    # Check profile
    $profileHasAlias = $false
    if (Test-Path $PROFILE) {
        $profileContent = Get-Content $PROFILE -Raw
        if ($profileContent -match "Set-Alias\s+.*?$([regex]::Escape($ModuleName))") {
            Write-Host "  [X] Alias in PowerShell profile" -ForegroundColor Yellow
            $itemCount++
            $profileHasAlias = $true
        }
    }

    Write-Host ""
    Write-Host "Total items to remove: $itemCount" -ForegroundColor White
    Write-Host ""
    Write-Host "After cleanup, you can run the install script for a fresh installation." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Proceed with cleanup? (Y/N): " -ForegroundColor Red -NoNewline
    $confirmation = Read-Host

    if ($confirmation -notmatch '^[Yy]') {
        Write-Host ""
        Write-DiagnosticMessage "Cleanup cancelled" -Type Warning
        return $false
    }

    Write-Host ""
    Write-Host "Cleaning up..." -ForegroundColor Cyan
    Write-Host ""

    $cleanupSuccess = $true

    # Remove module from memory
    if ($null -ne $loadedModule) {
        try {
            Remove-Module -Name $ModuleName -Force -ErrorAction Stop
            Write-DiagnosticMessage "Removed module from memory" -Type Success
        }
        catch {
            Write-DiagnosticMessage "Failed to remove module from memory: $($_.Exception.Message)" -Type Error
            $cleanupSuccess = $false
        }
    }

    # Remove aliases from memory
    if ($aliases.Count -gt 0) {
        foreach ($alias in $aliases) {
            try {
                Remove-Item -Path "Alias:\$($alias.Name)" -Force -ErrorAction Stop
                Write-DiagnosticMessage "Removed alias: $($alias.Name)" -Type Success
            }
            catch {
                Write-DiagnosticMessage "Failed to remove alias: $($alias.Name)" -Type Error
                $cleanupSuccess = $false
            }
        }
    }

    # Remove module folders
    foreach ($location in $Locations) {
        try {
            if (Test-Path $location.Path) {
                Remove-Item -Path $location.Path -Recurse -Force -ErrorAction Stop
                Write-DiagnosticMessage "Deleted: $($location.Path)" -Type Success
            }
        }
        catch {
            Write-DiagnosticMessage "Failed to delete: $($location.Path) - $($_.Exception.Message)" -Type Error
            $cleanupSuccess = $false
        }
    }

    # Remove from profile
    if ($profileHasAlias) {
        try {
            $profileContent = Get-Content $PROFILE -Raw -ErrorAction Stop
            $pattern = "^\s*Set-Alias\s+.*?$([regex]::Escape($ModuleName)).*$"
            $lines = $profileContent -split "`r?`n"
            $newLines = $lines | Where-Object { $_ -notmatch $pattern }

            if ($newLines.Count -lt $lines.Count) {
                $newContent = $newLines -join "`r`n"
                Set-Content -Path $PROFILE -Value $newContent -Force -ErrorAction Stop
                Write-DiagnosticMessage "Removed alias from profile" -Type Success
            }
        }
        catch {
            Write-DiagnosticMessage "Failed to update profile: $($_.Exception.Message)" -Type Error
            $cleanupSuccess = $false
        }
    }

    Write-Host ""
    if ($cleanupSuccess) {
        Write-Host "================================================================================" -ForegroundColor Green
        Write-DiagnosticMessage "CLEANUP COMPLETE!" -Type Success
        Write-Host "================================================================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "You can now run a fresh installation:" -ForegroundColor Cyan
        Write-Host "  .\install-modulefromzip.ps1 -ModuleName '$ModuleName'" -ForegroundColor White
        Write-Host ""
        if ($profileHasAlias) {
            Write-Host "NOTE: Profile was modified. Close and reopen PowerShell after reinstalling." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "================================================================================" -ForegroundColor Yellow
        Write-DiagnosticMessage "CLEANUP INCOMPLETE - See errors above" -Type Warning
        Write-Host "================================================================================" -ForegroundColor Yellow
    }

    return $cleanupSuccess
}

Write-Host ""
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  PowerShell Module Diagnostic Tool" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

# Prompt for module name if not provided
if ([string]::IsNullOrWhiteSpace($ModuleName)) {
    Write-Host "Enter the module name to diagnose" -ForegroundColor White
    Write-Host "Example: IGScan" -ForegroundColor Gray
    Write-Host ""
    $ModuleName = Read-Host "Module Name"
}

if ([string]::IsNullOrWhiteSpace($ModuleName)) {
    Write-DiagnosticMessage "No module name provided. Exiting." -Type Error
    exit 1
}

$ModuleName = $ModuleName.Trim()

Write-Host ""
Write-DiagnosticMessage "Diagnosing module: $ModuleName" -Type Section
Write-Host ""

$issues = @()
$recommendations = @()

# ============================================================================
# Test 1: Check if Get-Module can see it
# ============================================================================

Write-Host "------------------------------------------------------------------------------" -ForegroundColor DarkGray
Write-DiagnosticMessage "Test 1: PowerShell Module Discovery" -Type Section
Write-Host "------------------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

$moduleAvailable = Get-Module -ListAvailable -Name $ModuleName -ErrorAction SilentlyContinue

if ($null -ne $moduleAvailable) {
    Write-DiagnosticMessage "Module IS visible to Get-Module -ListAvailable" -Type Success
    Write-Host "  Location: $($moduleAvailable.ModuleBase)" -ForegroundColor Gray
    Write-Host "  Version:  $($moduleAvailable.Version)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "No issue detected! Your module should work correctly." -ForegroundColor Green
    exit 0
}
else {
    Write-DiagnosticMessage "Module NOT visible to Get-Module -ListAvailable" -Type Error
    $issues += "Module not discoverable by PowerShell"
}

Write-Host ""

# ============================================================================
# Test 2: Search for module files on disk
# ============================================================================

Write-Host "------------------------------------------------------------------------------" -ForegroundColor DarkGray
Write-DiagnosticMessage "Test 2: Module Files on Disk" -Type Section
Write-Host "------------------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

$modulePaths = $env:PSModulePath -split [IO.Path]::PathSeparator | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

# Add common module directories that might not be in PSModulePath
$additionalPaths = @(
    # Local Documents folder (not OneDrive-redirected)
    "$env:USERPROFILE\Documents\WindowsPowerShell\Modules"
    # Program Files
    "$env:ProgramFiles\WindowsPowerShell\Modules"
)

# Combine and deduplicate paths
$allSearchPaths = @($modulePaths) + @($additionalPaths) | Select-Object -Unique

Write-DiagnosticMessage "Searching $($modulePaths.Count) PSModulePath directories + additional common locations..." -Type Info
Write-Host ""

$foundLocations = @()
$foundOutsidePSModulePath = @()

foreach ($basePath in $allSearchPaths) {
    if (Test-Path $basePath) {
        # Case-insensitive search
        $modulePath = Join-Path $basePath $ModuleName

        if (Test-Path $modulePath) {
            $actualItem = Get-Item -Path $modulePath -ErrorAction SilentlyContinue
            if ($null -ne $actualItem) {
                $isInPSModulePath = $modulePaths -contains $basePath

                $location = [PSCustomObject]@{
                    Path              = $actualItem.FullName
                    ActualName        = $actualItem.Name
                    ExpectedName      = $ModuleName
                    CaseMismatch      = ($actualItem.Name -cne $ModuleName)
                    InPSModulePath    = $isInPSModulePath
                }

                $foundLocations += $location

                if (-not $isInPSModulePath) {
                    $foundOutsidePSModulePath += $location
                }
            }
        }
    }
}

if ($foundLocations.Count -eq 0) {
    Write-DiagnosticMessage "Module folder NOT found in any location" -Type Error
    $issues += "Module files not found on disk"

    Write-Host ""
    Write-Host "Searched in PSModulePath:" -ForegroundColor Yellow
    foreach ($path in $modulePaths) {
        Write-Host "  - $path" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "Also searched common locations:" -ForegroundColor Yellow
    foreach ($path in $additionalPaths) {
        if ($modulePaths -notcontains $path) {
            Write-Host "  - $path" -ForegroundColor Gray
        }
    }

    $recommendations += "Install the module using: .\install-modulefromzip.ps1 -ModuleName '$ModuleName'"
}
else {
    Write-DiagnosticMessage "Found $($foundLocations.Count) module folder(s):" -Type Success
    foreach ($location in $foundLocations) {
        $prefix = ""
        if (-not $location.InPSModulePath) {
            $prefix = "[WRONG LOCATION - NOT IN PSModulePath] "
        }

        if ($location.CaseMismatch) {
            Write-Host "  - $prefix$($location.Path) " -ForegroundColor Yellow -NoNewline
            Write-Host "[CASE ISSUE: '$($location.ActualName)' should be '$($location.ExpectedName)']" -ForegroundColor Red
        }
        elseif (-not $location.InPSModulePath) {
            Write-Host "  - $prefix$($location.Path)" -ForegroundColor Red
        }
        else {
            Write-Host "  - $($location.Path)" -ForegroundColor Gray
        }
    }

    # Add issues for modules found outside PSModulePath
    if ($foundOutsidePSModulePath.Count -gt 0) {
        $issues += "Module installed in wrong directory (not in PSModulePath)"
        $recommendations += "Use automatic cleanup to remove and reinstall correctly"
    }

    # Add issues for case mismatches
    $caseMismatchFound = $foundLocations | Where-Object { $_.CaseMismatch }
    if ($caseMismatchFound) {
        $issues += "Incorrect folder casing: '$($caseMismatchFound[0].ActualName)'"
        $recommendations += "Use automatic cleanup to remove and reinstall with correct casing"
    }
}

Write-Host ""

# ============================================================================
# Test 3: Check module structure
# ============================================================================

if ($foundLocations.Count -gt 0) {
    Write-Host "------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-DiagnosticMessage "Test 3: Module Structure Validation" -Type Section
    Write-Host "------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    foreach ($location in $foundLocations) {
        Write-Host "Checking: $($location.Path)" -ForegroundColor White
        Write-Host ""

        # Check for .psd1 manifest
        $manifestPath = Join-Path $location.Path "$($location.ActualName).psd1"
        $hasManifest = Test-Path $manifestPath

        if ($hasManifest) {
            Write-DiagnosticMessage "Found manifest file: $($location.ActualName).psd1" -Type Success

            # Try to load the manifest
            try {
                $manifest = Import-PowerShellDataFile -Path $manifestPath -ErrorAction Stop
                Write-DiagnosticMessage "Manifest file is valid" -Type Success

                # Check module version
                if ($manifest.ModuleVersion) {
                    Write-Host "  Module Version: $($manifest.ModuleVersion)" -ForegroundColor Gray
                }

                # Check root module
                if ($manifest.RootModule) {
                    Write-Host "  Root Module:    $($manifest.RootModule)" -ForegroundColor Gray

                    $rootModulePath = Join-Path $location.Path $manifest.RootModule
                    if (-not (Test-Path $rootModulePath)) {
                        Write-DiagnosticMessage "Root module file missing: $($manifest.RootModule)" -Type Error
                        $issues += "Root module file specified in manifest doesn't exist"
                    }
                }
            }
            catch {
                Write-DiagnosticMessage "Manifest file is INVALID: $($_.Exception.Message)" -Type Error
                $issues += "Corrupt or invalid manifest file"
                $recommendations += "Check manifest syntax at: $manifestPath"
            }
        }
        else {
            Write-DiagnosticMessage "Missing manifest file: $($location.ActualName).psd1" -Type Error
            $issues += "No .psd1 manifest file found"
        }

        # Check for .psm1 module file
        $moduleFilePath = Join-Path $location.Path "$($location.ActualName).psm1"
        $hasModuleFile = Test-Path $moduleFilePath

        if ($hasModuleFile) {
            Write-DiagnosticMessage "Found module file: $($location.ActualName).psm1" -Type Success
        }
        else {
            Write-DiagnosticMessage "Missing module file: $($location.ActualName).psm1" -Type Warning
            Write-Host "  Note: Module file is optional if functions are defined elsewhere" -ForegroundColor Gray
        }

        # List all files in module directory
        Write-Host ""
        Write-Host "  Module contents:" -ForegroundColor Gray
        Get-ChildItem -Path $location.Path -File | ForEach-Object {
            Write-Host "    - $($_.Name)" -ForegroundColor DarkGray
        }

        Write-Host ""
    }
}

# ============================================================================
# Test 4: Check PSModulePath
# ============================================================================

Write-Host "------------------------------------------------------------------------------" -ForegroundColor DarkGray
Write-DiagnosticMessage "Test 4: PSModulePath Configuration" -Type Section
Write-Host "------------------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

Write-DiagnosticMessage "PSModulePath contains $($modulePaths.Count) directories:" -Type Info
Write-Host ""

foreach ($path in $modulePaths) {
    $exists = Test-Path $path
    if ($exists) {
        Write-Host "  [OK] $path" -ForegroundColor Green
    }
    else {
        Write-Host "  [X]  $path (doesn't exist)" -ForegroundColor Red
    }
}

Write-Host ""

if ($foundLocations.Count -gt 0) {
    $moduleInPath = $false
    $hasCaseMismatch = $false

    foreach ($location in $foundLocations) {
        $locationParent = Split-Path $location.Path -Parent
        if ($modulePaths -contains $locationParent) {
            $moduleInPath = $true
        }
        if ($location.CaseMismatch) {
            $hasCaseMismatch = $true
        }
    }

    if (-not $moduleInPath) {
        Write-DiagnosticMessage "Module folder is NOT in a PSModulePath directory" -Type Error
        $issues += "Module installed outside of PSModulePath"
        $recommendations += "Use automatic cleanup below, or manually move to a valid PSModulePath location"
    }

    if ($hasCaseMismatch) {
        $issues += "Incorrect module folder casing"
        $recommendations += "Use automatic cleanup below to remove and reinstall with correct casing"
    }
}

# ============================================================================
# Test 5: Try to import the module
# ============================================================================

if ($foundLocations.Count -gt 0) {
    Write-Host "------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-DiagnosticMessage "Test 5: Module Import Test" -Type Section
    Write-Host "------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    try {
        $importedModule = Import-Module -Name $foundLocations[0].Path -PassThru -Force -ErrorAction Stop
        Write-DiagnosticMessage "Module imports successfully!" -Type Success
        Write-Host "  Name:     $($importedModule.Name)" -ForegroundColor Gray
        Write-Host "  Version:  $($importedModule.Version)" -ForegroundColor Gray
        Write-Host "  Exported: $($importedModule.ExportedCommands.Count) command(s)" -ForegroundColor Gray

        if ($importedModule.ExportedCommands.Count -gt 0) {
            Write-Host ""
            Write-Host "  Exported commands:" -ForegroundColor Gray
            $importedModule.ExportedCommands.Keys | ForEach-Object {
                Write-Host "    - $_" -ForegroundColor DarkGray
            }
        }

        # Remove the module after test
        Remove-Module -Name $importedModule.Name -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-DiagnosticMessage "Module FAILED to import: $($_.Exception.Message)" -Type Error
        $issues += "Module import failed"
        $recommendations += "Check module syntax and dependencies"
    }

    Write-Host ""
}

# ============================================================================
# Summary and Recommendations
# ============================================================================

Write-Host "------------------------------------------------------------------------------" -ForegroundColor DarkGray
Write-DiagnosticMessage "DIAGNOSIS SUMMARY" -Type Section
Write-Host "------------------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

if ($issues.Count -eq 0) {
    Write-Host "No issues detected!" -ForegroundColor Green
}
else {
    Write-Host "Issues Detected:" -ForegroundColor Red
    Write-Host ""
    foreach ($issue in $issues) {
        Write-Host "  - $issue" -ForegroundColor Yellow
    }
}

if ($recommendations.Count -gt 0) {
    Write-Host ""
    Write-Host "Recommendations:" -ForegroundColor Cyan
    Write-Host ""
    foreach ($rec in $recommendations) {
        Write-Host "  > $rec" -ForegroundColor White
    }
}

# ============================================================================
# Offer automatic cleanup for incorrect installations
# ============================================================================

$shouldOfferCleanup = $false
if ($foundLocations.Count -gt 0) {
    # Offer cleanup if module has issues that prevent it from working
    $hasIssues = $false

    # Check if any module is outside PSModulePath
    if ($foundOutsidePSModulePath.Count -gt 0) {
        $hasIssues = $true
    }

    # Check for case mismatches
    $hasCaseMismatchIssue = $foundLocations | Where-Object { $_.CaseMismatch }
    if ($hasCaseMismatchIssue) {
        $hasIssues = $true
    }

    $shouldOfferCleanup = $hasIssues
}

if ($shouldOfferCleanup) {
    Write-Host ""
    Write-Host "------------------------------------------------------------------------------" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "AUTOMATIC CLEANUP AVAILABLE" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "The module installation has issues that prevent it from working correctly." -ForegroundColor White
    Write-Host "Would you like to automatically clean up and prepare for reinstallation?" -ForegroundColor White
    Write-Host ""
    Write-Host "Cleanup will remove:" -ForegroundColor Gray
    Write-Host "  - Module files from disk" -ForegroundColor Gray
    Write-Host "  - Any loaded modules from memory" -ForegroundColor Gray
    Write-Host "  - Any related aliases" -ForegroundColor Gray
    Write-Host "  - Profile entries (if any)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Run automatic cleanup now? (Y/N): " -ForegroundColor Cyan -NoNewline
    $cleanupChoice = Read-Host

    if ($cleanupChoice -match '^[Yy]') {
        $cleanupResult = Invoke-ModuleCleanup -ModuleName $ModuleName -Locations $foundLocations
        if ($cleanupResult) {
            # Exit after successful cleanup
            exit 0
        }
    }
    else {
        Write-Host ""
        Write-DiagnosticMessage "Cleanup skipped. You can clean up manually or run: .\uninstall-module.ps1 -ModuleName '$ModuleName'" -Type Info
    }
}

Write-Host ""
Write-Host "Additional Troubleshooting:" -ForegroundColor Cyan
Write-Host "  - Close and reopen PowerShell to refresh module cache" -ForegroundColor Gray
Write-Host "  - Run: Get-Module -ListAvailable -Refresh" -ForegroundColor Gray
Write-Host "  - Check for typos in module name" -ForegroundColor Gray
Write-Host ""
