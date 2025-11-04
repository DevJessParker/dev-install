#Requires -Version 5.1
<#
.SYNOPSIS
    Installs a PowerShell module from a ZIP file with intelligent naming pattern matching.

.DESCRIPTION
    Installs PowerShell modules packaged as ZIP files following the IG<task>_Module naming convention.
    Handles common scenarios including:
    - Duplicate download suffixes (e.g., "IG<task>_Module (1).zip")
    - Version suffixes (e.g., "IG<task>_Module_v1.2.3.zip")
    - Automatic ZIP discovery in Downloads folder
    - Version comparison and backup capabilities
    - Automatic alias creation

.PARAMETER ModuleName
    The module name to install. Accepts multiple formats:
    - IG<task> (e.g., "IGScan")
    - IG<task>_Module (e.g., "IGScan_Module")
    - IG<task>_Module.zip (e.g., "IGScan_Module.zip")
    Name is automatically normalized. Required if not running interactively.

.PARAMETER ZipPath
    Explicit path to the ZIP file. If omitted, auto-discovers in Downloads folder.
    Must be a valid file path if specified.

.PARAMETER SourceUri
    Optional download URL for future extensibility. Currently unused.

.PARAMETER Scope
    Installation scope for the module.
    - CurrentUser: Installs to user's Documents\WindowsPowerShell\Modules
    - AllUsers: Installs to Program Files\WindowsPowerShell\Modules (requires admin)
    Default: CurrentUser

.PARAMETER BackupExisting
    Creates a timestamped backup of existing module installation before overwriting.
    Backup format: <ModuleName>.__backup__yyyyMMdd_HHmmss

.PARAMETER Quiet
    Suppresses informational output. Errors are always shown.

.PARAMETER Force
    Reserved for future use (e.g., skip version checks, force reinstall).

.PARAMETER ZipNamePatternTemplate
    Advanced: Custom regex template for ZIP name matching.
    Template uses {0} placeholder for module name.
    Default: '^{0}_Module(?:\s\(\d+\))?(_v?\d+\.\d+\.\d+)?\.zip$'

.PARAMETER NoAlias
    Skip interactive alias creation prompt.

.PARAMETER PersistAlias
    Automatically add the alias to PowerShell profile for persistence across sessions.
    Default: $true (aliases are automatically persisted)
    Set to $false to skip profile updates.

.EXAMPLE
    .\Install-ModuleFromZip.ps1 -ModuleName "IGScan"
    Installs IGScan module and automatically persists alias to profile.

.EXAMPLE
    .\Install-ModuleFromZip.ps1 -ModuleName "IGScan" -BackupExisting
    Installs with backup of existing version.

.EXAMPLE
    .\Install-ModuleFromZip.ps1 -ModuleName "IGScan_Module.zip" -ZipPath "C:\Custom\Path\IGScan_Module.zip"
    Installs from explicit path.

.EXAMPLE
    .\Install-ModuleFromZip.ps1
    Interactive mode: Prompts for module name and discovers ZIP automatically.

.EXAMPLE
    .\Install-ModuleFromZip.ps1 -ModuleName "IGScan" -PersistAlias $false
    Installs module and creates alias in current session only (not persisted to profile).

.EXAMPLE
    .\Install-ModuleFromZip.ps1 -ModuleName "IGScan" -NoAlias
    Installs module without creating any alias.

.NOTES
    Author: DevJessParker
    Requires: PowerShell 5.1+
    Compatible with: Windows PowerShell 5.1

    ZIP Naming Patterns Supported:
    - IGScan_Module.zip
    - IGScan_Module (1).zip
    - IGScan_Module (12).zip
    - IGScan_Module_v1.0.0.zip
    - IGScan_Module (2)_v1.2.3.zip

.LINK
    https://github.com/DevJessParker/dev-install
#>

[CmdletBinding(DefaultParameterSetName = 'Auto')]
param(
    [Parameter(Mandatory = $false, Position = 0, ParameterSetName = 'Auto')]
    [Parameter(Mandatory = $false, Position = 0, ParameterSetName = 'Explicit')]
    [AllowEmptyString()]
    [string]$ModuleName,

    [Parameter(Mandatory = $false, ParameterSetName = 'Explicit')]
    [ValidateScript({
        if ([string]::IsNullOrWhiteSpace($_)) { return $true }
        if (-not (Test-Path -Path $_ -PathType Leaf)) {
            throw "ZipPath must be a valid file: $_"
        }
        if (-not ($_ -match '\.zip$')) {
            throw "ZipPath must be a .zip file: $_"
        }
        return $true
    })]
    [string]$ZipPath,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^https?://')]
    [string]$SourceUri,

    [Parameter(Mandatory = $false)]
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string]$Scope = 'CurrentUser',

    [Parameter(Mandatory = $false)]
    [switch]$BackupExisting,

    [Parameter(Mandatory = $false)]
    [switch]$Quiet,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ZipNamePatternTemplate = '^{0}_Module(?:\s\(\d+\))?(_v?\d+\.\d+\.\d+)?\.zip$',

    [Parameter(Mandatory = $false)]
    [switch]$NoAlias,

    [Parameter(Mandatory = $false)]
    [bool]$PersistAlias = $true
)

#region Script Initialization

# Script-level settings
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Enable debug output (set to $false in production)
$script:DebugEnabled = $true

# Performance: Pre-load required assemblies
try {
    Add-Type -AssemblyName 'System.IO.Compression.FileSystem' -ErrorAction Stop | Out-Null
    Add-Type -AssemblyName 'System.IO.Compression' -ErrorAction Stop | Out-Null
}
catch {
    Write-Error "Failed to load required .NET assemblies. This script requires .NET Framework 4.5+."
    exit 1
}

#endregion

#region Error Handling

# Global error trap for detailed diagnostics
trap {
    $errorDetails = @"

================================================================================
ERROR CONTEXT - DIAGNOSTIC INFORMATION
================================================================================
Exception Type: $($_.Exception.GetType().FullName)
Error Message:  $($_.Exception.Message)
"@

    if ($_.InvocationInfo) {
        $errorDetails += @"

Location:       $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)
Line Content:   $($_.InvocationInfo.Line.Trim())
Position:
$($_.InvocationInfo.PositionMessage)
"@
    }

    $errorDetails += @"

Script Variables:
  ModuleName = '$ModuleName'
  ZipPath    = '$ZipPath'
  Scope      = '$Scope'
================================================================================
"@

    Write-Host $errorDetails -ForegroundColor Red

    # Re-throw to ensure exit code is set
    throw
}

#endregion

#region Helper Functions - Logging

function Write-DebugLog {
    <#
    .SYNOPSIS
        Writes debug messages when debug mode is enabled.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Message
    )

    process {
        if ($script:DebugEnabled) {
            Write-Host "[DEBUG] $Message" -ForegroundColor DarkCyan
        }
    }
}

function Write-InfoMessage {
    <#
    .SYNOPSIS
        Writes informational messages unless in quiet mode.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Message
    )

    process {
        if (-not $Quiet) {
            Write-Host "[INFO]  $Message" -ForegroundColor Gray
        }
    }
}

function Write-SuccessMessage {
    <#
    .SYNOPSIS
        Writes success messages unless in quiet mode.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Message
    )

    process {
        if (-not $Quiet) {
            Write-Host "[OK]    $Message" -ForegroundColor Green
        }
    }
}

function Write-WarningMessage {
    <#
    .SYNOPSIS
        Writes warning messages unless in quiet mode.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Message
    )

    process {
        if (-not $Quiet) {
            Write-Host "[WARN]  $Message" -ForegroundColor Yellow
        }
    }
}

function Write-ErrorMessage {
    <#
    .SYNOPSIS
        Writes error messages (always shown, even in quiet mode).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Message
    )

    process {
        Write-Host "[ERROR] $Message" -ForegroundColor Red
    }
}

#endregion

#region Core Functions

function Normalize-ModuleName {
    <#
    .SYNOPSIS
        Normalizes module name input to standard IG<task> format.

    .DESCRIPTION
        Handles various input formats and edge cases:
        - Removes quotes, whitespace, nulls
        - Strips .zip extension
        - Removes _Module, -Module, " Module" suffixes
        - Filters non-ASCII control characters
        - Validates IG prefix (case-insensitive) followed by alphanumerics

    .PARAMETER InputName
        Raw module name input from user or parameter.

    .OUTPUTS
        [string] Normalized module name or $null if invalid.

    .EXAMPLE
        Normalize-ModuleName '"IGScan_Module.zip"'
        Returns: IGScan
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$InputName
    )

    if ([string]::IsNullOrWhiteSpace($InputName)) {
        Write-DebugLog "Normalize-ModuleName: Input is null or whitespace"
        return $null
    }

    $normalized = $InputName

    # Step 1: Trim whitespace and null characters
    $normalized = $normalized.Trim(" `t`r`n`0")

    # Step 2: Strip surrounding quotes
    if ($normalized.Length -ge 2) {
        if ($normalized.StartsWith('"') -and $normalized.EndsWith('"')) {
            $normalized = $normalized.Substring(1, $normalized.Length - 2)
        }
        elseif ($normalized.StartsWith("'") -and $normalized.EndsWith("'")) {
            $normalized = $normalized.Substring(1, $normalized.Length - 2)
        }
    }

    # Step 3: Remove .zip extension (case-insensitive)
    if ($normalized -match '\.zip$') {
        $normalized = $normalized.Substring(0, $normalized.Length - 4)
    }

    # Step 4: Remove _Module, -Module, or " Module" suffix (case-insensitive)
    $normalized = $normalized -replace '(\s+|[-_])(?i:Module)$', ''

    # Step 5: Filter non-ASCII printable characters (32-126)
    $stringBuilder = New-Object System.Text.StringBuilder
    foreach ($char in $normalized.ToCharArray()) {
        $charCode = [int][char]$char
        if ($charCode -ge 32 -and $charCode -le 126) {
            [void]$stringBuilder.Append($char)
        }
    }
    $normalized = $stringBuilder.ToString().Trim()

    Write-DebugLog "Normalize-ModuleName: '$InputName' -> '$normalized'"

    # Step 6: Validate format (IG prefix + alphanumerics)
    if ($normalized -match '^(?i:IG)[A-Za-z0-9]+$') {
        return $normalized
    }

    Write-DebugLog "Normalize-ModuleName: Final validation failed for '$normalized'"
    return $null
}

function Resolve-ZipPath {
    <#
    .SYNOPSIS
        Resolves the ZIP file path either from explicit parameter or auto-discovery.

    .DESCRIPTION
        Resolution strategy:
        1. If ZipPath parameter provided, validate and use it
        2. Otherwise, search Downloads folder for matching pattern
        3. Pattern supports duplicate suffixes " (n)" and version suffixes
        4. Returns most recently modified match if multiple candidates exist

    .PARAMETER NormalizedModuleName
        Normalized module name (e.g., "IGScan")

    .PARAMETER ZipNamePattern
        Regex template for matching ZIP files

    .PARAMETER ExplicitZipPath
        Explicit ZIP path from parameter

    .OUTPUTS
        [string] Full path to resolved ZIP file

    .EXAMPLE
        Resolve-ZipPath -NormalizedModuleName "IGScan" -ZipNamePattern "^{0}_Module..." -ExplicitZipPath ""
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$NormalizedModuleName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ZipNamePattern,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$ExplicitZipPath
    )

    # Use explicit path if provided
    if (-not [string]::IsNullOrWhiteSpace($ExplicitZipPath)) {
        if (-not (Test-Path -Path $ExplicitZipPath -PathType Leaf)) {
            throw "Explicit ZipPath not found: $ExplicitZipPath"
        }
        Write-DebugLog "Using explicit ZIP path: $ExplicitZipPath"
        return (Get-Item -LiteralPath $ExplicitZipPath).FullName
    }

    # Auto-discover in Downloads folder
    $downloadsFolder = Join-Path $env:USERPROFILE 'Downloads'

    if (-not (Test-Path -Path $downloadsFolder -PathType Container)) {
        throw "Downloads folder not found: $downloadsFolder. Please provide -ZipPath explicitly."
    }

    Write-DebugLog "Searching for ZIP in: $downloadsFolder"

    # Build regex pattern
    $escapedModuleName = [regex]::Escape($NormalizedModuleName)
    $regexPattern = $ZipNamePattern -f $escapedModuleName

    Write-DebugLog "ZIP search pattern: $regexPattern"

    # PS 5.1-compatible regex
    $regex = New-Object System.Text.RegularExpressions.Regex(
        $regexPattern,
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    # Find matching ZIP files, sorted by last write time (newest first)
    $candidates = Get-ChildItem -Path $downloadsFolder -Filter '*.zip' -File -ErrorAction SilentlyContinue |
        Where-Object { $regex.IsMatch($_.Name) } |
        Sort-Object LastWriteTime -Descending

    if ($null -eq $candidates -or $candidates.Count -eq 0) {
        $examplePattern = "${NormalizedModuleName}_Module[ (n)][_vX.Y.Z].zip"
        throw "No ZIP file found in '$downloadsFolder' matching pattern: $examplePattern"
    }

    $selectedZip = $candidates[0]

    Write-InfoMessage "Auto-discovered ZIP: $($selectedZip.Name)"
    Write-DebugLog "Full ZIP path: $($selectedZip.FullName)"

    if ($candidates.Count -gt 1) {
        Write-WarningMessage "Multiple matching ZIPs found. Using most recent: $($selectedZip.Name)"
    }

    return $selectedZip.FullName
}

function Get-InstalledModuleVersion {
    <#
    .SYNOPSIS
        Gets the currently installed version of a module, if any.

    .PARAMETER ModuleName
        Name of the module to check.

    .OUTPUTS
        [Version] Installed module version, or $null if not installed.
    #>
    [CmdletBinding()]
    [OutputType([Version])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleName
    )

    try {
        $installedModules = Get-Module -ListAvailable -Name $ModuleName -ErrorAction SilentlyContinue |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if ($null -ne $installedModules) {
            return [Version]$installedModules.Version
        }
    }
    catch {
        Write-DebugLog "Error checking installed module version: $($_.Exception.Message)"
    }

    return $null
}

function Get-ZipModuleVersion {
    <#
    .SYNOPSIS
        Extracts module version from .psd1 manifest inside ZIP file.

    .DESCRIPTION
        Optimized I/O approach:
        - Opens ZIP file in read-only mode
        - Streams .psd1 file to temp location
        - Parses version without extracting entire archive
        - Properly disposes all streams and handles

    .PARAMETER ZipFilePath
        Full path to ZIP file.

    .PARAMETER ModuleName
        Expected module name for .psd1 file matching.

    .OUTPUTS
        [Version] Module version from manifest, or $null if not found.
    #>
    [CmdletBinding()]
    [OutputType([Version])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ZipFilePath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleName
    )

    if (-not (Test-Path -Path $ZipFilePath -PathType Leaf)) {
        Write-DebugLog "ZIP file not found: $ZipFilePath"
        return $null
    }

    $tempPsd1 = $null
    $fileStream = $null
    $zipArchive = $null
    $entryStream = $null
    $outputStream = $null

    try {
        # Create temp file for .psd1 extraction
        $tempPsd1 = Join-Path $env:TEMP ("{0}_psd1_{1}.psd1" -f $ModuleName, [guid]::NewGuid().ToString('N'))

        # Open ZIP file
        $fileStream = [System.IO.File]::OpenRead($ZipFilePath)
        $zipArchive = New-Object System.IO.Compression.ZipArchive(
            $fileStream,
            [System.IO.Compression.ZipArchiveMode]::Read
        )

        # Find .psd1 entry (prefer exact match, fallback to any .psd1)
        $psd1Pattern = '(^|/|\\){0}\.psd1$' -f [regex]::Escape($ModuleName)
        $psd1Entry = $zipArchive.Entries |
            Where-Object { $_.FullName -match $psd1Pattern } |
            Select-Object -First 1

        if ($null -eq $psd1Entry) {
            # Fallback: any .psd1 file
            $psd1Entry = $zipArchive.Entries |
                Where-Object { $_.FullName -match '\.psd1$' } |
                Select-Object -First 1
        }

        if ($null -eq $psd1Entry) {
            Write-DebugLog "No .psd1 manifest found in ZIP"
            return $null
        }

        Write-DebugLog "Found manifest: $($psd1Entry.FullName)"

        # Extract .psd1 to temp file
        $entryStream = $psd1Entry.Open()
        $outputStream = [System.IO.File]::Create($tempPsd1)
        $entryStream.CopyTo($outputStream)

        # Close streams before reading file
        $outputStream.Dispose()
        $entryStream.Dispose()
        $outputStream = $null
        $entryStream = $null

        # Parse module manifest
        $manifestData = Import-PowerShellDataFile -Path $tempPsd1 -ErrorAction Stop

        if ($manifestData -and $manifestData.ModuleVersion) {
            $version = [Version]$manifestData.ModuleVersion
            Write-DebugLog "Detected version in ZIP: $version"
            return $version
        }

        return $null
    }
    catch {
        Write-DebugLog "Error extracting version from ZIP: $($_.Exception.Message)"
        return $null
    }
    finally {
        # Dispose all resources in correct order
        if ($null -ne $outputStream) { $outputStream.Dispose() }
        if ($null -ne $entryStream) { $entryStream.Dispose() }
        if ($null -ne $zipArchive) { $zipArchive.Dispose() }
        if ($null -ne $fileStream) { $fileStream.Dispose() }

        # Clean up temp file
        if ($null -ne $tempPsd1 -and (Test-Path -Path $tempPsd1)) {
            Remove-Item -Path $tempPsd1 -Force -ErrorAction SilentlyContinue
        }
    }
}

function Expand-ZipToModule {
    <#
    .SYNOPSIS
        Extracts ZIP file to module installation directory.

    .DESCRIPTION
        Handles:
        - Scope-based destination selection (CurrentUser vs AllUsers)
        - Backup of existing installations
        - File unblocking for security
        - Folder name normalization

    .PARAMETER ZipFilePath
        Full path to ZIP file to extract.

    .PARAMETER ModuleName
        Name of the module (used for destination folder).

    .PARAMETER InstallScope
        Installation scope (CurrentUser or AllUsers).

    .PARAMETER CreateBackup
        Whether to backup existing installation.

    .OUTPUTS
        [string] Full path to installed module directory.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ZipFilePath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('CurrentUser', 'AllUsers')]
        [string]$InstallScope,

        [Parameter(Mandatory = $false)]
        [switch]$CreateBackup
    )

    # Determine destination root based on scope
    if ($InstallScope -eq 'AllUsers') {
        $destinationRoot = Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'
    }
    else {
        $destinationRoot = Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Modules'
    }

    # Ensure destination root exists
    if (-not (Test-Path -Path $destinationRoot -PathType Container)) {
        Write-DebugLog "Creating module directory: $destinationRoot"
        New-Item -Path $destinationRoot -ItemType Directory -Force | Out-Null
    }

    $destinationPath = Join-Path $destinationRoot $ModuleName

    # Handle existing installation (case-insensitive check for Windows)
    # This handles cases where module was installed with different casing (e.g., "igscan" vs "IGScan")
    $existingModulePath = $null
    if (Test-Path -Path $destinationPath) {
        # Get the actual path with its current casing
        $existingModulePath = (Get-Item -Path $destinationPath -ErrorAction SilentlyContinue).FullName

        if ($null -ne $existingModulePath) {
            $actualFolderName = Split-Path -Path $existingModulePath -Leaf

            if ($actualFolderName -cne $ModuleName) {
                Write-InfoMessage "Found existing module with different casing: '$actualFolderName' (will update to '$ModuleName')"
            }
        }

        if ($CreateBackup) {
            $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $backupName = "{0}.__backup__{1}" -f $ModuleName, $timestamp
            $backupPath = Join-Path $destinationRoot $backupName

            Write-InfoMessage "Backing up existing module to: $backupName"

            try {
                Rename-Item -Path $destinationPath -NewName $backupName -Force -ErrorAction Stop
            }
            catch {
                Write-WarningMessage "Backup failed, removing existing installation instead"
                Remove-Item -Path $destinationPath -Recurse -Force -ErrorAction Stop
            }
        }
        else {
            Write-InfoMessage "Removing existing module installation"
            Remove-Item -Path $destinationPath -Recurse -Force -ErrorAction Stop
        }
    }

    # Extract ZIP file
    Write-InfoMessage "Extracting: $([System.IO.Path]::GetFileName($ZipFilePath))"

    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipFilePath, $destinationRoot)
    }
    catch {
        throw "Failed to extract ZIP file: $($_.Exception.Message)"
    }

    # Handle case where ZIP contains a folder with different name than expected
    # (e.g., ZIP contains "IGScan/" but we want "IGScan" as the module name)
    $zipBaseName = [System.IO.Path]::GetFileNameWithoutExtension($ZipFilePath)
    $extractedPath = Join-Path $destinationRoot $zipBaseName

    if ((-not (Test-Path -Path $destinationPath)) -and (Test-Path -Path $extractedPath)) {
        Write-DebugLog "Renaming extracted folder: $zipBaseName -> $ModuleName"
        Rename-Item -Path $extractedPath -NewName $ModuleName -Force -ErrorAction Stop
    }

    # Unblock all files (remove Zone.Identifier alternate data stream)
    Write-InfoMessage "Unblocking files..."

    Get-ChildItem -Path $destinationPath -Recurse -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            try {
                Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue
            }
            catch {
                # Silently continue if unblock fails
                Write-DebugLog "Could not unblock: $($_.FullName)"
            }
        }

    return $destinationPath
}

function Get-ModuleNameFromFunction {
    <#
    .SYNOPSIS
        Extracts module name from a function name or path.

    .DESCRIPTION
        Attempts to extract the IG module name from various formats:
        - Start-IGScan -> IGScan
        - C:\...\IGScan\Start-IGScan -> IGScan
        - IGScan\Invoke-Something -> IGScan

    .PARAMETER FunctionName
        The function name or path to extract module name from.

    .OUTPUTS
        [string] Extracted module name, or $null if not found.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$FunctionName
    )

    if ([string]::IsNullOrWhiteSpace($FunctionName)) {
        return $null
    }

    # Try to extract IG<name> pattern from the function name
    # Handles: Start-IGScan, Invoke-IGScan, IGScan, etc.
    if ($FunctionName -match '\b(IG[A-Za-z0-9]+)\b') {
        return $Matches[1]
    }

    # Try to extract from path: C:\...\IGScan\...
    if ($FunctionName -match '\\(IG[A-Za-z0-9]+)\\') {
        return $Matches[1]
    }

    return $null
}

function New-ModuleAlias {
    <#
    .SYNOPSIS
        Creates or updates a global alias for the module's primary function (idempotent).

    .DESCRIPTION
        Intelligent alias creation with module-aware conflict resolution:

        Strategy:
        1. Prefer "Start-<ModuleName>" function if it exists
        2. Fallback to first exported function from module
        3. Extract module names from existing and new targets for comparison

        Scenarios:
        - Exact same target: Silently refresh (fully idempotent)
        - Same module, different function: Auto-update without prompt (module upgrade)
        - Different module: Prompt user to reassign with clear conflict details
        - Built-in command conflict: Skip with warning

    .PARAMETER AliasName
        Desired alias name (should be lowercase, no digits).

    .PARAMETER ModuleName
        Name of the module to create alias for.

    .PARAMETER IsReinstall
        Indicates this is a re-installation (for context/logging).

    .OUTPUTS
        [bool] $true if alias created/updated successfully, $false otherwise.

    .EXAMPLE
        New-ModuleAlias -AliasName "igscan" -ModuleName "IGScan"
        Creates or updates the 'igscan' alias, auto-updating if same module.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AliasName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleName,

        [Parameter(Mandatory = $false)]
        [switch]$IsReinstall
    )

    # Determine target function
    $targetFunction = "Start-$ModuleName"
    $targetCommand = Get-Command -Name $targetFunction -ErrorAction SilentlyContinue

    if ($null -eq $targetCommand) {
        # Fallback: Import module and use first exported function
        Write-DebugLog "Function '$targetFunction' not found, importing module to find target"

        try {
            $module = Import-Module -Name $ModuleName -PassThru -ErrorAction Stop

            if ($module -and $module.ExportedFunctions -and $module.ExportedFunctions.Keys.Count -gt 0) {
                $targetFunction = $module.ExportedFunctions.Keys | Select-Object -First 1
                Write-DebugLog "Using first exported function: $targetFunction"
            }
            else {
                Write-WarningMessage "Could not find any exported functions in module '$ModuleName'"
                return $false
            }
        }
        catch {
            Write-WarningMessage "Failed to import module for alias creation: $($_.Exception.Message)"
            return $false
        }
    }
    else {
        $targetFunction = $targetCommand.Name
    }

    # Check for existing command with same name
    $existingCommand = Get-Command -Name $AliasName -ErrorAction SilentlyContinue

    if ($null -ne $existingCommand) {
        # Handle different scenarios based on what exists
        if ($existingCommand.CommandType -eq 'Alias') {
            $existingTarget = $existingCommand.Definition

            # Extract module names for comparison
            $existingModuleName = Get-ModuleNameFromFunction -FunctionName $existingTarget
            $newModuleName = Get-ModuleNameFromFunction -FunctionName $targetFunction

            Write-DebugLog "Existing alias target: $existingTarget (Module: $existingModuleName)"
            Write-DebugLog "New alias target: $targetFunction (Module: $newModuleName)"

            # Scenario 1: Alias points to exact same function (idempotent)
            if ($existingTarget -eq $targetFunction) {
                Write-SuccessMessage "Alias '$AliasName' already configured correctly -> $targetFunction"

                try {
                    # Remove and recreate to ensure it's current
                    Remove-Item -Path "Alias:\$AliasName" -Force -ErrorAction SilentlyContinue
                    Set-Alias -Name $AliasName -Value $targetFunction -Scope Global -Option None -ErrorAction Stop
                    return $true
                }
                catch {
                    Write-WarningMessage "Failed to refresh alias: $($_.Exception.Message)"
                    return $false
                }
            }
            # Scenario 2: Same module (e.g., IGScan -> IGScan) - auto-update without prompt
            elseif ($null -ne $existingModuleName -and $null -ne $newModuleName -and $existingModuleName -eq $newModuleName) {
                Write-InfoMessage "Updating '$AliasName' alias for module '$newModuleName'..."
                Write-InfoMessage "  Previous: $existingTarget"
                Write-InfoMessage "  New:      $targetFunction"

                try {
                    Remove-Item -Path "Alias:\$AliasName" -Force -ErrorAction SilentlyContinue
                    Set-Alias -Name $AliasName -Value $targetFunction -Scope Global -Option None -ErrorAction Stop
                    Write-SuccessMessage "Alias updated for module '$newModuleName'"
                    return $true
                }
                catch {
                    Write-WarningMessage "Failed to update alias: $($_.Exception.Message)"
                    return $false
                }
            }
            # Scenario 3: Different modules or commands - prompt user
            else {
                Write-Host ""
                Write-Host "================================================================================" -ForegroundColor Yellow
                Write-Host "  ALIAS CONFLICT DETECTED" -ForegroundColor Yellow
                Write-Host "================================================================================" -ForegroundColor Yellow
                Write-Host ""
                Write-WarningMessage "The alias '$AliasName' is already assigned to a different command:"
                Write-Host ""

                if ($null -ne $existingModuleName) {
                    Write-Host "  Current:  $AliasName -> $existingTarget" -ForegroundColor Yellow
                    Write-Host "            (Module: $existingModuleName)" -ForegroundColor DarkYellow
                }
                else {
                    Write-Host "  Current:  $AliasName -> $existingTarget" -ForegroundColor Yellow
                }

                Write-Host ""

                if ($null -ne $newModuleName) {
                    Write-Host "  New:      $AliasName -> $targetFunction" -ForegroundColor Green
                    Write-Host "            (Module: $newModuleName)" -ForegroundColor DarkGreen
                }
                else {
                    Write-Host "  New:      $AliasName -> $targetFunction" -ForegroundColor Green
                }

                Write-Host ""
                Write-Host "Reassign the alias to the new module? (Y/N): " -ForegroundColor Cyan -NoNewline

                $response = Read-Host

                if ($response -match '^[Yy]') {
                    try {
                        Remove-Item -Path "Alias:\$AliasName" -Force -ErrorAction Stop
                        Set-Alias -Name $AliasName -Value $targetFunction -Scope Global -Option None -ErrorAction Stop
                        Write-Host ""
                        Write-SuccessMessage "Alias reassigned: '$AliasName' -> $targetFunction"
                        return $true
                    }
                    catch {
                        Write-Host ""
                        Write-WarningMessage "Failed to reassign alias: $($_.Exception.Message)"
                        return $false
                    }
                }
                else {
                    Write-Host ""
                    Write-InfoMessage "Kept existing alias: '$AliasName' -> $existingTarget"
                    Write-InfoMessage "You can manually change it later using: Set-Alias $AliasName $targetFunction"
                    return $false
                }
            }
        }
        else {
            # Not an alias - it's a built-in command, function, or cmdlet
            Write-Host ""
            Write-WarningMessage "Cannot create alias '$AliasName' - name conflicts with existing $($existingCommand.CommandType)"
            Write-WarningMessage "Command: $($existingCommand.Name)"
            Write-WarningMessage "Skipping alias creation to avoid breaking existing functionality"
            return $false
        }
    }

    # No existing command - create new alias
    try {
        Set-Alias -Name $AliasName -Value $targetFunction -Scope Global -Option None -ErrorAction Stop
        Write-SuccessMessage "Created alias: '$AliasName' -> $targetFunction"
        return $true
    }
    catch {
        Write-WarningMessage "Failed to create alias '$AliasName': $($_.Exception.Message)"
        return $false
    }
}

function Add-AliasToProfile {
    <#
    .SYNOPSIS
        Automatically adds or updates alias in PowerShell profile (idempotent).

    .DESCRIPTION
        Manages alias persistence in PowerShell profile:
        1. Creates profile file if it doesn't exist
        2. Detects if alias already exists in profile
        3. Updates existing alias or adds new one
        4. Handles errors gracefully (read-only files, permissions, etc.)
        5. Fully idempotent - safe to run multiple times

    .PARAMETER AliasName
        Name of the alias to persist.

    .PARAMETER TargetCommand
        The command the alias should point to.

    .OUTPUTS
        [bool] $true if profile updated successfully, $false otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AliasName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetCommand
    )

    try {
        $profilePath = $PROFILE

        # Check if profile exists, create if not
        if (-not (Test-Path -Path $profilePath -PathType Leaf)) {
            Write-InfoMessage "PowerShell profile not found. Creating: $profilePath"

            $profileDir = Split-Path -Path $profilePath -Parent

            if (-not (Test-Path -Path $profileDir -PathType Container)) {
                New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
            }

            New-Item -Path $profilePath -ItemType File -Force | Out-Null
            Write-SuccessMessage "Created PowerShell profile"
        }

        # Read current profile content
        $profileContent = Get-Content -Path $profilePath -Raw -ErrorAction Stop

        if ($null -eq $profileContent) {
            $profileContent = ""
        }

        # Pattern to match existing alias line
        $aliasPattern = "^\s*Set-Alias\s+(-Name\s+)?['""]?$([regex]::Escape($AliasName))['""]?\s+(-Value\s+)?['""]?.*['""]?\s*$"

        # Check if alias already exists
        $existingLines = $profileContent -split "`r?`n"
        $aliasLineIndex = -1
        $currentAliasLine = $null

        for ($i = 0; $i -lt $existingLines.Count; $i++) {
            if ($existingLines[$i] -match $aliasPattern) {
                $aliasLineIndex = $i
                $currentAliasLine = $existingLines[$i].Trim()
                break
            }
        }

        $newAliasLine = "Set-Alias $AliasName $TargetCommand"

        if ($aliasLineIndex -ge 0) {
            # Alias exists - check if it needs updating
            if ($currentAliasLine -match [regex]::Escape($TargetCommand)) {
                # Idempotent case: alias already correct
                Write-SuccessMessage "Alias '$AliasName' already exists in profile and points to: $TargetCommand"
                return $true
            }
            else {
                # Update existing alias
                Write-InfoMessage "Updating alias '$AliasName' in profile..."
                $existingLines[$aliasLineIndex] = $newAliasLine
                $updatedContent = $existingLines -join "`r`n"

                Set-Content -Path $profilePath -Value $updatedContent -Force -ErrorAction Stop
                Write-SuccessMessage "Updated alias in profile: $AliasName -> $TargetCommand"
                return $true
            }
        }
        else {
            # Add new alias to profile
            Write-InfoMessage "Adding alias '$AliasName' to PowerShell profile..."

            # Add newline if profile doesn't end with one
            if ($profileContent.Length -gt 0 -and -not ($profileContent -match '[\r\n]$')) {
                $profileContent += "`r`n"
            }

            # Add header comment if this is the first IG module alias
            if ($profileContent -notmatch 'IG Module Aliases') {
                $profileContent += "`r`n"
                $profileContent += "# IG Module Aliases (managed by Install-ModuleFromZip.ps1)`r`n"
            }

            $profileContent += "$newAliasLine`r`n"

            Set-Content -Path $profilePath -Value $profileContent -Force -ErrorAction Stop
            Write-SuccessMessage "Added alias to profile: $AliasName -> $TargetCommand"
            return $true
        }
    }
    catch [System.UnauthorizedAccessException] {
        Write-WarningMessage "Cannot update profile: Access denied"
        Write-WarningMessage "Profile path: $profilePath"
        Write-WarningMessage "You may need to run PowerShell as Administrator or check file permissions"
        return $false
    }
    catch [System.IO.IOException] {
        Write-WarningMessage "Cannot update profile: I/O error - $($_.Exception.Message)"
        Write-WarningMessage "Profile may be read-only or in use by another process"
        return $false
    }
    catch {
        Write-WarningMessage "Failed to update PowerShell profile: $($_.Exception.Message)"
        Write-DebugLog "Error type: $($_.Exception.GetType().FullName)"
        return $false
    }
}

#endregion

#region Main Execution

try {
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "  PowerShell Module Installer (IG Module Packages)" -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host ""

    # ============================================================================
    # Step 1: Prompt and validate module name
    # ============================================================================

    if ([string]::IsNullOrWhiteSpace($ModuleName)) {
        Write-Host "Enter the PowerShell Module Name" -ForegroundColor White
        Write-Host "Accepted formats:" -ForegroundColor Gray
        Write-Host "  - IG<task> (e.g., IGScan)" -ForegroundColor Gray
        Write-Host "  - IG<task>_Module (e.g., IGScan_Module)" -ForegroundColor Gray
        Write-Host "  - IG<task>_Module.zip (e.g., IGScan_Module.zip)" -ForegroundColor Gray
        Write-Host ""
        $ModuleName = Read-Host "Module Name"
    }

    $normalizedModuleName = Normalize-ModuleName -InputName $ModuleName

    if ($null -eq $normalizedModuleName) {
        Write-Host ""
        Write-ErrorMessage "Invalid module name: '$ModuleName'"
        Write-Host ""
        Write-Host "Expected format:" -ForegroundColor Yellow
        Write-Host "  - Must start with 'IG' (case-insensitive)" -ForegroundColor Yellow
        Write-Host "  - Followed by letters and/or numbers only" -ForegroundColor Yellow
        Write-Host "  - Examples: IGScan, IGDeploy, IGTest123" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Tips:" -ForegroundColor Gray
        Write-Host "  - Remove trailing spaces or quotes" -ForegroundColor Gray
        Write-Host "  - '_Module' and '.zip' suffixes are automatically stripped" -ForegroundColor Gray
        Write-Host ""
        throw "Invalid module name format"
    }

    Write-DebugLog "Normalized module name: $normalizedModuleName"

    # ============================================================================
    # Step 2: Resolve ZIP file path
    # ============================================================================

    $resolvedZipPath = Resolve-ZipPath `
        -NormalizedModuleName $normalizedModuleName `
        -ZipNamePattern $ZipNamePatternTemplate `
        -ExplicitZipPath $ZipPath

    Write-DebugLog "Resolved ZIP path: $resolvedZipPath"

    # ============================================================================
    # Step 3: Extract version information and compare
    # ============================================================================

    $zipVersion = Get-ZipModuleVersion -ZipFilePath $resolvedZipPath -ModuleName $normalizedModuleName
    $installedVersion = Get-InstalledModuleVersion -ModuleName $normalizedModuleName

    if ($null -ne $zipVersion) {
        Write-InfoMessage "ZIP contains module version: $zipVersion"
    }
    else {
        Write-WarningMessage "Could not detect version in ZIP manifest"
    }

    if ($null -ne $installedVersion) {
        Write-InfoMessage "Currently installed version: $installedVersion"

        if ($null -ne $zipVersion) {
            if ($zipVersion -gt $installedVersion) {
                Write-SuccessMessage "This is an UPGRADE: $installedVersion -> $zipVersion"
            }
            elseif ($zipVersion -lt $installedVersion) {
                Write-WarningMessage "This is a DOWNGRADE: $installedVersion -> $zipVersion"
            }
            else {
                Write-InfoMessage "Reinstalling same version: $installedVersion"
            }
        }
    }
    else {
        Write-InfoMessage "Module is not currently installed"
    }

    # ============================================================================
    # Step 4: Extract and install module
    # ============================================================================

    Write-Host ""
    Write-Host "Installing module..." -ForegroundColor Cyan

    $installedPath = Expand-ZipToModule `
        -ZipFilePath $resolvedZipPath `
        -ModuleName $normalizedModuleName `
        -InstallScope $Scope `
        -CreateBackup:$BackupExisting

    # ============================================================================
    # Step 5: Verify installation
    # ============================================================================

    $verificationModule = Get-Module -ListAvailable -Name $normalizedModuleName -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if ($null -ne $verificationModule) {
        Write-Host ""
        Write-SuccessMessage "Module '$normalizedModuleName' installed successfully!"
        Write-Host ""
        Write-Host "Module Details:" -ForegroundColor White
        Write-Host "  Name:       $($verificationModule.Name)" -ForegroundColor Gray
        Write-Host "  Version:    $($verificationModule.Version)" -ForegroundColor Gray
        Write-Host "  Location:   $($verificationModule.ModuleBase)" -ForegroundColor Gray
        Write-Host ""
    }
    else {
        Write-WarningMessage "Module installed but not yet visible to Get-Module"
        Write-WarningMessage "Open a NEW PowerShell session to refresh the module cache"
    }

    # ============================================================================
    # Step 6: Create alias (interactive)
    # ============================================================================

    if (-not $NoAlias) {
        Write-Host "-------------------------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host "Alias Configuration" -ForegroundColor Cyan
        Write-Host "-------------------------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host ""

        # Generate default alias: lowercase, remove digits
        $defaultAlias = ($normalizedModuleName.ToLower() -replace '\d', '')

        Write-Host "Create a short alias for quick access to this module?" -ForegroundColor White
        Write-Host ""
        Write-Host "Default alias: " -ForegroundColor Gray -NoNewline
        Write-Host $defaultAlias -ForegroundColor Green
        Write-Host ""
        Write-Host "Options:" -ForegroundColor Gray
        Write-Host "  - Press ENTER to accept default" -ForegroundColor Gray
        Write-Host "  - Type a custom alias name" -ForegroundColor Gray
        Write-Host "  - Type 'skip' to skip alias creation" -ForegroundColor Gray
        Write-Host ""

        $aliasInput = Read-Host "Alias [$defaultAlias]"

        $selectedAlias = $null

        if ([string]::IsNullOrWhiteSpace($aliasInput)) {
            # User pressed Enter - use default
            $selectedAlias = $defaultAlias
        }
        elseif ($aliasInput.Trim().ToLower() -eq 'skip') {
            # User explicitly skipped
            Write-InfoMessage "Alias creation skipped"
            $selectedAlias = $null
        }
        else {
            # User provided custom alias - sanitize it
            $selectedAlias = $aliasInput.Trim().ToLower() -replace '\s', '' -replace '\d', ''
        }

        if ($null -ne $selectedAlias) {
            # Detect if this is a re-installation
            $isReinstallation = ($null -ne $installedVersion)

            $aliasCreated = New-ModuleAlias -AliasName $selectedAlias -ModuleName $normalizedModuleName -IsReinstall:$isReinstallation

            if ($aliasCreated) {
                Write-Host ""
                Write-SuccessMessage "Alias '$selectedAlias' is now available in this PowerShell session"

                # Automatically persist alias to profile
                if ($PersistAlias) {
                    Write-Host ""
                    Write-Host "Persisting alias to PowerShell profile..." -ForegroundColor Cyan

                    # Determine target function name
                    $targetCmd = Get-Command -Name "Start-$normalizedModuleName" -ErrorAction SilentlyContinue
                    if ($null -eq $targetCmd) {
                        # Fallback to imported module's first function
                        $mod = Import-Module -Name $normalizedModuleName -PassThru -ErrorAction SilentlyContinue
                        if ($mod -and $mod.ExportedFunctions -and $mod.ExportedFunctions.Keys.Count -gt 0) {
                            $targetFunction = $mod.ExportedFunctions.Keys | Select-Object -First 1
                        }
                        else {
                            $targetFunction = "Start-$normalizedModuleName"
                        }
                    }
                    else {
                        $targetFunction = $targetCmd.Name
                    }

                    $profileUpdated = Add-AliasToProfile -AliasName $selectedAlias -TargetCommand $targetFunction

                    if ($profileUpdated) {
                        Write-Host ""
                        Write-SuccessMessage "Alias persisted! It will be available in all future PowerShell sessions."
                        Write-InfoMessage "Profile location: $PROFILE"
                    }
                    else {
                        Write-Host ""
                        Write-WarningMessage "Alias created in current session, but could not update profile automatically"
                        Write-Host "To persist manually, add this line to your profile:" -ForegroundColor Gray
                        Write-Host "  Set-Alias $selectedAlias $targetFunction" -ForegroundColor Yellow
                        Write-Host ""
                        Write-Host "Edit profile: " -ForegroundColor Gray -NoNewline
                        Write-Host "notepad `$PROFILE" -ForegroundColor Yellow
                    }
                }
                else {
                    Write-Host ""
                    Write-InfoMessage "Alias created in current session only (not persisted to profile)"
                    Write-Host "To make it permanent, add this line to your PowerShell profile:" -ForegroundColor Gray
                    Write-Host "  Set-Alias $selectedAlias Start-$normalizedModuleName" -ForegroundColor Yellow
                }
            }
        }
    }

    # ============================================================================
    # Final success message
    # ============================================================================

    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Green
    Write-SuccessMessage "Installation Complete!"
    Write-Host "================================================================================" -ForegroundColor Green
    Write-Host ""

    exit 0
}
catch {
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Red
    Write-ErrorMessage "Installation Failed"
    Write-Host "================================================================================" -ForegroundColor Red
    Write-Host ""
    Write-ErrorMessage $_.Exception.Message
    Write-Host ""

    if ($_.Exception.InnerException) {
        Write-Host "Inner Exception:" -ForegroundColor Red
        Write-Host $_.Exception.InnerException.Message -ForegroundColor Red
        Write-Host ""
    }

    exit 1
}
finally {
    # Restore preferences
    $ProgressPreference = 'Continue'
}

#endregion
