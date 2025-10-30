<#
Find-EmployeeRefs.ps1  (Windows PowerShell 5.1)
Includes progress bars and large-repo optimizations.
#>

[CmdletBinding()]
param(
  [string]$RootPath,
  [int]$MaxFileSizeMB = 5,
  [string]$Extensions
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-GroupHeader([string]$title, [string]$color) {
  Write-Host ""
  Write-Host $title -ForegroundColor $color
}
function Print-PathsFromMatches([System.Object[]]$matches) {
  if ($matches -and @($matches).Count -gt 0) {
    $paths = $matches | Select-Object -ExpandProperty Path -Unique | Sort-Object
    foreach ($p in $paths) { Write-Host ("  - " + $p) }
  }
}
function To-Proper([string]$s) {
  if ([string]::IsNullOrEmpty($s)) { return $s }
  if ($s.Length -eq 1) { return $s.ToUpper() }
  $s.Substring(0,1).ToUpper() + $s.Substring(1)
}
function Find-Literal([string]$text, [switch]$CaseSensitive, [string[]]$Paths) {
  if ([string]::IsNullOrEmpty($text) -or -not $Paths -or @($Paths).Count -eq 0) { return @() }
  if ($CaseSensitive) {
    Select-String -Path $Paths -SimpleMatch $text -CaseSensitive -AllMatches:$false -List -ErrorAction SilentlyContinue
  } else {
    Select-String -Path $Paths -SimpleMatch $text -AllMatches:$false -List -ErrorAction SilentlyContinue
  }
}
function Find-Regex([string]$pattern, [switch]$CaseSensitive, [string[]]$Paths) {
  if ([string]::IsNullOrEmpty($pattern) -or -not $Paths -or @($Paths).Count -eq 0) { return @() }
  if ($CaseSensitive) {
    Select-String -Path $Paths -Pattern $pattern -CaseSensitive -AllMatches:$false -List -ErrorAction SilentlyContinue
  } else {
    Select-String -Path $Paths -Pattern $pattern -AllMatches:$false -List -ErrorAction SilentlyContinue
  }
}

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    Write-Host "No RootPath provided. Searching for 'igsolutions_repo'..." -ForegroundColor Cyan

    $searchRoots = @()
    try { $searchRoots += [Environment]::GetFolderPath("UserProfile") } catch {}
    if (-not $searchRoots -or -not (Test-Path $searchRoots[0])) { $searchRoots = @("C:\Users") }

    $possibleRoots = @()
    foreach ($root in $searchRoots) {
        $possibleRoots += Join-Path $root "igsolutions_repo"
        $possibleRoots += Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
                          ForEach-Object { Join-Path $_.FullName "igsolutions_repo" }
    }

    $RootPath = $possibleRoots | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($RootPath) {
        Write-Host "Found repository path: $RootPath" -ForegroundColor Green
    } else {
        Write-Host "Could not automatically locate 'igsolutions_repo'." -ForegroundColor Yellow
        $RootPath = Read-Host "Enter the ROOT PATH manually (e.g., C:\Users\<username>\igsolutions_repo)"
    }
}

if (-not (Test-Path $RootPath)) {
    Write-Host "Invalid RootPath. Path not found: $RootPath" -ForegroundColor Red
    exit 1
}

$mode = $null
while (-not $mode) {
  Write-Host ""
  Write-Host "Select search mode:" -ForegroundColor Cyan
  Write-Host "  [1] Name (First + Last)  -> grouped checks (Critical/Unknown Email/etc.)"
  Write-Host "  [2] Single String        -> case-insensitive literal search only"
  Write-Host "  [3] Secrets/Keys         -> heuristics for key material (+ optional exact string)"
  Write-Host "  [Q] Quit"
  $choice = Read-Host "Enter 1, 2, 3, or Q"

  switch ($choice.Trim().ToUpper()) {
    '1' { $mode = 'Name' }
    '2' { $mode = 'String' }
    '3' { $mode = 'Keys' }
    'Q' { Write-Host "Exiting."; exit 0 }
    default { Write-Host "Invalid choice. Please enter 1, 2, 3, or Q." -ForegroundColor Yellow }
  }
}

# Collect user inputs BEFORE scanning files
$firstInput = $null; $lastInput = $null; $alt = $null

if ($mode -eq 'Name') {
  $firstInput = Read-Host "Which FIRST name would you like to search for?"
  $lastInput  = Read-Host "Which LAST name would you like to search for?"
  if ([string]::IsNullOrWhiteSpace($firstInput) -or [string]::IsNullOrWhiteSpace($lastInput)) {
    Write-Host "Both first and last names are required for Name mode." -ForegroundColor Red
    exit 1
  }
} elseif ($mode -eq 'String') {
  $alt = Read-Host "Enter a SINGLE string to search (case-insensitive)"
  if ([string]::IsNullOrWhiteSpace($alt)) {
    Write-Host "A non-empty string is required for String mode." -ForegroundColor Red
    exit 1
  }
} else {
  $alt = Read-Host "Optionally enter an exact key/token string to include (press Enter to skip)"
}

# NOW enumerate files after we have user input
Write-Host ""
Write-Host "Preparing to scan files..." -ForegroundColor Cyan

$maxBytes = [Math]::Max(0, $MaxFileSizeMB) * 1MB

if ([string]::IsNullOrWhiteSpace($Extensions)) {
  $Extensions = '.ps1,.psm1,.psd1,.cs,.csproj,.vb,.sln,.ts,.tsx,.js,.jsx,.json,.html,.htm,.css,.scss,.md,.txt,.yml,.yaml,.xml,.config,.xaml,.sql,.sh,.bat,.cmd,.ini,.vue,.rs,.go,.py,.rb,.java,.kt'
}
$extArray = $Extensions.Split(',', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() }
$extHash = @{}; foreach ($e in $extArray) { $extHash[$e.ToLower()] = $true }

# Build comprehensive skip pattern for performance
# Note: Files are filtered after enumeration, but this prevents processing
# files from package/build directories
$skipDirsPattern = '\\(' + (
  @(
    # Package managers and dependencies
    'node_modules','bower_components','jspm_packages','web_modules',
    'vendor','vendors','third_party','3rdparty','packages',
    'site-packages','dist-packages','__pypackages__',
    'lib','libs','deps','dependencies',

    # Version control
    '\.git','\.github','\.gitlab','\.svn','\.hg','\.bzr',

    # IDE and editors
    '\.idea','\.vscode','\.vs','\.settings','\.eclipse',
    '\.metadata','\.project','\.classpath',

    # Build outputs
    'bin','obj','dist','build','builds','out','output','target',
    'release','debug','\.build','_build',

    # Framework specific
    '\.next','\.nuxt','\.angular','\.svelte-kit','\.docusaurus',
    '\.cache','\.parcel-cache','\.webpack','\.rollup\.cache',
    '\.turbo','\.vercel','\.netlify',

    # Python
    '\.venv','venv','\.tox','\.pytest_cache','__pycache__','\.mypy_cache',
    '\.eggs','\.egg-info','\.Python',

    # Infrastructure as Code
    '\.terraform','\.terragrunt-cache','\.pulumi',

    # Logs and temp
    'logs','log','tmp','temp','temps','\.tmp','\.temp',
    'coverage','\.coverage','\.nyc_output',

    # OS specific
    '\$RECYCLE\.BIN','System Volume Information','\.Trash',
    '\.DS_Store','\.localized'
  ) -join '|'
) + ')(\\|$)'

# Custom recursive file enumeration that SKIPS excluded directories
# This is MUCH faster than Get-ChildItem -Recurse because we never enter
# directories like node_modules, .git, etc.
function Get-FilteredFilesRecursive {
  param(
    [string]$Path,
    [hashtable]$ExtHash,
    [long]$MaxBytes,
    [string]$SkipPattern
  )

  $files = @()
  $script:fileCount = 0

  function Traverse-Directory {
    param([string]$dir)

    try {
      # Get directories first and filter them BEFORE recursing
      $dirs = Get-ChildItem -Path $dir -Directory -Force -ErrorAction SilentlyContinue
      foreach ($d in $dirs) {
        # Skip if directory matches exclusion pattern
        if ($d.FullName -match $SkipPattern) {
          continue
        }
        # Recurse into this directory
        Traverse-Directory $d.FullName
      }

      # Now get files in current directory
      $currentFiles = Get-ChildItem -Path $dir -File -Force -ErrorAction SilentlyContinue
      foreach ($f in $currentFiles) {
        $script:fileCount++
        if ($script:fileCount % 1000 -eq 0) {
          Write-Progress -Activity "Enumerating files" -Status "Found $script:fileCount files..." -PercentComplete -1
        }

        # Skip files that are too large
        if ($f.Length -gt $MaxBytes) { continue }

        # Skip files without matching extensions
        $ext = [System.IO.Path]::GetExtension($f.Name)
        if ([string]::IsNullOrEmpty($ext)) { continue }
        if (-not $ExtHash.ContainsKey($ext.ToLower())) { continue }

        $files += $f.FullName
      }
    }
    catch {
      # Silently skip directories we can't access
    }
  }

  Traverse-Directory $Path
  Write-Progress -Activity "Enumerating files" -Completed
  return $files
}

Write-Progress -Activity "Enumerating files" -Status "Starting scan..." -PercentComplete 0
$allFiles = Get-FilteredFilesRecursive -Path $RootPath -ExtHash $extHash -MaxBytes $maxBytes -SkipPattern $skipDirsPattern

if (-not $allFiles -or @($allFiles).Count -eq 0) {
  Write-Host "No candidate files found to scan under $RootPath (after exclusions, size limit, and extension filter)." -ForegroundColor Yellow
  exit 0
}

Write-Host "Found $(@($allFiles).Count) files to scan" -ForegroundColor Green

function Invoke-ChunkedSearch([scriptblock]$SearchBlock, [string[]]$Files, [string]$label) {
  $batch = 500
  $total = @($Files).Count
  $results = @()
  for ($i = 0; $i -lt $total; $i += $batch) {
    $end = [Math]::Min($i + $batch, $total)
    $slice = $Files[$i..($end-1)]
    $pct = [int]([double]$end / [Math]::Max(1,$total) * 100)
    Write-Progress -Activity $label -Status "Files $end of $total" -PercentComplete $pct
    $r = & $SearchBlock $slice
    if ($r) { $results += $r }
  }
  Write-Progress -Activity $label -Completed
  return $results
}

if ($mode -eq 'String') {
  Write-GroupHeader ("Case-insensitive search for: `"$alt`"") 'Yellow'
  $block = { param($paths) Select-String -Path $paths -SimpleMatch $alt -AllMatches:$false -List -ErrorAction SilentlyContinue }
  $matches = Invoke-ChunkedSearch $block $allFiles 'Scanning (String)'
  if ($matches) {
    $byPath = $matches | Group-Object Path
    foreach ($g in $byPath) { Write-Host ("- " + $g.Name) }
  } else {
    Write-Host "- No matches found."
  }
  Write-Host ""; Write-Host "Search complete." -ForegroundColor Gray
  exit 0
}

if ($mode -eq 'Keys') {
  $regexes = @()
  if (-not [string]::IsNullOrWhiteSpace($alt)) {
    $regexes += [regex]::Escape($alt)
  }
  $regexes += '(?<![A-Z0-9])(AKIA|ASIA)[A-Z0-9]{16}(?![A-Z0-9])'
  $regexes += '(?<![A-Za-z0-9/+=])[A-Za-z0-9/+=]{40}(?![A-Za-z0-9/+=])'
  $regexes += 'eyJ[A-Za-z0-9_-]+?\.[A-Za-z0-9_-]+?\.[A-Za-z0-9_-]+'
  $regexes += '(?i)(access[-_ ]?key|secret[-_ ]?key|api[-_ ]?key|token)\s*[:=]\s*["\' + "'" + ']?[A-Za-z0-9/\+\-_=]{10,}["\' + "'" + ']?'

  $aggregate = @()
  foreach ($re in $regexes) {
    $block = { param($paths) Select-String -Path $paths -Pattern $re -AllMatches:$false -List -ErrorAction SilentlyContinue }
    $r = Invoke-ChunkedSearch $block $allFiles ("Scanning (Keys): $re")
    if ($r) { $aggregate += $r }
  }

  Write-GroupHeader "Possible Secrets/Keys" 'Red'
  if ($aggregate) {
    $paths = $aggregate | Select-Object -ExpandProperty Path -Unique | Sort-Object
    foreach ($p in $paths) { Write-Host ("  - " + $p) }
  } else {
    Write-Host "- No likely secrets found (based on heuristics)."
  }
  Write-Host ""; Write-Host "Scan complete." -ForegroundColor Gray
  exit 0
}

$firstLower = $firstInput.Trim().ToLower()
$lastLower  = $lastInput.Trim().ToLower()
$firstProper = To-Proper $firstLower
$lastProper  = To-Proper  $lastLower
$usernameLower = ($firstLower.Substring(0,1) + $lastLower)
$usernameUpper = $usernameLower.ToUpper()

$phraseUser   = "USER $usernameUpper"
$phraseProper = "$firstProper $lastProper"
$phraseLower  = "$firstLower $lastLower"

$patternIG_lc = [regex]::Escape("$usernameLower@igsolutions.com")
$patternIG_uc = [regex]::Escape("$usernameUpper@igsolutions.com")
$patternIH_lc = [regex]::Escape("$usernameLower@intelliguardhealth.com")
$patternIH_uc = [regex]::Escape("$usernameUpper@intelliguardhealth.com")

$re_unknown_email = '\b' + [regex]::Escape($usernameLower) + '@(?!' +
                    '(?:intelliguardhealth\.com|igsolutions\.com)\b)' +
                    '[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'

$re_FirstProper_spaced = '(?<=\s)' + [regex]::Escape($firstProper) + '(?=\s)'
$re_FirstLower_spaced  = '(?<=\s)' + [regex]::Escape($firstLower)  + '(?=\s)'
$re_LastProper_spaced  = '(?<=\s)' + [regex]::Escape($lastProper)  + '(?=\s)'
$re_LastLower_spaced   = '(?<=\s)' + [regex]::Escape($lastLower)   + '(?=\s)'
$re_user_not_at = '\b' + [regex]::Escape($usernameLower) + '(?!@)\b'

$crit_USER   = Invoke-ChunkedSearch { param($p) Select-String -Path $p -SimpleMatch $phraseUser -CaseSensitive -AllMatches:$false -List -ErrorAction SilentlyContinue } $allFiles 'Scanning (Critical: USER UPPER)'
$crit_Proper = Invoke-ChunkedSearch { param($p) Select-String -Path $p -SimpleMatch $phraseProper -CaseSensitive -AllMatches:$false -List -ErrorAction SilentlyContinue } $allFiles 'Scanning (Critical: Proper)'
$crit_Lower  = Invoke-ChunkedSearch { param($p) Select-String -Path $p -SimpleMatch $phraseLower -CaseSensitive -AllMatches:$false -List -ErrorAction SilentlyContinue } $allFiles 'Scanning (Critical: lower)'

$ig_refs  = Invoke-ChunkedSearch { param($p) Select-String -Path $p -Pattern $patternIG_lc -CaseSensitive -AllMatches:$false -List -ErrorAction SilentlyContinue } $allFiles 'Scanning (IG email lc)'
$ig_refs2 = Invoke-ChunkedSearch { param($p) Select-String -Path $p -Pattern $patternIG_uc -CaseSensitive -AllMatches:$false -List -ErrorAction SilentlyContinue } $allFiles 'Scanning (IG email UC)'
$ih_refs  = Invoke-ChunkedSearch { param($p) Select-String -Path $p -Pattern $patternIH_lc -CaseSensitive -AllMatches:$false -List -ErrorAction SilentlyContinue } $allFiles 'Scanning (IH email lc)'
$ih_refs2 = Invoke-ChunkedSearch { param($p) Select-String -Path $p -Pattern $patternIH_uc -CaseSensitive -AllMatches:$false -List -ErrorAction SilentlyContinue } $allFiles 'Scanning (IH email UC)'

$unknownEmailMatches = Invoke-ChunkedSearch { param($p) Select-String -Path $p -Pattern $re_unknown_email -AllMatches:$false -List -ErrorAction SilentlyContinue } $allFiles 'Scanning (Unknown email)'

$w_FirstProper = Invoke-ChunkedSearch { param($p) Select-String -Path $p -Pattern $re_FirstProper_spaced -CaseSensitive -AllMatches:$false -List -ErrorAction SilentlyContinue } $allFiles 'Scanning (Warn First Proper)'
$w_FirstLower  = Invoke-ChunkedSearch { param($p) Select-String -Path $p -Pattern $re_FirstLower_spaced -CaseSensitive -AllMatches:$false -List -ErrorAction SilentlyContinue } $allFiles 'Scanning (Warn First lower)'
$w_LastProper  = Invoke-ChunkedSearch { param($p) Select-String -Path $p -Pattern $re_LastProper_spaced -CaseSensitive -AllMatches:$false -List -ErrorAction SilentlyContinue } $allFiles 'Scanning (Warn Last Proper)'
$w_LastLower   = Invoke-ChunkedSearch { param($p) Select-String -Path $p -Pattern $re_LastLower_spaced -CaseSensitive -AllMatches:$false -List -ErrorAction SilentlyContinue } $allFiles 'Scanning (Warn Last lower)'
$w_user        = Invoke-ChunkedSearch { param($p) Select-String -Path $p -Pattern $re_user_not_at -CaseSensitive -AllMatches:$false -List -ErrorAction SilentlyContinue } $allFiles 'Scanning (Warn user not @)'

Write-GroupHeader "Critical Access" 'Red'
if ($crit_USER)   { Write-Host ('- Instances of "' + $phraseUser   + '"'); Print-PathsFromMatches $crit_USER }
if ($crit_Proper) { Write-Host ('- Instances of "' + $phraseProper + '"'); Print-PathsFromMatches $crit_Proper }
if ($crit_Lower)  { Write-Host ('- Instances of "' + $phraseLower  + '"'); Print-PathsFromMatches $crit_Lower }

Write-GroupHeader "Unknown Email" 'Red'
if ($unknownEmailMatches -and @($unknownEmailMatches).Count -gt 0) {
  $byPath = $unknownEmailMatches | Group-Object Path
  foreach ($g in $byPath) { Write-Host ("- " + $g.Name) }
}

Write-GroupHeader "IG Solutions Reference" 'Blue'
$igCombined = @()
if ($ig_refs)  { $igCombined += $ig_refs }
if ($ig_refs2) { $igCombined += $ig_refs2 }
if (@($igCombined).Count -gt 0) {
  Write-Host ('- Instances of "' + $usernameLower + '@igsolutions.com"')
  Print-PathsFromMatches $igCombined
}

Write-GroupHeader "Intelliguard Reference" 'Blue'
$ihCombined = @()
if ($ih_refs)  { $ihCombined += $ih_refs }
if ($ih_refs2) { $ihCombined += $ih_refs2 }
if (@($ihCombined).Count -gt 0) {
  Write-Host ('- Instances of "' + $usernameLower + '@intelliguardhealth.com"')
  Print-PathsFromMatches $ihCombined
}

Write-GroupHeader "Warning" 'Yellow'
if ($w_FirstProper) { Write-Host ('- Instances of "' + $firstProper + '" (capitalized), preceded by a space and followed by a space.'); Print-PathsFromMatches $w_FirstProper }
if ($w_FirstLower)  { Write-Host ('- Instances of "' + $firstLower  + '" (lowercase), preceded by a space and followed by a space.');  Print-PathsFromMatches $w_FirstLower  }
if ($w_LastProper)  { Write-Host ('- Instances of "' + $lastProper  + '", preceded by a space and followed by a space.');               Print-PathsFromMatches $w_LastProper  }
if ($w_LastLower)   { Write-Host ('- Instances of "' + $lastLower   + '", preceded by a space and followed by a space.');               Print-PathsFromMatches $w_LastLower   }
if ($w_user)        { Write-Host ('- Instances of "' + $usernameLower + '" that are NOT followed by an "@".');                          Print-PathsFromMatches $w_user        }

Write-Host ""
Write-Host ("Search complete for: {0} {1}  (username: {2})" -f $firstProper, $lastProper, $usernameLower) -ForegroundColor Gray
