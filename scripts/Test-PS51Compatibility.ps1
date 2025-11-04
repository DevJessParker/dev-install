<#
.SYNOPSIS
    Tests PowerShell 5.1 compatibility of Find-EmployeeRefs.ps1

.DESCRIPTION
    Validates that all constructs used in the script work in PowerShell 5.1
#>

$ErrorActionPreference = 'Stop'

Write-Host "Testing PowerShell 5.1 Compatibility..." -ForegroundColor Cyan
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Gray
Write-Host ""

$tests = @()
$passed = 0
$failed = 0

# Test 1: Generic List
Write-Host "Test 1: Generic List creation..." -NoNewline
try {
    $list = [System.Collections.Generic.List[string]]::new()
    $list.Add("test")
    if ($list.Count -eq 1) {
        Write-Host " PASS" -ForegroundColor Green
        $passed++
    } else {
        Write-Host " FAIL" -ForegroundColor Red
        $failed++
    }
} catch {
    Write-Host " FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $failed++
}

# Test 2: Generic Stack
Write-Host "Test 2: Generic Stack creation..." -NoNewline
try {
    $stack = [System.Collections.Generic.Stack[string]]::new()
    $stack.Push("test")
    if ($stack.Count -eq 1) {
        Write-Host " PASS" -ForegroundColor Green
        $passed++
    } else {
        Write-Host " FAIL" -ForegroundColor Red
        $failed++
    }
} catch {
    Write-Host " FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $failed++
}

# Test 3: Generic HashSet with StringComparer
Write-Host "Test 3: Generic HashSet with StringComparer..." -NoNewline
try {
    $hashSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    [void]$hashSet.Add("TEST")
    [void]$hashSet.Add("test")  # Should not add duplicate due to case-insensitive comparer
    if ($hashSet.Count -eq 1) {
        Write-Host " PASS" -ForegroundColor Green
        $passed++
    } else {
        Write-Host " FAIL (Expected 1 item, got $($hashSet.Count))" -ForegroundColor Red
        $failed++
    }
} catch {
    Write-Host " FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $failed++
}

# Test 4: Regex compilation
Write-Host "Test 4: Compiled Regex patterns..." -NoNewline
try {
    $pattern = [regex]::new("test\s+pattern", [System.Text.RegularExpressions.RegexOptions]::Compiled -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($pattern.IsMatch("Test  Pattern")) {
        Write-Host " PASS" -ForegroundColor Green
        $passed++
    } else {
        Write-Host " FAIL" -ForegroundColor Red
        $failed++
    }
} catch {
    Write-Host " FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $failed++
}

# Test 5: System.IO.Directory methods
Write-Host "Test 5: System.IO.Directory methods..." -NoNewline
try {
    $tempDir = [System.IO.Path]::GetTempPath()
    $dirs = [System.IO.Directory]::GetDirectories($tempDir)
    $files = [System.IO.Directory]::GetFiles($tempDir)
    Write-Host " PASS" -ForegroundColor Green
    $passed++
} catch {
    Write-Host " FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $failed++
}

# Test 6: System.IO.File.ReadAllText
Write-Host "Test 6: System.IO.File.ReadAllText..." -NoNewline
try {
    $testFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "ps51test.txt")
    [System.IO.File]::WriteAllText($testFile, "Test content")
    $content = [System.IO.File]::ReadAllText($testFile)
    [System.IO.File]::Delete($testFile)
    if ($content -eq "Test content") {
        Write-Host " PASS" -ForegroundColor Green
        $passed++
    } else {
        Write-Host " FAIL" -ForegroundColor Red
        $failed++
    }
} catch {
    Write-Host " FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $failed++
}

# Test 7: FileInfo constructor
Write-Host "Test 7: System.IO.FileInfo constructor..." -NoNewline
try {
    $tempFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "ps51test2.txt")
    [System.IO.File]::WriteAllText($tempFile, "Test")
    $fileInfo = [System.IO.FileInfo]::new($tempFile)
    [System.IO.File]::Delete($tempFile)
    if ($fileInfo.Extension -eq ".txt") {
        Write-Host " PASS" -ForegroundColor Green
        $passed++
    } else {
        Write-Host " FAIL" -ForegroundColor Red
        $failed++
    }
} catch {
    Write-Host " FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $failed++
}

# Test 8: TextInfo.ToTitleCase
Write-Host "Test 8: TextInfo.ToTitleCase..." -NoNewline
try {
    $titleCase = (Get-Culture).TextInfo.ToTitleCase("john doe")
    if ($titleCase -eq "John Doe") {
        Write-Host " PASS" -ForegroundColor Green
        $passed++
    } else {
        Write-Host " FAIL (got: $titleCase)" -ForegroundColor Red
        $failed++
    }
} catch {
    Write-Host " FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $failed++
}

# Test 9: Regex.Escape
Write-Host "Test 9: Regex.Escape..." -NoNewline
try {
    $escaped = [regex]::Escape("test.value@domain.com")
    if ($escaped -eq "test\.value@domain\.com") {
        Write-Host " PASS" -ForegroundColor Green
        $passed++
    } else {
        Write-Host " FAIL" -ForegroundColor Red
        $failed++
    }
} catch {
    Write-Host " FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $failed++
}

# Test 10: -notmatch operator with regex
Write-Host "Test 10: -notmatch with regex pattern..." -NoNewline
try {
    $pattern = '\\(node_modules|\.git)(\\|$)'
    $testPath1 = "C:\project\node_modules\package"
    $testPath2 = "C:\project\src\file.js"
    if ($testPath1 -match $pattern -and $testPath2 -notmatch $pattern) {
        Write-Host " PASS" -ForegroundColor Green
        $passed++
    } else {
        Write-Host " FAIL" -ForegroundColor Red
        $failed++
    }
} catch {
    Write-Host " FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $failed++
}

Write-Host ""
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "Results: $passed passed, $failed failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
Write-Host "=" * 60 -ForegroundColor Cyan

if ($failed -eq 0) {
    Write-Host ""
    Write-Host "All compatibility tests passed! Script is compatible with PowerShell 5.1" -ForegroundColor Green
    exit 0
} else {
    Write-Host ""
    Write-Host "Some tests failed. Script may not be fully compatible." -ForegroundColor Red
    exit 1
}
