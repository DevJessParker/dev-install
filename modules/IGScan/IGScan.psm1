#
# IGScan Module - Employee Reference Scanner
#

# Dot-source the Find-EmployeeRefs script
$ScriptPath = Join-Path $PSScriptRoot "Find-EmployeeRefs.ps1"

# Create a function wrapper to make it callable
function Invoke-EmployeeRefScan {
    [CmdletBinding()]
    param(
        [string]$RootPath,
        [int]$MaxFileSizeMB = 5,
        [string]$Extensions,
        [switch]$IncludeLineNumbers
    )

    # Execute the script with parameters
    & $ScriptPath @PSBoundParameters
}

# Create alias for easier invocation
Set-Alias -Name igscan -Value Invoke-EmployeeRefScan

# Export the function and alias
Export-ModuleMember -Function Invoke-EmployeeRefScan -Alias igscan
