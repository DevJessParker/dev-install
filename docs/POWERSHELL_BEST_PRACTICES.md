# PowerShell Best Practices

This document outlines PowerShell coding standards and best practices for this project to prevent common errors and maintain code quality.

## String Interpolation

### Variable Delimiting with Colons

**Problem:** PowerShell interprets colons after variable names as scope modifiers (`$global:`, `$script:`, `$env:`), which causes parsing errors when the colon is meant to be a literal character.

**❌ WRONG:**
```powershell
Write-Host "Wave $waveNumber: Processing tools"
# ERROR: ':' was not followed by a valid variable name character
```

**✅ CORRECT:**
```powershell
Write-Host "Wave ${waveNumber}: Processing tools"
# Use ${} to explicitly delimit the variable name
```

### When to Use ${} Syntax

Use `${variableName}` syntax when:
1. **Variable is followed by a colon**: `"Status ${status}: Complete"`
2. **Variable is followed by punctuation that could be confused**: `"File${count}.txt"`
3. **Variable name contains special characters**: `${my-variable}` (though avoid hyphens in names)
4. **Clarity is needed**: When variable boundaries aren't obvious

### When ${} is NOT Needed

Standard `$variable` syntax is fine for:
- **Scope modifiers** (these ARE colon syntax): `$script:count`, `$env:PATH`
- **Subexpressions**: `"Result: $($obj.Property):"` - colon after `)` is fine
- **Variable at end of string**: `"Count: $count"`
- **Variable followed by space**: `"Value $count is high"`
- **Variable followed by comma**: `"Items: $item1, $item2"`

## String Interpolation Examples

```powershell
# ✅ GOOD - Scope modifiers
$script:installedTools = @()
$env:PATH = "C:\tools"

# ✅ GOOD - Subexpressions with colons
Write-Host "Tool: $($tool.Name): $($tool.Version)"

# ✅ GOOD - Colon before variable
Write-Host "ERROR: $Message"
Write-Host "Status: $status"

# ✅ GOOD - Variable at end or with space
Write-Host "Installing tool $toolName now"
Write-Host "Count: $count"

# ❌ BAD - Variable followed by colon
Write-Host "Wave $waveNumber: Complete"  # PARSE ERROR

# ✅ GOOD - Use braces
Write-Host "Wave ${waveNumber}: Complete"

# ❌ BAD - Variable followed by punctuation
Write-Host "File$count.txt"  # May cause issues

# ✅ GOOD - Use braces for clarity
Write-Host "File${count}.txt"
```

## Additional Best Practices

### 1. Consistent Quoting

- Use **double quotes** `"..."` for strings with variables: `"Installing $tool"`
- Use **single quotes** `'...'` for literal strings: `'No variables here'`
- Use **here-strings** for multi-line text with quotes:
  ```powershell
  $message = @"
  Multi-line
  message with "quotes"
  "@
  ```

### 2. Array and Hashtable Syntax

```powershell
# ✅ GOOD - Empty arrays
$tools = @()

# ✅ GOOD - Single-item array
$tools = @("git")
# or
$tools = ,"git"

# ✅ GOOD - Hashtables
$config = @{
    Name = "Tool"
    Version = "1.0"
}
```

### 3. PowerShell 5.1 Compatibility

This project targets PowerShell 5.1+. Avoid newer syntax:

```powershell
# ❌ BAD - PS 7+ only
$result = $null ?? "default"
$cmd1 && $cmd2
$value = $condition ? $true : $false

# ✅ GOOD - PS 5.1 compatible
$result = if ($null -eq $value) { "default" } else { $value }
if ($LASTEXITCODE -eq 0) { $cmd2 }
$value = if ($condition) { $true } else { $false }
```

**PowerShell 6+ Cmdlets to Avoid:**

```powershell
# ❌ BAD - Join-String (PS 6+ only)
$items | Join-String -Separator ', '

# ✅ GOOD - Use -join operator
($items) -join ', '
$items -join ', '

# ❌ BAD - ForEach-Object with Join-String
$jobs | ForEach-Object { $_.Name } | Join-String -Separator '; '

# ✅ GOOD - Wrap in parentheses for -join
($jobs | ForEach-Object { $_.Name }) -join '; '
```

### 4. Cmdlet Parameter Splat

```powershell
# ✅ GOOD - Splatting for readability
$params = @{
    Path = "C:\file.txt"
    Force = $true
    Encoding = "UTF8"
}
Set-Content @params

# ✅ GOOD - Pipeline parameters
Get-ChildItem -Path "*.ps1" |
    Where-Object { $_.Length -gt 1KB } |
    ForEach-Object { Process-File $_ }
```

### 5. Error Handling

```powershell
# ✅ GOOD - Try/catch for terminating errors
try {
    $content = Get-Content -Path $file -ErrorAction Stop
}
catch {
    Write-Error "Failed to read file: $_"
}

# ✅ GOOD - Check $LASTEXITCODE for external commands
choco install git -y
if ($LASTEXITCODE -ne 0) {
    Write-Error "Installation failed with exit code: $LASTEXITCODE"
}
```

### 6. Function Documentation

```powershell
function Install-Tool {
    <#
    .SYNOPSIS
        Installs a development tool
    .DESCRIPTION
        Detailed description of what the function does
    .PARAMETER ToolName
        Name of the tool to install
    .PARAMETER Version
        Version to install (optional)
    .EXAMPLE
        Install-Tool -ToolName "git" -Version "2.40.0"
    .OUTPUTS
        Boolean indicating success
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolName,

        [Parameter(Mandatory = $false)]
        [string]$Version
    )

    # Function implementation
}
```

### 7. Script and Module Variables

```powershell
# ✅ GOOD - Use script scope for shared state
$script:installedTools = @()

# ✅ GOOD - Use proper scoping
function Add-Tool {
    param($Tool)
    $script:installedTools += $Tool  # Modifies script-level variable
}
```

### 8. Path Resolution in Background Jobs

**Problem:** When scripts are dot-sourced or run in background jobs (Start-Job), `$PSScriptRoot` gets re-evaluated in the new context, breaking relative paths.

```powershell
# ❌ BAD - Relative path breaks in jobs
param(
    [string]$ConfigPath = "$PSScriptRoot\..\config\file.json"
)
# If this script is dot-sourced in a job, $PSScriptRoot changes!

# ✅ GOOD - Resolve to absolute path immediately
param(
    [string]$ConfigPath = "$PSScriptRoot\..\config\file.json"
)

# Resolve to absolute path right after parameter block
if (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
    $ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath $ConfigPath |
        Resolve-Path -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Path
    if (-not $ConfigPath) {
        # Fallback if file doesn't exist yet
        $ConfigPath = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath "..\config\file.json"))
    }
}

# Now $ConfigPath is absolute and safe to pass to jobs
```

**Why this matters:**
- Background jobs (Start-Job) run in isolated contexts
- Dot-sourcing scripts re-evaluates parameter defaults
- Relative paths become invalid when $PSScriptRoot changes
- Always resolve paths to absolute before passing to jobs

## Common Pitfalls to Avoid

1. **Unquoted variable with colon**: `$var:text` → Use `${var}:text`
2. **Empty arrays without @()**: `$arr = ()` → Use `$arr = @()`
3. **Single-item array confusion**: `$arr = "item"` is a string, not array → Use `$arr = @("item")`
4. **Forgetting -ErrorAction Stop**: Try/catch won't work without it
5. **Not checking $LASTEXITCODE**: External commands don't throw exceptions
6. **Using PS 7+ syntax**: Check compatibility with PS 5.1
7. **Relative paths in background jobs**: Resolve to absolute paths before passing to Start-Job

## Validation Checklist

Before committing code, verify:

- [ ] All variables followed by colons use `${variable}:` syntax
- [ ] All functions have comment-based help
- [ ] All external commands check `$LASTEXITCODE`
- [ ] Code is compatible with PowerShell 5.1
- [ ] Error handling uses appropriate `-ErrorAction`
- [ ] Arrays use `@()` syntax consistently
- [ ] Scope modifiers (`$script:`, `$env:`) are used correctly

## References

- [PowerShell Best Practices and Style Guide](https://poshcode.gitbook.io/powershell-practice-and-style/)
- [PowerShell Scripting Style Guide](https://github.com/PoshCode/PowerShellPracticeAndStyle)
- [About Scopes](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_scopes)
- [About Quoting Rules](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_quoting_rules)
