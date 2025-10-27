# Development Environment Setup

Automated PowerShell scripts for installing and configuring a complete development environment on Windows. This repository provides a robust, enterprise-grade installation process with comprehensive error handling, version management, and detailed progress reporting.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Installed Tools](#installed-tools)
- [Project Structure](#project-structure)
- [Configuration](#configuration)
- [Usage](#usage)
- [Modules](#modules)
- [Scripts](#scripts)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

## Overview

This repository contains modular PowerShell scripts designed to automate the setup of a Windows development environment. The scripts are configuration-driven, allowing easy customization of tool versions and installation parameters.

## Features

- **Configuration-Driven**: All tool versions are managed through a single JSON configuration file
- **Robust Error Handling**: Comprehensive error handling with informative messages and retry logic
- **Version Management**: Automatically checks installed versions and upgrades/dowgrades to match exact requirements
- **Progress Feedback**: Step-by-step progress reporting throughout the installation process
- **Admin Privilege Checking**: Fails fast if not running with administrator privileges
- **System Requirements Validation**: Checks OS version, RAM, disk space, and other system specs
- **Modular Architecture**: Reusable modules for common functionality
- **PowerShell 5.1+ Compatible**: Works with both Windows PowerShell 5.1 and PowerShell 7+
- **CI/CD Ready**: Non-interactive mode for automated pipelines (GitHub Actions, Azure DevOps, Jenkins)
- **Dev Summary Reports**: Detailed summary at the end of each script execution
- **Colored Terminal Output**: Easy-to-read color-coded console messages

## Prerequisites

### System Requirements

- **Operating System**: Windows 10 or later (build 10.0.0.0+)
- **PowerShell**: Version 5.1 or later
- **RAM**: 8 GB minimum (recommended)
- **Disk Space**: 50 GB free space minimum (recommended)
- **Internet Connection**: Required for downloading packages
- **Administrator Privileges**: Required for all installations

### Before Running

1. Ensure you have administrator access to your Windows machine
2. Verify your internet connection is stable
3. Close any applications that might interfere with installations (IDEs, Docker, etc.)
4. Review and update the configuration file if needed (see [Configuration](#configuration))

## Quick Start

### Step 1: Clone or Download Repository

```powershell
# Clone the repository
git clone <repository-url>
cd dev-install
```

### Step 2: Open PowerShell as Administrator

1. Press `Windows + X`
2. Select **"Windows PowerShell (Admin)"** or **"Terminal (Admin)"**
3. Navigate to the repository directory

```powershell
cd C:\path\to\dev-install
```

### Step 3: Set Execution Policy (if needed)

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Step 4: Run Setup Script

```powershell
.\setup.ps1
```

The script will:
1. Display a welcome banner with installation details
2. Prompt for confirmation to proceed
3. Perform pre-flight system checks
4. Install all configured tools in the correct order
5. Display a comprehensive summary report

### Step 5: Verify Installation

After the script completes, **close your PowerShell window** and **open a new one as Administrator**, then verify installations:

```powershell
choco --version
nvm version
node --version
yarn --version
dotnet --version
aws --version
docker --version
```

## Installed Tools

The following tools are installed by default (versions are configurable):

| Tool | Version | Description |
|------|---------|-------------|
| **Chocolatey** | Latest | Package manager for Windows |
| **NVM** | 1.1.5 | Node Version Manager for Windows |
| **Node.js** | 18.19.1 | JavaScript runtime |
| **Yarn** | 1.22.22 | JavaScript package manager |
| **.NET Core SDK** | 3.1.201 | .NET Core development kit |
| **AWS CLI** | 2.0.6 | AWS Command Line Interface |
| **7-Zip** | 22.1 | File archiver |
| **.NET Framework DevPack** | 4.7.2 | .NET Framework developer pack |
| **cURL** | Latest | Data transfer tool |
| **K6** | Latest | Load testing tool |
| **Docker Desktop** | 4.12.0 | Container platform |
| **PSake** | 4.9.0 | PowerShell build automation |
| **AWS.Tools.Installer** | 1.0.2.4 | AWS PowerShell tools installer |
| **AWS.Tools.S3** | 4.1.39.0 | AWS S3 PowerShell module |
| **SqlServer** | 21.1.18221 | SQL Server PowerShell module |

## Project Structure

```
dev-install/
│
├── setup.ps1                          # Main orchestrator script
│
├── config/
│   └── tools-config.json              # Tool versions and configuration
│
├── modules/
│   ├── AdminCheck.psm1                # Admin privilege verification
│   ├── ColorConfig.psm1               # Terminal color output
│   ├── ErrorHandling.psm1             # Error handling utilities
│   ├── SystemCheck.psm1               # System requirements checking
│   └── VersionManagement.psm1         # Version checking and comparison
│
├── scripts/
│   └── Install-DevelopmentTools.ps1   # Development tools installation
│
└── README.md                          # This file
```

## Configuration

### Modifying Tool Versions

Edit `config/tools-config.json` to change tool versions or add new tools:

```json
{
  "developmentTools": {
    "node": {
      "version": "18.19.1",
      "source": "nvm",
      "setAsDefault": true,
      "description": "Node.js JavaScript runtime"
    }
  }
}
```

### Configuration Properties

- **version**: Exact version to install (use "latest" for the newest version)
- **source**: Installation source (`chocolatey`, `powershellgallery`, `nvm`, `script`)
- **packageName**: Package name if different from tool key
- **description**: Tool description for documentation

### System Requirements Configuration

Adjust system requirements in the same configuration file:

```json
{
  "systemRequirements": {
    "minimumWindowsVersion": "10.0.0.0",
    "minimumPowerShellVersion": "5.1",
    "minimumRAM_GB": 8,
    "minimumDiskSpace_GB": 50,
    "requiresAdmin": true
  }
}
```

## Usage

### Main Setup Script

Run the complete setup process:

```powershell
.\setup.ps1
```

**Options:**

```powershell
# Skip system requirements check
.\setup.ps1 -SkipSystemCheck

# Use custom configuration file
.\setup.ps1 -ConfigPath "C:\custom\config.json"

# Combine options
.\setup.ps1 -SkipSystemCheck -ConfigPath ".\custom-config.json"

# Run in CI/CD mode (no prompts, automatic proceed)
.\setup.ps1 -NonInteractive

# Full CI/CD example (recommended for automated environments)
.\setup.ps1 -NonInteractive -SkipSystemCheck
```

### CI/CD Usage

For automated CI/CD pipelines (GitHub Actions, Azure DevOps, Jenkins, etc.), use the `-NonInteractive` flag to run without any prompts:

```powershell
# Minimal CI/CD command
.\setup.ps1 -NonInteractive

# Recommended CI/CD command with system check skip
.\setup.ps1 -NonInteractive -SkipSystemCheck
```

**CI/CD Notes:**
- `-NonInteractive` skips all user prompts and automatically proceeds with installation
- Recommended to combine with `-SkipSystemCheck` in containers or VMs with known specs
- All installations run silently with automatic confirmations
- Script will exit with code 0 on success, 1 on failure
- Output is logged to console for CI/CD tools to capture

**Example GitHub Actions Workflow:**
```yaml
- name: Install Development Tools
  shell: pwsh
  run: |
    .\setup.ps1 -NonInteractive -SkipSystemCheck
```

**Example Azure DevOps Pipeline:**
```yaml
- task: PowerShell@2
  displayName: 'Install Development Environment'
  inputs:
    targetType: 'filePath'
    filePath: '.\setup.ps1'
    arguments: '-NonInteractive -SkipSystemCheck'
```

### Individual Scripts

You can also run individual installation scripts:

```powershell
# Install development tools only
.\scripts\Install-DevelopmentTools.ps1

# With options
.\scripts\Install-DevelopmentTools.ps1 -SkipSystemCheck
```

### Using Modules Directly

Modules can be imported and used in your own scripts:

```powershell
# Import a module
Import-Module .\modules\ColorConfig.psm1

# Use module functions
Write-SuccessMessage "Installation complete!"
Write-ErrorMessage "Something went wrong"
Write-ProgressMessage "Installing package..."
```

## Modules

### AdminCheck.psm1

Provides admin privilege verification and fail-fast functionality.

**Functions:**
- `Test-IsAdmin` - Checks if running as administrator
- `Assert-IsAdmin` - Fails script if not running as admin
- `Get-ElevatedSession` - Attempts to elevate current session

**Example:**
```powershell
Import-Module .\modules\AdminCheck.psm1
Assert-IsAdmin -ScriptName "My Setup Script"
```

### ColorConfig.psm1

Provides colored terminal output for better readability.

**Functions:**
- `Write-SuccessMessage` - Green success message
- `Write-ErrorMessage` - Red error message
- `Write-WarningMessage` - Yellow warning message
- `Write-InfoMessage` - Cyan informational message
- `Write-ProgressMessage` - Magenta progress message
- `Write-HeaderMessage` - Formatted header with borders
- `Write-SectionHeader` - Section divider
- `Write-StepMessage` - Numbered step message
- `Write-DevSummary` - Formatted summary report

**Example:**
```powershell
Import-Module .\modules\ColorConfig.psm1
Write-SuccessMessage "Installation completed"
Write-ProgressMessage "Installing Node.js..."
```

### ErrorHandling.psm1

Provides comprehensive error handling and logging.

**Functions:**
- `Initialize-ErrorHandling` - Sets up error handling
- `Write-ErrorLog` - Logs errors with optional fatal flag
- `Write-WarningLog` - Logs warnings
- `Invoke-WithRetry` - Executes code with retry logic
- `Test-LastExitCode` - Checks command exit codes
- `Show-ErrorSummary` - Displays all errors and warnings
- `Invoke-SafeCommand` - Safely executes external commands

**Example:**
```powershell
Import-Module .\modules\ErrorHandling.psm1

Invoke-WithRetry -ScriptBlock {
    choco install nodejs -y
} -MaxRetries 3 -OperationName "Node.js Installation"
```

### SystemCheck.psm1

Provides system information and requirements validation.

**Functions:**
- `Get-SystemInformation` - Retrieves comprehensive system info
- `Show-SystemInformation` - Displays formatted system details
- `Test-WindowsVersion` - Validates Windows version
- `Test-PowerShellVersion` - Validates PowerShell version
- `Test-AvailableRAM` - Checks available RAM
- `Test-AvailableDiskSpace` - Checks disk space
- `Test-SystemRequirements` - Comprehensive requirements check
- `Test-InternetConnection` - Verifies internet connectivity

**Example:**
```powershell
Import-Module .\modules\SystemCheck.psm1
$sysInfo = Get-SystemInformation
Show-SystemInformation -SystemInfo $sysInfo
Test-SystemRequirements -ConfigPath ".\config\tools-config.json"
```

### VersionManagement.psm1

Provides version checking and comparison functionality.

**Functions:**
- `Get-ChocoPackageVersion` - Gets Chocolatey package version
- `Get-PowerShellModuleVersion` - Gets PowerShell module version
- `Get-NodeVersion` - Gets active Node.js version
- `Get-NvmVersion` - Gets NVM version
- `Get-CommandVersion` - Gets CLI tool version
- `Test-ToolVersion` - Compares installed vs required version
- `Get-InstalledToolVersion` - Gets version based on source type
- `Show-ToolVersionStatus` - Displays version status table

**Example:**
```powershell
Import-Module .\modules\VersionManagement.psm1
$nodeVersion = Get-NodeVersion
$status = Test-ToolVersion -InstalledVersion $nodeVersion -RequiredVersion "18.19.1" -ToolName "Node.js"
```

## Scripts

### setup.ps1

Main orchestrator script that coordinates the entire installation process.

**Responsibilities:**
- Display welcome banner and get user confirmation
- Perform pre-flight system checks
- Execute installation scripts in correct order
- Display final summary and next steps

**Parameters:**
- `-ConfigPath` - Path to configuration file
- `-SkipSystemCheck` - Skip system requirements validation
- `-ToolsOnly` - Only install development tools (default)

### Install-DevelopmentTools.ps1

Installs all development tools based on configuration.

**Responsibilities:**
- Install Chocolatey package manager
- Install development tools in specified order
- Check existing versions and upgrade/downgrade as needed
- Manage environment PATH variables
- Generate detailed installation summary

**Parameters:**
- `-ConfigPath` - Path to configuration file
- `-SkipSystemCheck` - Skip system requirements validation

**Process:**
1. Validates admin privileges
2. Gathers system information
3. Checks system requirements
4. Installs Chocolatey (if needed)
5. Processes each tool in installation order
6. Checks installed version vs required version
7. Uninstalls mismatched versions
8. Installs correct version
9. Refreshes environment variables
10. Generates summary report

## Troubleshooting

### Common Issues

#### "Running scripts is disabled on this system"

**Solution:** Set the execution policy:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

#### "Administrator privileges required"

**Solution:**
1. Right-click PowerShell
2. Select "Run as Administrator"
3. Re-run the script

#### Installation Fails for Specific Tool

**Solution:**
1. Check the error message in the Dev Summary
2. Verify internet connectivity
3. Try installing that specific tool manually first
4. Check if the version exists in the package repository
5. Update the version in `config/tools-config.json`

#### Environment Variables Not Updated

**Solution:**
1. Close ALL PowerShell/Terminal windows
2. Open a new Administrator PowerShell
3. Verify the installation again

#### Chocolatey Installation Fails

**Solution:**
1. Manually install Chocolatey from https://chocolatey.org/install
2. Re-run the setup script

#### Docker Installation Issues

**Solution:**
1. Ensure Hyper-V is enabled (Windows 10/11 Pro required)
2. Ensure virtualization is enabled in BIOS
3. Install Docker Desktop manually if needed

### Getting Help

1. Check the error messages in the Dev Summary
2. Review the detailed error log displayed after execution
3. Verify system requirements are met
4. Check configuration file syntax
5. Ensure internet connectivity
6. Try running individual scripts for isolated testing

### Debug Mode

For more detailed output, you can modify the scripts to include verbose output:

```powershell
.\setup.ps1 -Verbose
```

## Best Practices

1. **Always run as Administrator** - Required for all installations
2. **Close other applications** - Especially Docker, IDEs, and development tools
3. **Review configuration** - Before running, verify the tool versions meet your needs
4. **Backup important data** - Though rare, installations can fail
5. **Read the summary** - Always review the Dev Summary for errors or warnings
6. **Restart terminal** - After installation, always close and reopen your terminal
7. **Verify installations** - Run version checks for each tool after setup

## Contributing

Contributions are welcome! To add new tools or improve existing scripts:

1. Fork the repository
2. Create a feature branch
3. Add your tool configuration to `config/tools-config.json`
4. Update installation logic in `scripts/Install-DevelopmentTools.ps1` if needed
5. **Validate your code** - Run the syntax validation script:
   ```powershell
   .\scripts\Validate-PowerShellSyntax.ps1
   # Or with auto-fix:
   .\scripts\Validate-PowerShellSyntax.ps1 -Fix
   ```
6. **Follow PowerShell best practices** - See [docs/POWERSHELL_BEST_PRACTICES.md](docs/POWERSHELL_BEST_PRACTICES.md)
7. Test thoroughly on a clean Windows installation
8. Update this README with new tool information
9. Submit a pull request

### Code Quality Guidelines

- **PowerShell 5.1+ Compatibility**: All code must work on PowerShell 5.1
- **String Interpolation**: Use `${variable}:` when variable is followed by a colon
- **Error Handling**: Always check `$LASTEXITCODE` after external commands
- **Documentation**: Add comment-based help to all functions
- **Validation**: Run `Validate-PowerShellSyntax.ps1` before committing

See [PowerShell Best Practices](docs/POWERSHELL_BEST_PRACTICES.md) for detailed guidelines.

## License

[Specify your license here]

## Support

For issues, questions, or suggestions:
- Open an issue in this repository
- Contact your team's DevOps lead
- Refer to internal documentation

---

**Last Updated:** 2025-10-23

**Maintained By:** [Your Team Name]
