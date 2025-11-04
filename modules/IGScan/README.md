# IGScan Module

Employee reference scanner for finding employee names, emails, and potential secrets in codebases.

## Installation

### Option 1: Automated Installation (Recommended)

Run the installation script from the repository root. This will automatically remove any existing version and install the latest:

```powershell
.\scripts\Install-IGScanModule.ps1
```

If you encounter permission issues, use the `-Force` parameter:

```powershell
.\scripts\Install-IGScanModule.ps1 -Force
```

### Option 2: Manual Installation

1. Copy the entire `IGScan` folder to your PowerShell modules directory:
   ```powershell
   Copy-Item -Path ".\modules\IGScan" -Destination "$HOME\Documents\WindowsPowerShell\Modules\IGScan" -Recurse -Force
   ```

2. Import the module:
   ```powershell
   Import-Module IGScan -Force
   ```

3. Verify installation:
   ```powershell
   Get-Command -Module IGScan
   ```

### Option 3: Import Directly (No Installation)

```powershell
Import-Module ".\modules\IGScan\IGScan.psd1"
```

## Usage

Run the scanner using the alias:

```powershell
igscan
```

Or use the full function name with parameters:

```powershell
Invoke-EmployeeRefScan -RootPath "C:\Projects\MyRepo" -MaxFileSizeMB 10
```

## Parameters

- **RootPath**: The root directory to scan (optional - will prompt to find igsolutions_repo if not provided)
- **MaxFileSizeMB**: Maximum file size in MB to scan (default: 5)
- **Extensions**: Comma-separated list of file extensions to scan (optional - uses default list if not provided)

## Scan Modes

1. **Name Mode (1)**: Search for employee by first and last name
2. **String Mode (2)**: Search for a single string (case-insensitive)
3. **Secrets/Keys Mode (3)**: Search for potential secrets and API keys

## Requirements

- PowerShell 5.1 or higher
- Windows PowerShell or PowerShell Core

## Troubleshooting

### Module Not Loading or Outdated

If you get errors about missing files or old versions:

```powershell
# Run the automated installation script to fix
.\scripts\Install-IGScanModule.ps1 -Force
```

### Other Issues

If the module doesn't load, ensure:
1. The module is in a valid PowerShell module path: `$env:PSModulePath`
2. The execution policy allows script execution: `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`
3. All three files are present: `IGScan.psd1`, `IGScan.psm1`, and `Find-EmployeeRefs.ps1`

### Verify Installation

```powershell
# Check if module is installed
Get-Module -ListAvailable IGScan

# Check installed files
Get-ChildItem "$HOME\Documents\WindowsPowerShell\Modules\IGScan"
```
