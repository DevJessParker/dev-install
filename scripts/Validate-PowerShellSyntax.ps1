#Requires -Version 5.1

<#
.SYNOPSIS
    Validates PowerShell scripts for common syntax issues
.DESCRIPTION
    Checks PowerShell scripts for patterns that cause parsing errors or violate best practices.
    This script should be run before committing code to catch issues early.
.PARAMETER Path
    Path to directory or file to validate (defaults to repository root)
.PARAMETER Fix
    Automatically fix issues where possible
.EXAMPLE
    .\Validate-PowerShellSyntax.ps1
    .\Validate-PowerShellSyntax.ps1 -Path ".\scripts"
    .\Validate-PowerShellSyntax.ps1 -Fix
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Path = $PSScriptRoot,

    [Parameter(Mandatory = $false)]
    [switch]$Fix
)

$ErrorCount = 0
$WarningCount = 0
$FixedCount = 0

function Test-VariableColonPattern {
    <#
    .SYNOPSIS
        Checks for problematic $variable: patterns in strings
    .DESCRIPTION
        Detects patterns like "$varName: text" that should be "${varName}: text"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $false)]
        [switch]$Fix
    )

    $content = Get-Content -Path $FilePath -Raw
    $lines = Get-Content -Path $FilePath

    # Pattern: $variableName: (not $scope:variableName, not ${variableName}:, not $(...):)
    # This regex looks for: $ + word chars + : + space, but NOT if preceded by { or (
    $problematicPattern = '(?<![{\$])\$([a-zA-Z_][a-zA-Z0-9_]*):(?!\s*=)'

    $issues = @()
    $lineNumber = 0

    foreach ($line in $lines) {
        $lineNumber++

        # Skip lines that are comments
        if ($line -match '^\s*#') {
            continue
        }

        # Find matches
        if ($line -match $problematicPattern) {
            # Check if it's in a string (simple heuristic - line contains quotes)
            if ($line -match '"' -or $line -match "'") {
                # Exclude valid scope modifiers
                if ($line -notmatch '\$script:' -and
                    $line -notmatch '\$env:' -and
                    $line -notmatch '\$global:' -and
                    $line -notmatch '\$local:' -and
                    $line -notmatch '\$private:' -and
                    $line -notmatch '\${[^}]+}:') {  # Already fixed with braces

                    $matches = [regex]::Matches($line, $problematicPattern)
                    foreach ($match in $matches) {
                        $varName = $match.Groups[1].Value

                        # Additional check: make sure it's not a scope modifier
                        if ($varName -notin @('script', 'env', 'global', 'local', 'private')) {
                            $issues += [PSCustomObject]@{
                                File = $FilePath
                                Line = $lineNumber
                                Column = $match.Index + 1
                                Variable = $varName
                                Issue = "Variable followed by colon needs braces: `$$varName: should be `${$varName}:"
                                Content = $line.Trim()
                            }
                        }
                    }
                }
            }
        }
    }

    if ($issues.Count -gt 0) {
        Write-Host "`n❌ ERRORS in $FilePath" -ForegroundColor Red
        foreach ($issue in $issues) {
            Write-Host "  Line $($issue.Line): $($issue.Issue)" -ForegroundColor Red
            Write-Host "    $($issue.Content)" -ForegroundColor DarkGray

            if ($Fix) {
                # Attempt to fix by replacing $varName: with ${varName}:
                $originalVar = "`$$($issue.Variable):"
                $fixedVar = "`${$($issue.Variable)}:"

                $lineContent = $lines[$issue.Line - 1]
                $fixedLine = $lineContent -replace [regex]::Escape($originalVar), $fixedVar

                if ($fixedLine -ne $lineContent) {
                    $lines[$issue.Line - 1] = $fixedLine
                    Write-Host "    ✓ Fixed: $originalVar → $fixedVar" -ForegroundColor Green
                    $script:FixedCount++
                }
            }
        }

        if ($Fix) {
            # Write fixed content back to file
            Set-Content -Path $FilePath -Value $lines -Encoding UTF8
            Write-Host "  ✓ File updated with fixes" -ForegroundColor Green
        }

        return $issues.Count
    }

    return 0
}

function Test-PowerShellSyntax {
    <#
    .SYNOPSIS
        Validates PowerShell syntax using the parser
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    try {
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Path $FilePath -Raw), [ref]$null)
        return 0
    }
    catch {
        Write-Host "`n❌ SYNTAX ERROR in $FilePath" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Main validation logic
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "PowerShell Syntax Validation" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Scanning: $Path"
if ($Fix) {
    Write-Host "Mode: FIX (will attempt to auto-fix issues)" -ForegroundColor Yellow
}
Write-Host ""

# Get all PowerShell files
$searchPath = if (Test-Path $Path -PathType Container) { $Path } else { Split-Path $Path -Parent }
$files = Get-ChildItem -Path $searchPath -Recurse -Include "*.ps1", "*.psm1" -File

Write-Host "Found $($files.Count) PowerShell files to validate`n"

foreach ($file in $files) {
    Write-Host "Checking: $($file.Name)" -ForegroundColor Cyan

    # Check 1: Variable colon pattern
    $varColonErrors = Test-VariableColonPattern -FilePath $file.FullName -Fix:$Fix
    $script:ErrorCount += $varColonErrors

    # Check 2: PowerShell syntax validation
    $syntaxErrors = Test-PowerShellSyntax -FilePath $file.FullName
    $script:ErrorCount += $syntaxErrors

    if ($varColonErrors -eq 0 -and $syntaxErrors -eq 0) {
        Write-Host "  ✓ No issues found" -ForegroundColor Green
    }
}

# Summary
Write-Host "`n=====================================" -ForegroundColor Cyan
Write-Host "Validation Summary" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Files checked: $($files.Count)"
Write-Host "Errors found: $ErrorCount" -ForegroundColor $(if ($ErrorCount -gt 0) { "Red" } else { "Green" })
Write-Host "Warnings: $WarningCount" -ForegroundColor $(if ($WarningCount -gt 0) { "Yellow" } else { "Green" })

if ($Fix) {
    Write-Host "Issues fixed: $FixedCount" -ForegroundColor $(if ($FixedCount -gt 0) { "Green" } else { "Gray" })
}

Write-Host ""

if ($ErrorCount -gt 0) {
    if (-not $Fix) {
        Write-Host "💡 Tip: Run with -Fix parameter to automatically fix some issues" -ForegroundColor Yellow
    }
    Write-Host "❌ Validation FAILED - Please fix errors before committing" -ForegroundColor Red
    exit 1
}
else {
    Write-Host "✓ Validation PASSED" -ForegroundColor Green
    exit 0
}
