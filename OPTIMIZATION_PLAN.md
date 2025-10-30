# Performance Optimization & Feature Addition Plan

## Current Performance Issue
- **Previous version**: 78 seconds
- **Current version**: 122 seconds (57% slower)
- **Target**: 50-60 seconds (35% faster than original)

## Root Cause of Slowdown
The line number tracking added in the latest version is inefficient:
1. `ReadAllLines()` creates entire array in memory
2. Character position → line number conversion counts newlines repeatedly
3. More complex object storage and sorting

## Optimization Strategy

### 1. Faster Line Number Tracking
**Current (slow):**
```powershell
$lines = [System.IO.File]::ReadAllLines($File)  # Creates array
$content = $lines -join "`n"  # Recreates string
# Later: count newlines up to each match position
$lineNumber = ($textUpToMatch.ToCharArray() | Where-Object { $_ -eq "`n" }).Count + 1
```

**Optimized (fast):**
```powershell
# Build line start position map once
$content = [System.IO.File]::ReadAllText($File)
$lineStarts = @(0)
for ($i = 0; $i < $content.Length; $i++) {
    if ($content[$i] -eq "`n") { $lineStarts += $i + 1 }
}

# Binary search for line number (O(log n) instead of O(n))
function Get-LineNumber($charPos, $lineStarts) {
    for ($i = $lineStarts.Count - 1; $i -ge 0; $i--) {
        if ($charPos >= $lineStarts[$i]) { return $i + 1 }
    }
    return 1
}
```

**Expected Improvement**: 30-40% faster

### 2. Comment Detection

Need to detect if matches are in commented code and separate them.

**Comment Patterns to Detect:**
- Single-line: `//`, `#`, `--`, `REM` (PowerShell, Python, SQL, Batch)
- Multi-line: `/* */`, `<# #>` (C-style, PowerShell)

**Implementation:**
```powershell
function Is-InComment($lineText) {
    $trimmed = $lineText.TrimStart()
    # Single-line comments
    if ($trimmed -match '^(//|#|--|REM\s)') { return $true }
    # Could be in multi-line comment (track state)
    return $false
}
```

**Output Change:**
- Add new section: "COMMENTED OUT REFERENCE"
- Show files where matches only exist in comments
- Still show line numbers

### 3. Email Pattern Updates

**Current:**
```powershell
$patternIG = "jwebber@igsolutions.com"  # Requires exact .com
$patternIH = "jwebber@intelliguardhealth.com"  # Requires exact .com
```

**New:**
```powershell
$patternIG = "jwebber@igsolutions"  # Matches @igsolutions.*, @igsolutions
$patternIH = "jwebber@intelliguardhealth"  # Matches @intelliguardhealth.*
```

**Pattern:**
```powershell
# IG Solutions - matches @igsolutions with or without TLD
'\b' + [regex]::Escape($username) + '@igsolutions(?:\.[a-z]{2,})?'

# Intelliguard Health - matches @intelliguardhealth with or without TLD
'\b' + [regex]::Escape($username) + '@intelliguardhealth(?:\.[a-z]{2,})?'
```

### 4. Output Reordering

**Current Order:**
1. Critical Findings
2. IG Solutions Email
3. Intelliguard Health Email
4. Unknown Email Domains
5. Warnings

**New Order:**
1. Critical Findings
2. **Unknown Email Domains** (moved up)
3. IG Solutions Email
4. Intelliguard Health Email
5. Warnings
6. **Commented Out Reference** (new section)

### 5. File Search Mode

**New Mode #4: File Search**

**User Options:**
1. Exact filename with extension (e.g., "config.json")
2. Partial filename, case-insensitive (e.g., "config" matches config.json, app.config.ts)
3. Exact name, all extensions (e.g., "config" matches config.json, config.xml, config.yaml)

**Implementation:**
```powershell
elseif ($mode -eq 'File') {
    Write-Host "File search options:"
    Write-Host "  [1] Exact filename (e.g., 'config.json')"
    Write-Host "  [2] Partial filename (e.g., 'config')"
    Write-Host "  [3] Exact name, any extension (e.g., 'config' → config.*)"

    $fileSearchMode = Read-Host "Choose option [1, 2, 3]"
    $fileName = Read-Host "Enter filename to search"

    # Use parallel processing to search file names only (no content scanning)
    # This should be VERY fast (< 5 seconds for 30k files)
}
```

**Output:**
```
FILE SEARCH RESULTS

Query: "config" (Partial match)
Found 23 files:

  C:\repo\src\app.config.ts
  C:\repo\config\database.config.json
  C:\repo\terraform\backend.config.tf
  ...
```

## Implementation Checklist

- [ ] Optimize line number tracking (use line start positions + binary search)
- [ ] Add comment detection logic
- [ ] Update email patterns (remove .com requirement)
- [ ] Reorder output sections
- [ ] Add File search mode (option 4)
- [ ] Add COMMENTED OUT REFERENCE section
- [ ] Performance test (target: < 60 seconds)
- [ ] Update documentation

## Expected Performance After All Changes

| Operation | Time |
|-----------|------|
| File enumeration | 3-5 sec |
| Parallel scanning (optimized) | 40-50 sec |
| Result sorting/display | 2-3 sec |
| **Total** | **45-58 sec** |

**Improvement**: 35-42% faster than current (122 sec), 28-40% faster than original (78 sec)

## File Search Performance

File search should be extremely fast since we're only searching filenames, not content:
- **File enumeration**: Same as above (3-5 sec)
- **Filename matching**: < 1 sec (in-memory string comparison)
- **Total**: 4-6 seconds for entire repo

## Notes

1. The line start position map approach is used by professional editors (VS Code, Sublime)
2. Comment detection can be improved incrementally (start with single-line)
3. File search mode needs no content scanning (just filename matching)
4. All changes maintain PowerShell 5.1 compatibility
