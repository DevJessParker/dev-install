# PowerShell 5.1 Compatibility

## Overview

Find-EmployeeRefs.ps1 is **fully compatible with PowerShell 5.1** (Windows PowerShell).

## Requirements

- **PowerShell Version**: 5.1 or higher
- **.NET Framework**: 4.5+ (included with Windows PowerShell 5.1)
- **Operating System**: Windows 7 SP1 / Windows Server 2008 R2 SP1 or later

## Features Used

### PowerShell 5.0+ Features

The script uses the following features introduced in PowerShell 5.0:

1. **`::new()` Constructor Syntax**
   - Introduced in PowerShell 5.0
   - Used for creating .NET objects
   - Example: `[System.Collections.Generic.List[string]]::new()`

### .NET Framework Features

All .NET classes and methods used are available in .NET Framework 4.5+:

1. **Generic Collections**
   - `System.Collections.Generic.List<T>`
   - `System.Collections.Generic.Stack<T>`
   - `System.Collections.Generic.HashSet<T>`

2. **File System Operations**
   - `System.IO.Directory.GetDirectories()`
   - `System.IO.Directory.GetFiles()`
   - `System.IO.File.ReadAllText()`
   - `System.IO.FileInfo`
   - `System.IO.Path`

3. **Regular Expressions**
   - `System.Text.RegularExpressions.Regex`
   - `RegexOptions.Compiled`
   - `RegexOptions.IgnoreCase`

4. **String Comparison**
   - `System.StringComparer.OrdinalIgnoreCase`

## Compatibility Testing

Run the compatibility test script to verify your environment:

```powershell
.\scripts\Test-PS51Compatibility.ps1
```

This will test all constructs used in Find-EmployeeRefs.ps1 and report any issues.

## Known Limitations

### Not Compatible With

- **PowerShell 4.0 or earlier** - Uses `::new()` syntax from PS 5.0
- **PowerShell Core 6.x** - Not tested, but should work
- **PowerShell 7.x** - Not tested, but should work

### Platform Support

- ✅ **Windows PowerShell 5.1** (Primary target)
- ⚠️ **PowerShell Core/7** on Windows (Should work, not tested)
- ❌ **PowerShell Core/7** on Linux/macOS (Not applicable - uses Windows paths)

## Why PowerShell 5.1?

Windows PowerShell 5.1 is:
- Pre-installed on Windows 10 and Windows Server 2016+
- Widely deployed in enterprise environments
- Stable and well-supported
- Includes all required .NET Framework features

## Verified Constructs

All the following have been verified to work in PowerShell 5.1:

| Feature | Status | Notes |
|---------|--------|-------|
| `::new()` syntax | ✅ Works | PS 5.0+ |
| Generic List | ✅ Works | .NET 2.0+ |
| Generic Stack | ✅ Works | .NET 2.0+ |
| Generic HashSet | ✅ Works | .NET 3.5+ |
| Compiled Regex | ✅ Works | .NET 1.1+ |
| System.IO.Directory | ✅ Works | .NET 1.1+ |
| System.IO.File | ✅ Works | .NET 1.1+ |
| StringComparer | ✅ Works | .NET 2.0+ |
| Set-StrictMode | ✅ Works | PS 2.0+ |

## Troubleshooting

### "Method invocation failed" errors

If you see errors about `::new()`:
1. Check PowerShell version: `$PSVersionTable.PSVersion`
2. Ensure you're running PowerShell 5.0 or later
3. Update Windows PowerShell if needed

### Performance Issues

If the script runs slowly:
1. Check antivirus - real-time scanning may slow file reads
2. Verify exclusion patterns are working (check progress - should skip node_modules)
3. Consider increasing `-MaxFileSizeMB` to skip large files

## Testing Your Environment

```powershell
# Check PowerShell version
$PSVersionTable.PSVersion

# Should show 5.1 or higher

# Check .NET Framework version
[System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription

# Run compatibility tests
.\scripts\Test-PS51Compatibility.ps1
```

## Support

This script is designed for and tested with:
- Windows 10 (all versions with PowerShell 5.1)
- Windows 11
- Windows Server 2016+

For other platforms or older Windows versions, please test thoroughly before use.
