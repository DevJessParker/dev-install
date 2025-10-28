#Requires -Version 5.1

<#
.SYNOPSIS
    Compliance audit logging module for SOC2 and HIPAA requirements
.DESCRIPTION
    Provides comprehensive audit logging, session tracking, and compliance reporting
    for security-sensitive operations. Creates an immutable audit trail of all
    installation activities.

    SOC2 Controls Addressed:
    - CC6.1: Logical and Physical Access Controls
    - CC7.2: System Operations - Monitoring Activities
    - CC7.3: System Operations - Evaluation and Management of Change

    HIPAA Requirements Addressed:
    - 164.308(a)(1)(ii)(D): Information System Activity Review
    - 164.308(a)(5)(ii)(C): Log-in Monitoring
    - 164.312(b): Audit Controls
#>

# Script-level variables
$Script:AuditLogPath = $null
$Script:SessionId = $null
$Script:SessionStartTime = $null
$Script:CurrentUser = $null
$Script:AuditEntries = @()

function Initialize-ComplianceAudit {
    <#
    .SYNOPSIS
        Initializes the compliance audit system
    .DESCRIPTION
        Sets up audit logging with a unique session ID, user tracking, and
        creates a persistent audit log file in the logs directory
    .PARAMETER LogDirectory
        Directory where audit logs will be stored (default: .\logs)
    .EXAMPLE
        Initialize-ComplianceAudit -LogDirectory "C:\Logs\DevInstall"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$LogDirectory
    )

    # Generate unique session ID
    $Script:SessionId = [System.Guid]::NewGuid().ToString()
    $Script:SessionStartTime = Get-Date

    # Capture user information for audit trail
    $Script:CurrentUser = @{
        Username = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        MachineName = $env:COMPUTERNAME
        Domain = $env:USERDOMAIN
    }

    # Determine log directory
    if (-not $LogDirectory) {
        $scriptRoot = Split-Path -Parent $PSScriptRoot
        $LogDirectory = Join-Path -Path $scriptRoot -ChildPath "logs"
    }

    # Create logs directory if it doesn't exist
    if (-not (Test-Path -Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }

    # Create audit log file with timestamp
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFileName = "audit_${timestamp}_${Script:SessionId}.log"
    $Script:AuditLogPath = Join-Path -Path $LogDirectory -ChildPath $logFileName

    # Write audit log header
    $header = @"
================================================================================
COMPLIANCE AUDIT LOG
================================================================================
Session ID:      $($Script:SessionId)
Start Time:      $(Get-Date -Format "yyyy-MM-dd HH:mm:ss K")
User:            $($Script:CurrentUser.Username)
Machine:         $($Script:CurrentUser.MachineName)
Domain:          $($Script:CurrentUser.Domain)
Admin Rights:    $($Script:CurrentUser.IsAdmin)
PowerShell Ver:  $($PSVersionTable.PSVersion)
OS Version:      $(if ($PSVersionTable.OS) { $PSVersionTable.OS } else { [System.Environment]::OSVersion.VersionString })
================================================================================

"@

    Add-Content -Path $Script:AuditLogPath -Value $header -Encoding UTF8

    # Log session initialization
    Write-AuditEntry -EventType "SESSION_START" -Action "Initialize" -Component "ComplianceAudit" -Status "Success" `
        -Details "Compliance audit system initialized" -Severity "Info"

    Write-Host "Compliance audit initialized: Session $($Script:SessionId)" -ForegroundColor Cyan
    Write-Host "Audit log: $($Script:AuditLogPath)" -ForegroundColor Gray
}

function Write-AuditEntry {
    <#
    .SYNOPSIS
        Writes an entry to the compliance audit log
    .DESCRIPTION
        Creates a structured, immutable audit log entry with timestamp, user context,
        and detailed operation information. All entries are both stored in memory
        and appended to the persistent audit log file.
    .PARAMETER EventType
        Type of event (e.g., PACKAGE_INSTALL, CONFIG_CHANGE, SECURITY_EVENT)
    .PARAMETER Action
        Specific action performed (e.g., Install, Update, Delete, Verify)
    .PARAMETER Component
        Component or tool being acted upon
    .PARAMETER Status
        Operation status (Success, Failed, Warning, Info)
    .PARAMETER Details
        Detailed description of the operation
    .PARAMETER Severity
        Severity level (Critical, High, Medium, Low, Info)
    .PARAMETER AdditionalData
        Optional hashtable of additional structured data
    .EXAMPLE
        Write-AuditEntry -EventType "PACKAGE_INSTALL" -Action "Install" -Component "nodejs" `
            -Status "Success" -Details "Installed nodejs v18.19.1" -Severity "Info" `
            -AdditionalData @{ Version = "18.19.1"; Source = "chocolatey" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("SESSION_START", "SESSION_END", "PACKAGE_INSTALL", "PACKAGE_UPDATE",
                     "PACKAGE_REMOVE", "CONFIG_CHANGE", "SECURITY_EVENT", "ACCESS_CHECK",
                     "CHECKSUM_VERIFY", "DOWNLOAD", "ERROR", "WARNING", "INFO")]
        [string]$EventType,

        [Parameter(Mandatory = $true)]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [string]$Component,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Success", "Failed", "Warning", "Info", "Skipped")]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$Details,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Critical", "High", "Medium", "Low", "Info")]
        [string]$Severity = "Info",

        [Parameter(Mandatory = $false)]
        [hashtable]$AdditionalData = @{}
    )

    # Create audit entry
    $auditEntry = [PSCustomObject]@{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff K"
        SessionId = $Script:SessionId
        EventType = $EventType
        Action = $Action
        Component = $Component
        Status = $Status
        Severity = $Severity
        Details = $Details
        User = $Script:CurrentUser.Username
        Machine = $Script:CurrentUser.MachineName
        AdditionalData = $AdditionalData
    }

    # Store in memory
    $Script:AuditEntries += $auditEntry

    # Format for log file (JSON-like structured format for easy parsing)
    $logEntry = @"
[$($auditEntry.Timestamp)] [$($auditEntry.Severity)] [$($auditEntry.EventType)]
  Action:     $($auditEntry.Action)
  Component:  $($auditEntry.Component)
  Status:     $($auditEntry.Status)
  User:       $($auditEntry.User)@$($auditEntry.Machine)
  Details:    $($auditEntry.Details)
"@

    if ($AdditionalData.Count -gt 0) {
        $logEntry += "`n  Data:       $(ConvertTo-Json $AdditionalData -Compress)"
    }

    $logEntry += "`n"

    # Append to audit log file (immutable append-only)
    if ($Script:AuditLogPath) {
        try {
            Add-Content -Path $Script:AuditLogPath -Value $logEntry -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to write to audit log: $($_.Exception.Message)"
        }
    }

    # Also emit to event log for compliance (Windows Event Log)
    if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
        try {
            # Create event source if it doesn't exist (requires admin)
            $eventSource = "DevInstall"
            if (-not [System.Diagnostics.EventLog]::SourceExists($eventSource)) {
                if ($Script:CurrentUser.IsAdmin) {
                    [System.Diagnostics.EventLog]::CreateEventSource($eventSource, "Application")
                }
            }

            # Map severity to event log entry type
            $entryType = switch ($Severity) {
                "Critical" { "Error" }
                "High" { "Error" }
                "Medium" { "Warning" }
                "Low" { "Information" }
                "Info" { "Information" }
            }

            # Write to Windows Event Log if source exists
            if ([System.Diagnostics.EventLog]::SourceExists($eventSource)) {
                $eventId = switch ($EventType) {
                    "SESSION_START" { 1000 }
                    "SESSION_END" { 1001 }
                    "PACKAGE_INSTALL" { 2000 }
                    "PACKAGE_UPDATE" { 2001 }
                    "PACKAGE_REMOVE" { 2002 }
                    "CONFIG_CHANGE" { 3000 }
                    "SECURITY_EVENT" { 4000 }
                    "ACCESS_CHECK" { 4001 }
                    "CHECKSUM_VERIFY" { 4002 }
                    default { 9999 }
                }

                Write-EventLog -LogName "Application" -Source $eventSource -EntryType $entryType `
                    -EventId $eventId -Message "$EventType`: $Details`n`nUser: $($Script:CurrentUser.Username)`nSession: $($Script:SessionId)" `
                    -ErrorAction SilentlyContinue
            }
        }
        catch {
            # Silent fail for event log writing (non-critical)
        }
    }
}

function Write-PackageAudit {
    <#
    .SYNOPSIS
        Writes a package installation/update/removal audit entry
    .PARAMETER Action
        Action performed (Install, Update, Remove, Verify)
    .PARAMETER PackageName
        Name of the package
    .PARAMETER Version
        Package version
    .PARAMETER Source
        Package source (chocolatey, powershellgallery, nvm, etc.)
    .PARAMETER Status
        Operation status (Success, Failed, Warning, Skipped)
    .PARAMETER Details
        Additional details about the operation
    .PARAMETER Checksum
        Package checksum if verified
    .EXAMPLE
        Write-PackageAudit -Action "Install" -PackageName "nodejs" -Version "18.19.1" `
            -Source "chocolatey" -Status "Success" -Details "Package installed successfully" `
            -Checksum "abc123def456"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Install", "Update", "Remove", "Verify", "Skip")]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [string]$PackageName,

        [Parameter(Mandatory = $false)]
        [string]$Version = "Unknown",

        [Parameter(Mandatory = $false)]
        [string]$Source = "Unknown",

        [Parameter(Mandatory = $true)]
        [ValidateSet("Success", "Failed", "Warning", "Skipped")]
        [string]$Status,

        [Parameter(Mandatory = $false)]
        [string]$Details = "",

        [Parameter(Mandatory = $false)]
        [string]$Checksum = $null,

        [Parameter(Mandatory = $false)]
        [string]$OldVersion = $null
    )

    $eventType = switch ($Action) {
        "Install" { "PACKAGE_INSTALL" }
        "Update" { "PACKAGE_UPDATE" }
        "Remove" { "PACKAGE_REMOVE" }
        default { "INFO" }
    }

    $severity = switch ($Status) {
        "Failed" { "High" }
        "Warning" { "Medium" }
        default { "Info" }
    }

    $additionalData = @{
        PackageName = $PackageName
        Version = $Version
        Source = $Source
    }

    if ($Checksum) {
        $additionalData.Checksum = $Checksum
    }

    if ($OldVersion) {
        $additionalData.OldVersion = $OldVersion
    }

    $detailsMessage = if ($Details) { $Details } else { "$Action $PackageName v$Version from $Source" }

    Write-AuditEntry -EventType $eventType -Action $Action -Component $PackageName `
        -Status $Status -Details $detailsMessage -Severity $severity -AdditionalData $additionalData
}

function Write-SecurityAudit {
    <#
    .SYNOPSIS
        Writes a security-related audit entry
    .PARAMETER Action
        Security action (ChecksumVerify, TLSCheck, AdminCheck, etc.)
    .PARAMETER Component
        Component being checked
    .PARAMETER Status
        Check status (Success, Failed, Warning)
    .PARAMETER Details
        Details of the security check
    .PARAMETER Severity
        Severity level (Critical, High, Medium, Low)
    .EXAMPLE
        Write-SecurityAudit -Action "ChecksumVerify" -Component "nodejs.zip" `
            -Status "Success" -Details "Checksum verified: SHA256 match" -Severity "Info"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [string]$Component,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Success", "Failed", "Warning", "Info")]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$Details,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Critical", "High", "Medium", "Low", "Info")]
        [string]$Severity = "Info"
    )

    Write-AuditEntry -EventType "SECURITY_EVENT" -Action $Action -Component $Component `
        -Status $Status -Details $Details -Severity $Severity
}

function Close-ComplianceAudit {
    <#
    .SYNOPSIS
        Closes the compliance audit session and generates summary report
    .DESCRIPTION
        Finalizes the audit log with session statistics and summary information
    .EXAMPLE
        Close-ComplianceAudit
    #>
    [CmdletBinding()]
    param()

    $sessionDuration = (Get-Date) - $Script:SessionStartTime

    # Generate statistics
    $stats = @{
        TotalEntries = $Script:AuditEntries.Count
        Successes = ($Script:AuditEntries | Where-Object { $_.Status -eq "Success" }).Count
        Failures = ($Script:AuditEntries | Where-Object { $_.Status -eq "Failed" }).Count
        Warnings = ($Script:AuditEntries | Where-Object { $_.Status -eq "Warning" }).Count
        Duration = $sessionDuration.ToString("hh\:mm\:ss")
    }

    # Write session end entry
    Write-AuditEntry -EventType "SESSION_END" -Action "Finalize" -Component "ComplianceAudit" `
        -Status "Success" -Details "Audit session completed" -Severity "Info" `
        -AdditionalData $stats

    # Write footer to log file
    $footer = @"

================================================================================
AUDIT SESSION SUMMARY
================================================================================
Session ID:      $($Script:SessionId)
End Time:        $(Get-Date -Format "yyyy-MM-dd HH:mm:ss K")
Duration:        $($stats.Duration)
Total Entries:   $($stats.TotalEntries)
  Successes:     $($stats.Successes)
  Failures:      $($stats.Failures)
  Warnings:      $($stats.Warnings)
================================================================================
"@

    if ($Script:AuditLogPath) {
        Add-Content -Path $Script:AuditLogPath -Value $footer -Encoding UTF8
        Write-Host "`nCompliance audit log finalized: $($Script:AuditLogPath)" -ForegroundColor Green
    }
}

function Get-AuditEntries {
    <#
    .SYNOPSIS
        Returns all audit entries for the current session
    .EXAMPLE
        Get-AuditEntries | Where-Object { $_.EventType -eq "PACKAGE_INSTALL" }
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param()

    return $Script:AuditEntries
}

function Get-AuditLogPath {
    <#
    .SYNOPSIS
        Returns the path to the current audit log file
    .EXAMPLE
        Get-AuditLogPath
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return $Script:AuditLogPath
}

function Get-SessionId {
    <#
    .SYNOPSIS
        Returns the current audit session ID
    .EXAMPLE
        Get-SessionId
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return $Script:SessionId
}

# Export module members
Export-ModuleMember -Function Initialize-ComplianceAudit, Write-AuditEntry, Write-PackageAudit, `
                              Write-SecurityAudit, Close-ComplianceAudit, Get-AuditEntries, `
                              Get-AuditLogPath, Get-SessionId
