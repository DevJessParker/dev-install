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
    [string]$Extensions,
    [switch]$IncludeLineNumbers
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
Write-Host "  [4] File Mode     - Search for files by name"
Write-Host "  [Q] Quit"
Write-Host ""

$mode = $null
while (-not $mode) {
    $choice = Read-Host "Enter choice [1, 2, 3, 4, Q]"
    switch ($choice.Trim().ToUpper()) {
        '1' { $mode = 'Name' }
        '2' { $mode = 'String' }
        '3' { $mode = 'Keys' }
        '4' { $mode = 'File' }
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

    # Build username from first initial + last name
    $username = $null
    $fullNameProper = $null
    if (-not [string]::IsNullOrWhiteSpace($firstName) -and -not [string]::IsNullOrWhiteSpace($lastName)) {
        $username = ($firstName.Substring(0, 1) + $lastName).ToLower()
        $fullNameProper = (Get-Culture).TextInfo.ToTitleCase($firstName.ToLower()) + " " + (Get-Culture).TextInfo.ToTitleCase($lastName.ToLower())
    }

    # Build ONE combined mega-pattern for maximum performance (single regex search per file)
    $patternParts = @()

    # Critical patterns
    if (-not [string]::IsNullOrWhiteSpace($firstName) -and -not [string]::IsNullOrWhiteSpace($lastName)) {
        $patternParts += "USER $($username.ToUpper())"
        $patternParts += [regex]::Escape($fullNameProper)
    }

    # Single email pattern - just username@ (no domain categorization during scan)
    if ($username) {
        $patternParts += "$([regex]::Escape($username))@[a-z0-9.-]+(?:\.[a-z]{2,})?"
    }

    # Warning patterns - username, firstName, lastName
    if ($username) {
        $patternParts += "\b$([regex]::Escape($username))\b(?!@)"
    }
    if (-not [string]::IsNullOrWhiteSpace($firstName)) {
        $patternParts += "\s$([regex]::Escape($firstName))\s"
    }
    if (-not [string]::IsNullOrWhiteSpace($lastName)) {
        $patternParts += "\s$([regex]::Escape($lastName))\s"
    }

    if ($patternParts.Count -gt 0) {
        # Combine all patterns with alternation - ONE pattern to rule them all!
        $combinedPattern = "($($patternParts -join '|'))"
        $searchPatterns['Combined_All'] = @{
            Pattern = [regex]::new($combinedPattern, [System.Text.RegularExpressions.RegexOptions]::Compiled -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            Display = "All patterns"
            Username = $username
            FirstName = $firstName
            LastName = $lastName
            FullName = $fullNameProper
        }
    }
}
elseif ($mode -eq 'File') {
    Write-Host ""
    Write-Host "File search options:" -ForegroundColor Cyan
    Write-Host "  [1] Exact filename (e.g., 'config.json')"
    Write-Host "  [2] Partial filename (e.g., 'config')"
    Write-Host "  [3] Exact name, any extension (e.g., 'config' → config.*)"
    Write-Host ""

    $fileSearchMode = $null
    while (-not $fileSearchMode) {
        $choice = Read-Host "Choose option [1, 2, 3]"
        switch ($choice.Trim()) {
            '1' { $fileSearchMode = 'Exact' }
            '2' { $fileSearchMode = 'Partial' }
            '3' { $fileSearchMode = 'AnyExtension' }
            default { Write-Host "Invalid choice. Try again." -ForegroundColor Yellow }
        }
    }

    $fileName = Read-Host "Enter filename to search"
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        Write-Host "ERROR: Filename cannot be empty" -ForegroundColor Red
        exit 1
    }
    $fileName = $fileName.Trim()
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

#region File Search Mode (Special handling - no content scanning)

if ($mode -eq 'File') {
    Write-Host ""
    Write-Host "Searching filenames..." -ForegroundColor Cyan

    $matchedFiles = [System.Collections.Generic.List[string]]::new()
    $startTime = Get-Date

    foreach ($file in $targetFiles) {
        $fileNameOnly = [System.IO.Path]::GetFileName($file)
        $fileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($file)

        $isMatch = $false
        switch ($fileSearchMode) {
            'Exact' {
                # Exact match (case-insensitive)
                if ($fileNameOnly -eq $fileName) {
                    $isMatch = $true
                }
            }
            'Partial' {
                # Partial match (case-insensitive)
                if ($fileNameOnly -like "*$fileName*") {
                    $isMatch = $true
                }
            }
            'AnyExtension' {
                # Exact name without extension
                if ($fileNameWithoutExt -eq $fileName) {
                    $isMatch = $true
                }
            }
        }

        if ($isMatch) {
            $matchedFiles.Add($file)
        }
    }

    $elapsed = (Get-Date) - $startTime

    # Display results
    Write-Host ""
    Write-Host "=" * 80 -ForegroundColor Cyan
    Write-Host "FILE SEARCH RESULTS" -ForegroundColor Cyan
    Write-Host "=" * 80 -ForegroundColor Cyan
    Write-Host ""

    $modeDescription = switch ($fileSearchMode) {
        'Exact' { "Exact match" }
        'Partial' { "Partial match" }
        'AnyExtension' { "Exact name, any extension" }
    }

    Write-Host "Query: `"$fileName`" ($modeDescription)" -ForegroundColor Yellow
    Write-Host "Found $($matchedFiles.Count) file(s) in $([int]$elapsed.TotalSeconds) second(s)" -ForegroundColor Green
    Write-Host ""

    if ($matchedFiles.Count -gt 0) {
        foreach ($file in $matchedFiles) {
            Write-Host "  $file" -ForegroundColor White
        }
    }
    else {
        Write-Host "  No files found matching '$fileName'" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "=" * 80 -ForegroundColor Cyan
    Write-Host "Searched $($targetFiles.Count) files" -ForegroundColor Cyan
    Write-Host "=" * 80 -ForegroundColor Cyan
    Write-Host ""

    exit 0
}

#endregion

#region Parallel Scanning with Runspaces

Write-Host ""
Write-Host "Scanning files..." -ForegroundColor Cyan

# Determine optimal thread count (CPU cores, max 8 for I/O bound work)
$threadCount = [Math]::Min([Environment]::ProcessorCount, 8)
Write-Host "Using $threadCount parallel threads" -ForegroundColor Gray
Write-Host ""

# Thread-safe concurrent collections for results (now with line numbers)
# Structure: PatternKey -> ConcurrentBag of "FilePath|LineNumber1,LineNumber2,..."
$results = [System.Collections.Concurrent.ConcurrentDictionary[string, System.Collections.Concurrent.ConcurrentBag[object]]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($key in $searchPatterns.Keys) {
    [void]$results.TryAdd($key, [System.Collections.Concurrent.ConcurrentBag[object]]::new())
}
if ($mode -eq 'String') {
    [void]$results.TryAdd('StringMatch', [System.Collections.Concurrent.ConcurrentBag[object]]::new())
}

# Pattern-specific counters for progress display
$patternCounts = [System.Collections.Concurrent.ConcurrentDictionary[string, int]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($key in $searchPatterns.Keys) {
    [void]$patternCounts.TryAdd($key, 0)
}
if ($mode -eq 'String') {
    [void]$patternCounts.TryAdd('StringMatch', 0)
}

# Create runspace pool
$runspacePool = [runspacefactory]::CreateRunspacePool(1, $threadCount)
$runspacePool.Open()

# Scriptblock for parallel execution
$scanScriptBlock = {
    param($File, $SearchPatterns, $Mode, $SearchString, $Results, $PatternCounts, $IncludeLineNumbers)

    # Helper to detect if a line is commented (only used if line numbers enabled)
    function Is-CommentedLine {
        param([string]$line)
        $trimmed = $line.TrimStart()
        # Common comment patterns: SQL (--), PowerShell (#), C-style (//), Batch (REM)
        return ($trimmed -match '^(--|#|//|REM\s|/\*|\*)')
    }

    try {
        $content = [System.IO.File]::ReadAllText($File)
        if ([string]::IsNullOrEmpty($content)) { return }

        # Only do expensive line number tracking if requested
        if ($IncludeLineNumbers) {
            # Build line start position map ONCE (much faster than counting newlines repeatedly)
            $lineStarts = [System.Collections.Generic.List[int]]::new()
            $lineStarts.Add(0)
            for ($i = 0; $i -lt $content.Length; $i++) {
                if ($content[$i] -eq "`n") {
                    $lineStarts.Add($i + 1)
                }
            }

            # Also get line texts for comment detection
            $lines = $content -split "`n"

            # Fast line number lookup function
            $getLineNumber = {
                param([int]$charPos)
                for ($idx = $lineStarts.Count - 1; $idx -ge 0; $idx--) {
                    if ($charPos -ge $lineStarts[$idx]) {
                        return $idx + 1
                    }
                }
                return 1
            }
        }

        if ($Mode -eq 'String') {
            $pattern = [regex]::new([regex]::Escape($SearchString), [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $matches = $pattern.Matches($content)

            if ($matches.Count -gt 0) {
                if ($IncludeLineNumbers) {
                    # Detailed mode with line numbers and comment detection
                    $matchedLines = [System.Collections.Generic.HashSet[int]]::new()
                    $commentedLines = [System.Collections.Generic.HashSet[int]]::new()

                    foreach ($match in $matches) {
                        $lineNum = & $getLineNumber $match.Index
                        [void]$matchedLines.Add($lineNum)
                        # Check if this line is commented
                        if (Is-CommentedLine $lines[$lineNum - 1]) {
                            [void]$commentedLines.Add($lineNum)
                        }
                    }

                    $activeLines = [System.Collections.Generic.HashSet[int]]::new($matchedLines)
                    $activeLines.ExceptWith($commentedLines)

                    if ($activeLines.Count -gt 0) {
                        $Results['StringMatch'].Add([PSCustomObject]@{
                            File = $File
                            Lines = ($activeLines | Sort-Object)
                        })
                        $null = $PatternCounts.AddOrUpdate('StringMatch', 1, { param($k, $v) $v + 1 })
                    }

                    if ($commentedLines.Count -gt 0) {
                        $Results['StringMatch_Commented'].Add([PSCustomObject]@{
                            File = $File
                            Lines = ($commentedLines | Sort-Object)
                        })
                    }
                } else {
                    # Fast mode - just record file has matches
                    $Results['StringMatch'].Add([PSCustomObject]@{
                        File = $File
                        Lines = @()  # Empty array when line numbers disabled
                    })
                    $null = $PatternCounts.AddOrUpdate('StringMatch', 1, { param($k, $v) $v + 1 })
                }
            }
        }
        else {
            # Name or Keys mode - use combined pattern for maximum speed
            foreach ($key in $SearchPatterns.Keys) {
                $pattern = $SearchPatterns[$key].Pattern
                $matches = $pattern.Matches($content)

                if ($matches.Count -gt 0) {
                    # Special handling for Combined_All - categorize based on matched text
                    if ($key -eq 'Combined_All') {
                        # Get metadata from pattern
                        $username = $SearchPatterns[$key].Username
                        $fullName = $SearchPatterns[$key].FullName

                        # Group matches by category using simple string checks
                        $categoryMatches = @{
                            'Critical_USER' = [System.Collections.Generic.HashSet[int]]::new()
                            'Critical_FullName' = [System.Collections.Generic.HashSet[int]]::new()
                            'Email_All' = [System.Collections.Generic.HashSet[int]]::new()
                            'Warning_All' = [System.Collections.Generic.HashSet[int]]::new()
                        }

                        # Store full email text for display coloring later
                        $emailMatches = [System.Collections.Generic.List[PSCustomObject]]::new()

                        foreach ($match in $matches) {
                            $matchText = $match.Value
                            $matchTextLower = $matchText.ToLower()

                            # Categorize based on matched text (simple string checks - FAST!)
                            $category = if ($matchText -eq "USER $($username.ToUpper())") {
                                'Critical_USER'
                            } elseif ($fullName -and $matchTextLower -eq $fullName.ToLower()) {
                                'Critical_FullName'
                            } elseif ($matchText.Contains('@')) {
                                'Email_All'
                            } else {
                                'Warning_All'
                            }

                            if ($IncludeLineNumbers) {
                                $lineNum = & $getLineNumber $match.Index
                                [void]$categoryMatches[$category].Add($lineNum)

                                # Store email match details for later display
                                if ($category -eq 'Email_All') {
                                    $emailMatches.Add([PSCustomObject]@{
                                        Email = $matchText
                                        LineNum = $lineNum
                                    })
                                }
                            } else {
                                [void]$categoryMatches[$category].Add(0)  # Placeholder

                                # Store email match details for later display
                                if ($category -eq 'Email_All') {
                                    $emailMatches.Add([PSCustomObject]@{
                                        Email = $matchText
                                        LineNum = 0
                                    })
                                }
                            }
                        }

                        # Store results for each category that has matches
                        foreach ($category in $categoryMatches.Keys) {
                            if ($categoryMatches[$category].Count -gt 0) {
                                if (-not $Results.ContainsKey($category)) {
                                    [void]$Results.TryAdd($category, [System.Collections.Concurrent.ConcurrentBag[object]]::new())
                                }
                                if (-not $PatternCounts.ContainsKey($category)) {
                                    [void]$PatternCounts.TryAdd($category, 0)
                                }

                                $resultObj = [PSCustomObject]@{
                                    File = $File
                                    Lines = if ($IncludeLineNumbers) { ($categoryMatches[$category] | Sort-Object | Select-Object -Unique) } else { @() }
                                }

                                # Add email details if this is email category
                                if ($category -eq 'Email_All' -and $emailMatches.Count -gt 0) {
                                    $resultObj | Add-Member -NotePropertyName 'Emails' -NotePropertyValue $emailMatches
                                }

                                $Results[$category].Add($resultObj)
                                $null = $PatternCounts.AddOrUpdate($category, 1, { param($k, $v) $v + 1 })
                            }
                        }
                    }
                    else {
                        # Keys mode or other patterns
                        if ($IncludeLineNumbers) {
                            $matchedLines = [System.Collections.Generic.HashSet[int]]::new()
                            foreach ($match in $matches) {
                                $lineNum = & $getLineNumber $match.Index
                                [void]$matchedLines.Add($lineNum)
                            }

                            if ($matchedLines.Count -gt 0) {
                                $Results[$key].Add([PSCustomObject]@{
                                    File = $File
                                    Lines = ($matchedLines | Sort-Object)
                                })
                                $null = $PatternCounts.AddOrUpdate($key, 1, { param($k, $v) $v + 1 })
                            }
                        } else {
                            $Results[$key].Add([PSCustomObject]@{
                                File = $File
                                Lines = @()
                            })
                            $null = $PatternCounts.AddOrUpdate($key, 1, { param($k, $v) $v + 1 })
                        }
                    }
                }
            }
        }
    }
    catch {
        # Skip files that can't be read (binary, locked, etc.)
    }
}

# Create and start all runspaces
$runspaces = [System.Collections.ArrayList]::new()
$startTime = Get-Date

foreach ($file in $targetFiles) {
    $powershell = [powershell]::Create().AddScript($scanScriptBlock).AddArgument($file).AddArgument($searchPatterns).AddArgument($mode).AddArgument($searchString).AddArgument($results).AddArgument($patternCounts).AddArgument($IncludeLineNumbers.IsPresent)
    $powershell.RunspacePool = $runspacePool

    [void]$runspaces.Add([PSCustomObject]@{
        PowerShell = $powershell
        AsyncResult = $powershell.BeginInvoke()
        File = $file
    })
}

# Monitor progress with pattern-specific updates
$totalFiles = $targetFiles.Count
$lastDisplayTime = $startTime
$displayInterval = [TimeSpan]::FromMilliseconds(500)

Write-Host "Progress updates:" -ForegroundColor Gray

while ($runspaces.AsyncResult.IsCompleted -contains $false) {
    $completed = ($runspaces.AsyncResult.IsCompleted | Where-Object { $_ -eq $true }).Count
    $elapsed = (Get-Date) - $startTime
    $rate = if ($elapsed.TotalSeconds -gt 0) { [int]($completed / $elapsed.TotalSeconds) } else { 0 }
    $pct = if ($totalFiles -gt 0) { [int](($completed / $totalFiles) * 100) } else { 0 }

    # Update progress bar
    Write-Progress -Activity "Scanning files (parallel - $threadCount threads)" -Status "$completed of $totalFiles ($rate files/sec)" -PercentComplete $pct

    # Show pattern-specific progress every 500ms
    $now = Get-Date
    if (($now - $lastDisplayTime) -ge $displayInterval) {
        $lastDisplayTime = $now

        # Get current match counts
        $totalMatches = 0
        $patternSummary = [System.Text.StringBuilder]::new()
        [void]$patternSummary.Append("  Files: $completed/$totalFiles ($pct%) | Matches: ")

        $sortedKeys = $patternCounts.Keys | Sort-Object
        foreach ($key in $sortedKeys) {
            $count = $patternCounts[$key]
            if ($count -gt 0) {
                $totalMatches += $count
                [void]$patternSummary.Append("$key=$count ")
            }
        }

        if ($totalMatches -eq 0) {
            [void]$patternSummary.Append("(none yet)")
        }

        Write-Host $patternSummary.ToString() -ForegroundColor DarkGray
    }

    Start-Sleep -Milliseconds 100
}

# Final progress update
$completed = $runspaces.Count
Write-Progress -Activity "Scanning files" -Status "Completing..." -PercentComplete 100

# Wait for all runspaces to complete and clean up
foreach ($runspace in $runspaces) {
    $null = $runspace.PowerShell.EndInvoke($runspace.AsyncResult)
    $runspace.PowerShell.Dispose()
}

$runspacePool.Close()
$runspacePool.Dispose()

Write-Progress -Activity "Scanning files" -Completed

$elapsed = (Get-Date) - $startTime
Write-Host ""
Write-Host "Scan completed in $([int]$elapsed.TotalSeconds) seconds ($threadCount threads)" -ForegroundColor Green

# Convert results to sorted format (already includes line numbers)
$sortedResults = @{}
foreach ($key in $results.Keys) {
    $sortedResults[$key] = $results[$key].ToArray() | Sort-Object { $_.File }
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
        $results['StringMatch'] | ForEach-Object {
            Write-Host "  $($_.File)" -ForegroundColor White
            if ($IncludeLineNumbers -and $_.Lines -and @($_.Lines).Count -gt 0) {
                $lineNumbers = $_.Lines -join ', '
                Write-Host "    Lines: $lineNumbers" -ForegroundColor Gray
            }
        }
    }
    else {
        Write-Host "  No matches found" -ForegroundColor Gray
    }

    # Commented out references (only shown if line numbers enabled)
    if ($IncludeLineNumbers) {
        Write-SectionHeader "COMMENTED OUT REFERENCE" 'DarkYellow'
        if ($results.ContainsKey('StringMatch_Commented') -and @($results['StringMatch_Commented']).Count -gt 0) {
            Write-Host "  String: `"$searchString`" (in comments)" -ForegroundColor DarkYellow
            $results['StringMatch_Commented'] | ForEach-Object {
                $lineNumbers = $_.Lines -join ', '
                Write-Host "    $($_.File)" -ForegroundColor White
                Write-Host "      Lines: $lineNumbers" -ForegroundColor Gray
            }
        }
        else {
            Write-Host "  None found" -ForegroundColor Gray
        }
    }
}
elseif ($mode -eq 'Name') {
    # Critical findings
    Write-SectionHeader "CRITICAL FINDINGS" 'Red'
    $criticalFound = $false

    # Check for USER pattern
    if ($results.ContainsKey('Critical_USER') -and @($results['Critical_USER']).Count -gt 0) {
        $criticalFound = $true
        $results['Critical_USER'] | ForEach-Object {
            Write-Host "    $($_.File)" -ForegroundColor White
            if ($IncludeLineNumbers -and $_.Lines -and @($_.Lines).Count -gt 0) {
                $lineNumbers = $_.Lines -join ', '
                Write-Host "      Lines: $lineNumbers" -ForegroundColor Gray
            }
        }
    }

    # Check for Full Name pattern
    if ($results.ContainsKey('Critical_FullName') -and @($results['Critical_FullName']).Count -gt 0) {
        $criticalFound = $true
        $results['Critical_FullName'] | ForEach-Object {
            Write-Host "    $($_.File)" -ForegroundColor White
            if ($IncludeLineNumbers -and $_.Lines -and @($_.Lines).Count -gt 0) {
                $lineNumbers = $_.Lines -join ', '
                Write-Host "      Lines: $lineNumbers" -ForegroundColor Gray
            }
        }
    }

    if (-not $criticalFound) {
        Write-Host "  None found" -ForegroundColor Gray
    }

    # Email findings - all in one section with color coding
    Write-SectionHeader "EMAIL FINDINGS" 'Cyan'
    if ($results.ContainsKey('Email_All') -and @($results['Email_All']).Count -gt 0) {
        $results['Email_All'] | ForEach-Object {
            $fileEntry = $_

            # Determine if file has unknown domains (for coloring)
            $hasUnknown = $false
            if ($fileEntry.Emails) {
                foreach ($emailEntry in $fileEntry.Emails) {
                    $email = $emailEntry.Email.ToLower()
                    if (-not ($email.Contains('@igsolutions') -or $email.Contains('@intelliguardhealth'))) {
                        $hasUnknown = $true
                        break
                    }
                }
            }

            # Display file in red if has unknown domains, white otherwise
            $fileColor = if ($hasUnknown) { 'Red' } else { 'White' }
            Write-Host "    $($fileEntry.File)" -ForegroundColor $fileColor

            if ($IncludeLineNumbers -and $fileEntry.Lines -and @($fileEntry.Lines).Count -gt 0) {
                $lineNumbers = $fileEntry.Lines -join ', '
                Write-Host "      Lines: $lineNumbers" -ForegroundColor Gray
            }
        }
    }
    else {
        Write-Host "  None found" -ForegroundColor Gray
    }

    # Warnings (name references)
    Write-SectionHeader "WARNINGS (Name References)" 'Yellow'
    if ($results.ContainsKey('Warning_All') -and @($results['Warning_All']).Count -gt 0) {
        $results['Warning_All'] | ForEach-Object {
            Write-Host "    $($_.File)" -ForegroundColor White
            if ($IncludeLineNumbers -and $_.Lines -and @($_.Lines).Count -gt 0) {
                $lineNumbers = $_.Lines -join ', '
                Write-Host "      Lines: $lineNumbers" -ForegroundColor Gray
            }
        }
    }
    else {
        Write-Host "  None found" -ForegroundColor Gray
    }

    # Commented out references (only shown if line numbers enabled)
    if ($IncludeLineNumbers) {
        Write-SectionHeader "COMMENTED OUT REFERENCE" 'DarkYellow'
        $commentedFound = $false
        foreach ($key in ($results.Keys | Where-Object { $_ -like '*_Commented' } | Sort-Object)) {
            if (@($results[$key]).Count -gt 0) {
                $commentedFound = $true
                $baseKey = $key -replace '_Commented$', ''
                # Safely get display name with strict mode compatibility
                $pattern = if ($searchPatterns.ContainsKey($baseKey)) { $searchPatterns[$baseKey] } else { $null }
                $displayName = if ($pattern -and $pattern.Display) {
                    $pattern.Display
                } else {
                    $baseKey
                }
                Write-Host "  Pattern: $displayName (in comments)" -ForegroundColor DarkYellow
                $results[$key] | ForEach-Object {
                    $lineNumbers = $_.Lines -join ', '
                    Write-Host "    $($_.File)" -ForegroundColor White
                    Write-Host "      Lines: $lineNumbers" -ForegroundColor Gray
                }
            }
        }
        if (-not $commentedFound) {
            Write-Host "  None found" -ForegroundColor Gray
        }
    }
}
elseif ($mode -eq 'Keys') {
    Write-SectionHeader "POTENTIAL SECRETS/KEYS" 'Red'
    if ($results.ContainsKey('Keys_Potential') -and @($results['Keys_Potential']).Count -gt 0) {
        $results['Keys_Potential'] | ForEach-Object {
            Write-Host "  $($_.File)" -ForegroundColor Yellow
            if ($IncludeLineNumbers -and $_.Lines -and @($_.Lines).Count -gt 0) {
                $lineNumbers = $_.Lines -join ', '
                Write-Host "    Lines: $lineNumbers" -ForegroundColor Gray
            }
        }
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
