<#
.SYNOPSIS
    Fast employee reference scanner - single-pass file scanning

.DESCRIPTION
    Scans large repositories for employee names, emails, and secrets in a single pass.
    Optimized for performance by reading each file only once.

.PARAMETER RootPath
    Root directory to scan. Auto-detects igsolutions_repo if not provided.

.PARAMETER MaxFileSizeMB
    Maximum file size to scan in MB (default: 5)

.PARAMETER Extensions
    Comma-separated list of file extensions to scan

.NOTES
    Compatible with: PowerShell 5.1+
    Requires: .NET Framework 4.5+ (included with Windows PowerShell 5.1)

    Performance: Scans each file once, checking all patterns simultaneously
    Expected speed: 30-60 seconds for 25k+ files on modern hardware

.EXAMPLE
    .\Find-EmployeeRefs.ps1
    Interactive mode - prompts for search mode and parameters

.EXAMPLE
    .\Find-EmployeeRefs.ps1 -RootPath "C:\repo\myproject"
    Scan specific directory
#>

[CmdletBinding()]
param(
    [string]$RootPath,
    [int]$MaxFileSizeMB = 5,
    [string]$Extensions
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

#region Helper Functions

function Write-SectionHeader {
    param([string]$Title, [string]$Color = 'Cyan')
    Write-Host ""
    Write-Host $Title -ForegroundColor $Color
}

function Get-ExcludedDirectoriesPattern {
    $excludedDirs = @(
        # Package managers
        'node_modules', 'bower_components', 'jspm_packages', 'packages',
        'vendor', 'vendors', 'site-packages', 'dist-packages',
        # Version control
        '\.git', '\.svn', '\.hg',
        # IDE
        '\.vs', '\.vscode', '\.idea',
        # Build outputs
        'bin', 'obj', 'dist', 'build', 'out', 'target',
        # Caches
        '\.cache', '\.next', '\.nuxt', '__pycache__',
        # Logs
        'logs', 'tmp', 'temp'
    )
    return '\\(' + ($excludedDirs -join '|') + ')(\\|$)'
}

function Get-TargetFiles {
    param(
        [string]$RootPath,
        [hashtable]$ExtensionHash,
        [long]$MaxBytes,
        [string]$ExcludePattern
    )

    $results = [System.Collections.Generic.List[string]]::new()
    $totalFiles = 0

    $stack = [System.Collections.Generic.Stack[string]]::new()
    $stack.Push($RootPath)

    while ($stack.Count -gt 0) {
        $currentDir = $stack.Pop()

        try {
            # Process directories first
            $dirs = [System.IO.Directory]::GetDirectories($currentDir)
            foreach ($dir in $dirs) {
                if ($dir -notmatch $ExcludePattern) {
                    $stack.Push($dir)
                }
            }

            # Process files
            $files = [System.IO.Directory]::GetFiles($currentDir)
            foreach ($file in $files) {
                $totalFiles++
                if ($totalFiles % 1000 -eq 0) {
                    Write-Progress -Activity "Finding files" -Status "Checked $totalFiles files, found $($results.Count)" -PercentComplete -1
                }

                # Check file size
                $fileInfo = [System.IO.FileInfo]::new($file)
                if ($fileInfo.Length -gt $MaxBytes) { continue }

                # Check extension
                $ext = $fileInfo.Extension.ToLower()
                if (-not $ext -or -not $ExtensionHash.ContainsKey($ext)) { continue }

                $results.Add($file)
            }
        }
        catch {
            # Skip inaccessible directories
        }
    }

    Write-Progress -Activity "Finding files" -Completed
    return $results
}

#endregion

#region Auto-detect Repository Path

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    Write-Host "Searching for 'igsolutions_repo'..." -ForegroundColor Cyan

    $searchPaths = @(
        (Join-Path $env:USERPROFILE "igsolutions_repo"),
        (Join-Path $env:USERPROFILE "repo\igsolutions_repo")
    )

    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            $RootPath = $path
            Write-Host "Found: $RootPath" -ForegroundColor Green
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($RootPath)) {
        $RootPath = Read-Host "Enter repository path"
    }
}

if (-not (Test-Path $RootPath)) {
    Write-Host "ERROR: Path not found: $RootPath" -ForegroundColor Red
    exit 1
}

#endregion

#region Mode Selection

Write-SectionHeader "Select Search Mode"
Write-Host "  [1] Name Mode     - Search for employee names and emails"
Write-Host "  [2] String Mode   - Search for any string (case-insensitive)"
Write-Host "  [3] Keys Mode     - Scan for exposed API keys and secrets"
Write-Host "  [Q] Quit"
Write-Host ""

$mode = $null
while (-not $mode) {
    $choice = Read-Host "Enter choice [1, 2, 3, Q]"
    switch ($choice.Trim().ToUpper()) {
        '1' { $mode = 'Name' }
        '2' { $mode = 'String' }
        '3' { $mode = 'Keys' }
        'Q' { Write-Host "Exiting."; exit 0 }
        default { Write-Host "Invalid choice. Try again." -ForegroundColor Yellow }
    }
}

#endregion

#region Input Collection

$searchPatterns = @{}
$firstName = $null
$lastName = $null
$searchString = $null

if ($mode -eq 'String') {
    $searchString = Read-Host "Enter search string"
    if ([string]::IsNullOrWhiteSpace($searchString)) {
        Write-Host "ERROR: Search string cannot be empty" -ForegroundColor Red
        exit 1
    }
    $searchString = $searchString.Trim()
}
elseif ($mode -eq 'Name') {
    $firstName = (Read-Host "First name (or press Enter to skip)").Trim()
    $lastName = (Read-Host "Last name (or press Enter to skip)").Trim()

    if ([string]::IsNullOrWhiteSpace($firstName) -and [string]::IsNullOrWhiteSpace($lastName)) {
        Write-Host "ERROR: Must provide at least first or last name" -ForegroundColor Red
        exit 1
    }

    # Build patterns for name search
    $username = $null
    if (-not [string]::IsNullOrWhiteSpace($firstName) -and -not [string]::IsNullOrWhiteSpace($lastName)) {
        $username = ($firstName.Substring(0, 1) + $lastName).ToLower()
    }

    # Critical patterns
    if (-not [string]::IsNullOrWhiteSpace($firstName) -and -not [string]::IsNullOrWhiteSpace($lastName)) {
        $fullNameProper = (Get-Culture).TextInfo.ToTitleCase($firstName.ToLower()) + " " + (Get-Culture).TextInfo.ToTitleCase($lastName.ToLower())
        $searchPatterns['Critical_USER'] = @{
            Pattern = [regex]::new("USER $($username.ToUpper())", [System.Text.RegularExpressions.RegexOptions]::Compiled)
            Display = "USER $($username.ToUpper())"
        }
        $searchPatterns['Critical_FullName'] = @{
            Pattern = [regex]::new([regex]::Escape($fullNameProper), [System.Text.RegularExpressions.RegexOptions]::Compiled -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            Display = $fullNameProper
        }
    }

    # Email patterns
    if ($username) {
        $searchPatterns['Email_IGSolutions'] = @{
            Pattern = [regex]::new([regex]::Escape("$username@igsolutions.com"), [System.Text.RegularExpressions.RegexOptions]::Compiled -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            Display = "$username@igsolutions.com"
        }
        $searchPatterns['Email_Intelliguard'] = @{
            Pattern = [regex]::new([regex]::Escape("$username@intelliguardhealth.com"), [System.Text.RegularExpressions.RegexOptions]::Compiled -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            Display = "$username@intelliguardhealth.com"
        }
        $searchPatterns['Email_Unknown'] = @{
            Pattern = [regex]::new("\b$([regex]::Escape($username))@(?!(?:igsolutions\.com|intelliguardhealth\.com)\b)[a-z0-9.-]+\.[a-z]{2,}\b", [System.Text.RegularExpressions.RegexOptions]::Compiled -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            Display = "$username@<unknown-domain>"
        }
    }

    # Warning patterns
    if ($username) {
        $searchPatterns['Warning_Username'] = @{
            Pattern = [regex]::new("\b$([regex]::Escape($username))\b(?!@)", [System.Text.RegularExpressions.RegexOptions]::Compiled -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            Display = $username
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($firstName)) {
        $searchPatterns['Warning_FirstName'] = @{
            Pattern = [regex]::new("\s$([regex]::Escape($firstName))\s", [System.Text.RegularExpressions.RegexOptions]::Compiled -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            Display = $firstName
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($lastName)) {
        $searchPatterns['Warning_LastName'] = @{
            Pattern = [regex]::new("\s$([regex]::Escape($lastName))\s", [System.Text.RegularExpressions.RegexOptions]::Compiled -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            Display = $lastName
        }
    }
}
elseif ($mode -eq 'Keys') {
    $customKey = (Read-Host "Optional: Enter specific key to search for (or press Enter)").Trim()

    $keyPatterns = @(
        '(?<![A-Z0-9])(AKIA|ASIA)[A-Z0-9]{16}(?![A-Z0-9])',  # AWS Access Keys
        'eyJ[A-Za-z0-9_-]+?\.[A-Za-z0-9_-]+?\.[A-Za-z0-9_-]+',  # JWT tokens
        '(?i)(api[_-]?key|access[_-]?key|secret[_-]?key|token)\s*[:=]\s*[''"]?[A-Za-z0-9/\+\-_=]{20,}[''"]?'  # Generic keys
    )

    if ($customKey) {
        $keyPatterns += [regex]::Escape($customKey)
    }

    $combinedPattern = '(' + ($keyPatterns -join '|') + ')'
    $searchPatterns['Keys_Potential'] = @{
        Pattern = [regex]::new($combinedPattern, [System.Text.RegularExpressions.RegexOptions]::Compiled)
        Display = "Potential secrets/keys"
    }
}

#endregion

#region File Enumeration

Write-Host ""
Write-Host "Preparing to scan..." -ForegroundColor Cyan

$maxBytes = [Math]::Max(1, $MaxFileSizeMB) * 1MB

if ([string]::IsNullOrWhiteSpace($Extensions)) {
    $Extensions = '.ps1,.psm1,.psd1,.cs,.csproj,.vb,.sln,.ts,.tsx,.js,.jsx,.json,.html,.css,.scss,.md,.txt,.yml,.yaml,.xml,.config,.sql,.sh,.bat,.cmd'
}

$extHash = @{}
$Extensions.Split(',') | ForEach-Object {
    $ext = $_.Trim().ToLower()
    if ($ext -and -not $ext.StartsWith('.')) { $ext = ".$ext" }
    if ($ext) { $extHash[$ext] = $true }
}

$excludePattern = Get-ExcludedDirectoriesPattern
$targetFiles = Get-TargetFiles -RootPath $RootPath -ExtensionHash $extHash -MaxBytes $maxBytes -ExcludePattern $excludePattern

if ($targetFiles.Count -eq 0) {
    Write-Host "No files found to scan" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($targetFiles.Count) files to scan" -ForegroundColor Green

#endregion

#region Parallel Scanning with Runspaces

Write-Host ""
Write-Host "Scanning files..." -ForegroundColor Cyan

# Determine optimal thread count (CPU cores, max 8 for I/O bound work)
$threadCount = [Math]::Min([Environment]::ProcessorCount, 8)
Write-Host "Using $threadCount parallel threads" -ForegroundColor Gray

# Thread-safe concurrent collections for results
$results = [System.Collections.Concurrent.ConcurrentDictionary[string, System.Collections.Concurrent.ConcurrentBag[string]]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($key in $searchPatterns.Keys) {
    [void]$results.TryAdd($key, [System.Collections.Concurrent.ConcurrentBag[string]]::new())
}
if ($mode -eq 'String') {
    [void]$results.TryAdd('StringMatch', [System.Collections.Concurrent.ConcurrentBag[string]]::new())
}

# Shared counter for progress
$script:processedCount = 0
$syncHash = [hashtable]::Synchronized(@{ Processed = 0 })

# Create runspace pool
$runspacePool = [runspacefactory]::CreateRunspacePool(1, $threadCount)
$runspacePool.Open()

# Scriptblock for parallel execution
$scanScriptBlock = {
    param($File, $SearchPatterns, $Mode, $SearchString, $Results, $SyncHash)

    try {
        # Read file content
        $content = [System.IO.File]::ReadAllText($File)

        if ($Mode -eq 'String') {
            if ($content -match [regex]::Escape($SearchString)) {
                $Results['StringMatch'].Add($File)
            }
        }
        else {
            # Check all patterns
            foreach ($key in $SearchPatterns.Keys) {
                if ($SearchPatterns[$key].Pattern.IsMatch($content)) {
                    $Results[$key].Add($File)
                }
            }
        }
    }
    catch {
        # Skip files that can't be read (binary, locked, etc.)
    }

    # Update progress counter
    $null = [System.Threading.Interlocked]::Increment([ref]$SyncHash.Processed)
}

# Create and start all runspaces
$runspaces = [System.Collections.ArrayList]::new()
$startTime = Get-Date

foreach ($file in $targetFiles) {
    $powershell = [powershell]::Create().AddScript($scanScriptBlock).AddArgument($file).AddArgument($searchPatterns).AddArgument($mode).AddArgument($searchString).AddArgument($results).AddArgument($syncHash)
    $powershell.RunspacePool = $runspacePool

    [void]$runspaces.Add([PSCustomObject]@{
        PowerShell = $powershell
        AsyncResult = $powershell.BeginInvoke()
    })
}

# Monitor progress
$totalFiles = $targetFiles.Count
while ($runspaces.AsyncResult.IsCompleted -contains $false) {
    $processed = $syncHash.Processed
    $elapsed = (Get-Date) - $startTime
    $rate = if ($elapsed.TotalSeconds -gt 0) { [int]($processed / $elapsed.TotalSeconds) } else { 0 }
    $pct = if ($totalFiles -gt 0) { [int](($processed / $totalFiles) * 100) } else { 0 }

    Write-Progress -Activity "Scanning files (parallel)" -Status "$processed of $totalFiles ($rate files/sec)" -PercentComplete $pct
    Start-Sleep -Milliseconds 200
}

# Wait for all runspaces to complete and clean up
foreach ($runspace in $runspaces) {
    $null = $runspace.PowerShell.EndInvoke($runspace.AsyncResult)
    $runspace.PowerShell.Dispose()
}

$runspacePool.Close()
$runspacePool.Dispose()

Write-Progress -Activity "Scanning files" -Completed

$elapsed = (Get-Date) - $startTime
Write-Host "Scan completed in $([int]$elapsed.TotalSeconds) seconds ($threadCount threads)" -ForegroundColor Green

# Convert ConcurrentBag results to sorted arrays for display
$sortedResults = @{}
foreach ($key in $results.Keys) {
    $sortedResults[$key] = $results[$key].ToArray() | Sort-Object -Unique
}
$results = $sortedResults

#endregion

#region Display Results

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "SCAN RESULTS" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan

if ($mode -eq 'String') {
    Write-SectionHeader "String Match: `"$searchString`"" 'Yellow'
    if ($results.ContainsKey('StringMatch') -and @($results['StringMatch']).Count -gt 0) {
        $results['StringMatch'] | ForEach-Object { Write-Host "  $_" }
    }
    else {
        Write-Host "  No matches found" -ForegroundColor Gray
    }
}
elseif ($mode -eq 'Name') {
    # Critical findings
    Write-SectionHeader "CRITICAL FINDINGS" 'Red'
    $criticalFound = $false
    foreach ($key in ($results.Keys | Where-Object { $_ -like 'Critical_*' } | Sort-Object)) {
        if (@($results[$key]).Count -gt 0) {
            $criticalFound = $true
            Write-Host "  Pattern: $($searchPatterns[$key].Display)" -ForegroundColor Yellow
            $results[$key] | ForEach-Object { Write-Host "    $_" }
        }
    }
    if (-not $criticalFound) {
        Write-Host "  None found" -ForegroundColor Gray
    }

    # Email findings
    Write-SectionHeader "IG SOLUTIONS EMAIL" 'Blue'
    if ($results.ContainsKey('Email_IGSolutions') -and @($results['Email_IGSolutions']).Count -gt 0) {
        Write-Host "  Pattern: $($searchPatterns['Email_IGSolutions'].Display)" -ForegroundColor Yellow
        $results['Email_IGSolutions'] | ForEach-Object { Write-Host "    $_" }
    }
    else {
        Write-Host "  None found" -ForegroundColor Gray
    }

    Write-SectionHeader "INTELLIGUARD HEALTH EMAIL" 'Blue'
    if ($results.ContainsKey('Email_Intelliguard') -and @($results['Email_Intelliguard']).Count -gt 0) {
        Write-Host "  Pattern: $($searchPatterns['Email_Intelliguard'].Display)" -ForegroundColor Yellow
        $results['Email_Intelliguard'] | ForEach-Object { Write-Host "    $_" }
    }
    else {
        Write-Host "  None found" -ForegroundColor Gray
    }

    Write-SectionHeader "UNKNOWN EMAIL DOMAINS" 'Red'
    if ($results.ContainsKey('Email_Unknown') -and @($results['Email_Unknown']).Count -gt 0) {
        Write-Host "  Pattern: $($searchPatterns['Email_Unknown'].Display)" -ForegroundColor Yellow
        $results['Email_Unknown'] | ForEach-Object { Write-Host "    $_" }
    }
    else {
        Write-Host "  None found" -ForegroundColor Gray
    }

    # Warnings
    Write-SectionHeader "WARNINGS" 'Yellow'
    $warningFound = $false
    foreach ($key in ($results.Keys | Where-Object { $_ -like 'Warning_*' } | Sort-Object)) {
        if (@($results[$key]).Count -gt 0) {
            $warningFound = $true
            Write-Host "  Pattern: $($searchPatterns[$key].Display)" -ForegroundColor Yellow
            $results[$key] | ForEach-Object { Write-Host "    $_" }
        }
    }
    if (-not $warningFound) {
        Write-Host "  None found" -ForegroundColor Gray
    }
}
elseif ($mode -eq 'Keys') {
    Write-SectionHeader "POTENTIAL SECRETS/KEYS" 'Red'
    if ($results.ContainsKey('Keys_Potential') -and @($results['Keys_Potential']).Count -gt 0) {
        $results['Keys_Potential'] | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
        Write-Host ""
        Write-Host "  WARNING: Review these files manually for false positives" -ForegroundColor Yellow
    }
    else {
        Write-Host "  None found" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Scanned $($targetFiles.Count) files" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

#endregion
