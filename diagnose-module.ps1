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
        'Success' { '[✓]    ' }
        'Warning' { '[!]    ' }
        'Error'   { '[✗]    ' }
        'Section' { '' }
    }

    Write-Host "$prefix$Message" -ForegroundColor $colors[$Type]
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

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-DiagnosticMessage "Test 1: PowerShell Module Discovery" -Type Section
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
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

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-DiagnosticMessage "Test 2: Module Files on Disk" -Type Section
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""

$modulePaths = $env:PSModulePath -split [IO.Path]::PathSeparator | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

Write-DiagnosticMessage "Searching $($modulePaths.Count) module directories..." -Type Info
Write-Host ""

$foundLocations = @()

foreach ($basePath in $modulePaths) {
    if (Test-Path $basePath) {
        # Case-insensitive search
        $modulePath = Join-Path $basePath $ModuleName

        if (Test-Path $modulePath) {
            $actualItem = Get-Item -Path $modulePath -ErrorAction SilentlyContinue
            if ($null -ne $actualItem) {
                $foundLocations += [PSCustomObject]@{
                    Path            = $actualItem.FullName
                    ActualName      = $actualItem.Name
                    ExpectedName    = $ModuleName
                    CaseMismatch    = ($actualItem.Name -cne $ModuleName)
                }
            }
        }
    }
}

if ($foundLocations.Count -eq 0) {
    Write-DiagnosticMessage "Module folder NOT found in any PSModulePath location" -Type Error
    $issues += "Module files not found on disk"

    Write-Host ""
    Write-Host "Searched in:" -ForegroundColor Yellow
    foreach ($path in $modulePaths) {
        Write-Host "  - $path" -ForegroundColor Gray
    }

    $recommendations += "Install the module using: .\install-modulefromzip.ps1 -ModuleName '$ModuleName'"
}
else {
    Write-DiagnosticMessage "Found $($foundLocations.Count) module folder(s):" -Type Success
    foreach ($location in $foundLocations) {
        if ($location.CaseMismatch) {
            Write-Host "  - $($location.Path) " -ForegroundColor Yellow -NoNewline
            Write-Host "[CASE ISSUE: '$($location.ActualName)' should be '$($location.ExpectedName)']" -ForegroundColor Red
            $issues += "Incorrect folder casing: '$($location.ActualName)'"
            $recommendations += "Uninstall and reinstall with correct casing using the install script"
        }
        else {
            Write-Host "  - $($location.Path)" -ForegroundColor Gray
        }
    }
}

Write-Host ""

# ============================================================================
# Test 3: Check module structure
# ============================================================================

if ($foundLocations.Count -gt 0) {
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-DiagnosticMessage "Test 3: Module Structure Validation" -Type Section
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
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

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-DiagnosticMessage "Test 4: PSModulePath Configuration" -Type Section
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""

Write-DiagnosticMessage "PSModulePath contains $($modulePaths.Count) directories:" -Type Info
Write-Host ""

foreach ($path in $modulePaths) {
    $exists = Test-Path $path
    if ($exists) {
        Write-Host "  [✓] $path" -ForegroundColor Green
    }
    else {
        Write-Host "  [✗] $path (doesn't exist)" -ForegroundColor Red
    }
}

Write-Host ""

if ($foundLocations.Count -gt 0) {
    $moduleInPath = $false
    foreach ($location in $foundLocations) {
        $locationParent = Split-Path $location.Path -Parent
        if ($modulePaths -contains $locationParent) {
            $moduleInPath = $true
            break
        }
    }

    if (-not $moduleInPath) {
        Write-DiagnosticMessage "Module folder is NOT in a PSModulePath directory" -Type Error
        $issues += "Module installed outside of PSModulePath"
        $recommendations += "Move module to a valid PSModulePath location or add the module's parent directory to PSModulePath"
    }
}

# ============================================================================
# Test 5: Try to import the module
# ============================================================================

if ($foundLocations.Count -gt 0) {
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-DiagnosticMessage "Test 5: Module Import Test" -Type Section
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
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

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-DiagnosticMessage "DIAGNOSIS SUMMARY" -Type Section
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""

if ($issues.Count -eq 0) {
    Write-Host "No issues detected!" -ForegroundColor Green
}
else {
    Write-Host "Issues Detected:" -ForegroundColor Red
    Write-Host ""
    foreach ($issue in $issues) {
        Write-Host "  • $issue" -ForegroundColor Yellow
    }
}

if ($recommendations.Count -gt 0) {
    Write-Host ""
    Write-Host "Recommendations:" -ForegroundColor Cyan
    Write-Host ""
    foreach ($rec in $recommendations) {
        Write-Host "  → $rec" -ForegroundColor White
    }
}

Write-Host ""
Write-Host "Additional Troubleshooting:" -ForegroundColor Cyan
Write-Host "  • Close and reopen PowerShell to refresh module cache" -ForegroundColor Gray
Write-Host "  • Run: Get-Module -ListAvailable -Refresh" -ForegroundColor Gray
Write-Host "  • Check for typos in module name" -ForegroundColor Gray
Write-Host ""
