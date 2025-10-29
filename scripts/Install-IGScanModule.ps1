<#
.SYNOPSIS
    Installs or updates the IGScan PowerShell module

.DESCRIPTION
    This script automatically removes any existing IGScan module installation
    and installs the latest version from the repository.

.PARAMETER Force
    Force reinstallation even if the module is currently loaded

.EXAMPLE
    .\Install-IGScanModule.ps1

.EXAMPLE
    .\Install-IGScanModule.ps1 -Force
#>

[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Determine the repository root (script is in scripts/ subdirectory)
$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceModulePath = Join-Path $repoRoot "modules\IGScan"
$targetModulePath = Join-Path $HOME "Documents\WindowsPowerShell\Modules\IGScan"

Write-Host ""
Write-Host "=== IGScan Module Installation ===" -ForegroundColor Cyan
Write-Host ""

# Verify source module exists
if (-not (Test-Path $sourceModulePath)) {
    Write-Host "ERROR: Source module not found at: $sourceModulePath" -ForegroundColor Red
    Write-Host "Please ensure you're running this script from the dev-install repository." -ForegroundColor Yellow
    exit 1
}

# Check required files exist
$requiredFiles = @('IGScan.psd1', 'IGScan.psm1', 'Find-EmployeeRefs.ps1')
$missingFiles = @()
foreach ($file in $requiredFiles) {
    $filePath = Join-Path $sourceModulePath $file
    if (-not (Test-Path $filePath)) {
        $missingFiles += $file
    }
}

if ($missingFiles.Count -gt 0) {
    Write-Host "ERROR: Missing required files in source module:" -ForegroundColor Red
    $missingFiles | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

Write-Host "Source module validated: $sourceModulePath" -ForegroundColor Green

# Check if module is currently loaded
$loadedModule = Get-Module -Name IGScan -ErrorAction SilentlyContinue
if ($loadedModule) {
    Write-Host "Unloading currently loaded IGScan module..." -ForegroundColor Yellow
    Remove-Module IGScan -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500  # Give Windows time to release file handles
}

# Remove existing installation if found
if (Test-Path $targetModulePath) {
    Write-Host "Removing existing module installation..." -ForegroundColor Yellow
    Write-Host "  Location: $targetModulePath" -ForegroundColor Gray

    try {
        Remove-Item -Path $targetModulePath -Recurse -Force -ErrorAction Stop
        Write-Host "  Existing module removed successfully" -ForegroundColor Green
        Start-Sleep -Milliseconds 500  # Give Windows time to release file handles
    }
    catch {
        Write-Host "  WARNING: Could not remove existing module" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red

        if (-not $Force) {
            Write-Host ""
            Write-Host "Try running with -Force parameter or manually remove:" -ForegroundColor Yellow
            Write-Host "  Remove-Item -Path '$targetModulePath' -Recurse -Force" -ForegroundColor Gray
            exit 1
        }
    }
}

# Ensure target directory exists
$targetParent = Split-Path -Parent $targetModulePath
if (-not (Test-Path $targetParent)) {
    Write-Host "Creating PowerShell modules directory..." -ForegroundColor Yellow
    New-Item -Path $targetParent -ItemType Directory -Force | Out-Null
}

# Copy the module
Write-Host "Installing IGScan module..." -ForegroundColor Cyan
Write-Host "  From: $sourceModulePath" -ForegroundColor Gray
Write-Host "  To:   $targetModulePath" -ForegroundColor Gray

try {
    Copy-Item -Path $sourceModulePath -Destination $targetModulePath -Recurse -Force -ErrorAction Stop
    Write-Host "  Module copied successfully" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Failed to copy module" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Verify installation
Write-Host ""
Write-Host "Verifying installation..." -ForegroundColor Cyan

$installedFiles = Get-ChildItem -Path $targetModulePath -File -ErrorAction SilentlyContinue
if ($installedFiles.Count -eq 0) {
    Write-Host "ERROR: Installation verification failed - no files found" -ForegroundColor Red
    exit 1
}

Write-Host "Installed files:" -ForegroundColor Green
$installedFiles | ForEach-Object {
    Write-Host ("  - " + $_.Name + " (" + [Math]::Round($_.Length / 1KB, 2) + " KB)") -ForegroundColor Gray
}

# Import the module
Write-Host ""
Write-Host "Importing IGScan module..." -ForegroundColor Cyan

try {
    Import-Module IGScan -Force -ErrorAction Stop
    Write-Host "  Module imported successfully" -ForegroundColor Green
}
catch {
    Write-Host "WARNING: Module installed but failed to import" -ForegroundColor Yellow
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Try importing manually: Import-Module IGScan" -ForegroundColor Yellow
    exit 1
}

# Verify module commands
$commands = Get-Command -Module IGScan -ErrorAction SilentlyContinue
if ($commands) {
    Write-Host ""
    Write-Host "Available commands:" -ForegroundColor Green
    $commands | ForEach-Object {
        Write-Host ("  - " + $_.Name + " (Type: " + $_.CommandType + ")") -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "=== Installation Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Usage: igscan" -ForegroundColor Cyan
Write-Host "   or: Invoke-EmployeeRefScan -RootPath 'C:\path\to\repo'" -ForegroundColor Cyan
Write-Host ""
