#Requires -Version 5.1

<#
.SYNOPSIS
    Admin privilege checking module for installation scripts
.DESCRIPTION
    Provides functions to verify administrator privileges and fail-fast if not running as admin
#>

function Test-IsAdmin {
    <#
    .SYNOPSIS
        Checks if the current PowerShell session is running with administrator privileges
    .DESCRIPTION
        Returns $true if running as administrator, $false otherwise
    .EXAMPLE
        Test-IsAdmin
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            # PowerShell Core 6+ compatibility
            $currentPrincipal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
        } else {
            # PowerShell 5.1 compatibility
            $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        }

        return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        Write-Error "Failed to check administrator privileges: $_"
        return $false
    }
}

function Assert-IsAdmin {
    <#
    .SYNOPSIS
        Asserts that the script is running with administrator privileges, exits if not
    .DESCRIPTION
        Checks for admin privileges and terminates the script with an error message if not running as admin
    .PARAMETER ScriptName
        Optional name of the script to include in error messages
    .EXAMPLE
        Assert-IsAdmin -ScriptName "Setup"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ScriptName = "This script"
    )

    if (-not (Test-IsAdmin)) {
        $errorMessage = @"

===============================================================================
ERROR: ADMINISTRATOR PRIVILEGES REQUIRED
===============================================================================

$ScriptName must be run with administrator privileges.

To run as administrator:
1. Right-click on PowerShell
2. Select 'Run as Administrator'
3. Navigate to the script directory
4. Run the script again

===============================================================================
"@
        Write-Error $errorMessage
        exit 1
    }
}

function Get-ElevatedSession {
    <#
    .SYNOPSIS
        Attempts to restart the current script with elevated privileges
    .DESCRIPTION
        Launches a new PowerShell process with administrator privileges
    .PARAMETER ScriptPath
        Path to the script to run elevated
    .PARAMETER Arguments
        Arguments to pass to the elevated script
    .EXAMPLE
        Get-ElevatedSession -ScriptPath ".\setup.ps1"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $false)]
        [string[]]$Arguments = @()
    )

    if (-not (Test-IsAdmin)) {
        try {
            $argumentList = @(
                "-NoProfile"
                "-ExecutionPolicy", "Bypass"
                "-File", "`"$ScriptPath`""
            )

            if ($Arguments.Count -gt 0) {
                $argumentList += $Arguments
            }

            Start-Process powershell.exe -Verb RunAs -ArgumentList $argumentList -Wait
            exit
        }
        catch {
            Write-Error "Failed to elevate session: $_"
            exit 1
        }
    }
}

# Export module members
Export-ModuleMember -Function Test-IsAdmin, Assert-IsAdmin, Get-ElevatedSession
