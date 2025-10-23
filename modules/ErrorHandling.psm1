#Requires -Version 5.1

<#
.SYNOPSIS
    Error handling utilities module for installation scripts
.DESCRIPTION
    Provides standardized error handling, logging, and recovery mechanisms
#>

# Import ColorConfig for consistent output
Import-Module "$PSScriptRoot\ColorConfig.psm1" -Force

# Script-level error log collection
$Script:ErrorLog = @()
$Script:WarningLog = @()

function Initialize-ErrorHandling {
    <#
    .SYNOPSIS
        Initializes error handling for the script
    .DESCRIPTION
        Sets up error action preferences and handlers
    .EXAMPLE
        Initialize-ErrorHandling
    #>
    [CmdletBinding()]
    param()

    $ErrorActionPreference = 'Stop'
    $Script:ErrorLog = @()
    $Script:WarningLog = @()
}

function Write-ErrorLog {
    <#
    .SYNOPSIS
        Logs an error message and adds it to the error log
    .PARAMETER Message
        The error message
    .PARAMETER Exception
        Optional exception object
    .PARAMETER Fatal
        Whether this is a fatal error (will terminate script)
    .EXAMPLE
        Write-ErrorLog -Message "Failed to install package" -Fatal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [System.Exception]$Exception,

        [Parameter(Mandatory = $false)]
        [switch]$Fatal
    )

    $errorEntry = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Message   = $Message
        Exception = if ($Exception) { $Exception.Message } else { $null }
        Fatal     = $Fatal.IsPresent
    }

    $Script:ErrorLog += $errorEntry

    # Display error
    Write-ErrorMessage $Message

    if ($Exception) {
        Write-ColorOutput -Message "Exception Details: $($Exception.Message)" -Color Red
        if ($Exception.InnerException) {
            Write-ColorOutput -Message "Inner Exception: $($Exception.InnerException.Message)" -Color Red
        }
    }

    if ($Fatal) {
        Write-ErrorMessage "Fatal error encountered. Script execution cannot continue."
        Write-ColorOutput -Message "`nError Log Summary:" -Color Red
        Show-ErrorSummary
        exit 1
    }
}

function Write-WarningLog {
    <#
    .SYNOPSIS
        Logs a warning message and adds it to the warning log
    .PARAMETER Message
        The warning message
    .EXAMPLE
        Write-WarningLog -Message "Version mismatch detected"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $warningEntry = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Message   = $Message
    }

    $Script:WarningLog += $warningEntry
    Write-WarningMessage $Message
}

function Invoke-WithRetry {
    <#
    .SYNOPSIS
        Executes a script block with retry logic
    .PARAMETER ScriptBlock
        The script block to execute
    .PARAMETER MaxRetries
        Maximum number of retry attempts (default: 3)
    .PARAMETER RetryDelaySeconds
        Delay between retries in seconds (default: 5)
    .PARAMETER OperationName
        Name of the operation for logging
    .EXAMPLE
        Invoke-WithRetry -ScriptBlock { Install-Package -Name "example" } -OperationName "Package Installation"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 3,

        [Parameter(Mandatory = $false)]
        [int]$RetryDelaySeconds = 5,

        [Parameter(Mandatory = $false)]
        [string]$OperationName = "Operation"
    )

    $attempt = 0
    $success = $false
    $lastError = $null

    while (-not $success -and $attempt -lt $MaxRetries) {
        $attempt++

        try {
            Write-ProgressMessage "$OperationName (Attempt $attempt of $MaxRetries)"
            & $ScriptBlock
            $success = $true
            Write-SuccessMessage "$OperationName completed successfully"
        }
        catch {
            $lastError = $_
            Write-WarningMessage "$OperationName failed on attempt $attempt : $($_.Exception.Message)"

            if ($attempt -lt $MaxRetries) {
                Write-InfoMessage "Retrying in $RetryDelaySeconds seconds..."
                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }
    }

    if (-not $success) {
        Write-ErrorLog -Message "$OperationName failed after $MaxRetries attempts" -Exception $lastError -Fatal
    }

    return $success
}

function Test-LastExitCode {
    <#
    .SYNOPSIS
        Checks the last exit code and throws an error if non-zero
    .PARAMETER OperationName
        Name of the operation that was performed
    .PARAMETER AllowedExitCodes
        Array of exit codes that are considered successful (default: @(0))
    .EXAMPLE
        Test-LastExitCode -OperationName "Chocolatey Installation"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OperationName,

        [Parameter(Mandatory = $false)]
        [int[]]$AllowedExitCodes = @(0)
    )

    if ($LASTEXITCODE -notin $AllowedExitCodes) {
        $errorMsg = "$OperationName failed with exit code: $LASTEXITCODE"
        Write-ErrorLog -Message $errorMsg -Fatal
    }
}

function Show-ErrorSummary {
    <#
    .SYNOPSIS
        Displays a summary of all errors and warnings
    .EXAMPLE
        Show-ErrorSummary
    #>
    [CmdletBinding()]
    param()

    if ($Script:ErrorLog.Count -gt 0) {
        Write-ColorOutput -Message "`nErrors Encountered:" -Color Red
        foreach ($error in $Script:ErrorLog) {
            Write-ColorOutput -Message "  [$($error.Timestamp)] $($error.Message)" -Color Red
            if ($error.Exception) {
                Write-ColorOutput -Message "    Exception: $($error.Exception)" -Color DarkRed
            }
        }
    }

    if ($Script:WarningLog.Count -gt 0) {
        Write-ColorOutput -Message "`nWarnings:" -Color Yellow
        foreach ($warning in $Script:WarningLog) {
            Write-ColorOutput -Message "  [$($warning.Timestamp)] $($warning.Message)" -Color Yellow
        }
    }

    if ($Script:ErrorLog.Count -eq 0 -and $Script:WarningLog.Count -eq 0) {
        Write-SuccessMessage "No errors or warnings encountered"
    }
}

function Get-ErrorLog {
    <#
    .SYNOPSIS
        Returns the current error log
    .EXAMPLE
        Get-ErrorLog
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param()

    return $Script:ErrorLog
}

function Get-WarningLog {
    <#
    .SYNOPSIS
        Returns the current warning log
    .EXAMPLE
        Get-WarningLog
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param()

    return $Script:WarningLog
}

function Clear-ErrorLog {
    <#
    .SYNOPSIS
        Clears the error and warning logs
    .EXAMPLE
        Clear-ErrorLog
    #>
    [CmdletBinding()]
    param()

    $Script:ErrorLog = @()
    $Script:WarningLog = @()
}

function Invoke-SafeCommand {
    <#
    .SYNOPSIS
        Safely executes a command and captures errors
    .PARAMETER Command
        The command to execute
    .PARAMETER Arguments
        Arguments for the command
    .PARAMETER OperationName
        Name of the operation for logging
    .EXAMPLE
        Invoke-SafeCommand -Command "choco" -Arguments @("install", "nodejs") -OperationName "Node.js Installation"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $false)]
        [string[]]$Arguments = @(),

        [Parameter(Mandatory = $true)]
        [string]$OperationName
    )

    try {
        Write-ProgressMessage "Executing: $Command $($Arguments -join ' ')"

        if ($PSVersionTable.PSVersion.Major -ge 6) {
            # PowerShell Core 6+ syntax
            & $Command @Arguments
        }
        else {
            # PowerShell 5.1 compatible syntax
            $argString = $Arguments -join ' '
            if ($argString) {
                & $Command $argString.Split(' ')
            }
            else {
                & $Command
            }
        }

        Test-LastExitCode -OperationName $OperationName
        return $true
    }
    catch {
        Write-ErrorLog -Message "Failed to execute $OperationName" -Exception $_.Exception
        return $false
    }
}

# Initialize error handling
Initialize-ErrorHandling

# Export module members
Export-ModuleMember -Function Initialize-ErrorHandling, Write-ErrorLog, Write-WarningLog,
                              Invoke-WithRetry, Test-LastExitCode, Show-ErrorSummary,
                              Get-ErrorLog, Get-WarningLog, Clear-ErrorLog, Invoke-SafeCommand
