#Requires -Version 5.1

<#
.SYNOPSIS
    System requirements checking module for installation scripts
.DESCRIPTION
    Provides functions to check OS version, hardware specifications, and system requirements
.NOTES
    This module requires ColorConfig and ErrorHandling modules to be imported
    before using its functions in your scripts.
#>

function Get-SystemInformation {
    <#
    .SYNOPSIS
        Retrieves comprehensive system information
    .DESCRIPTION
        Gathers OS version, hardware specs, and other system details
    .EXAMPLE
        Get-SystemInformation
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop

        $systemInfo = @{
            OSName               = $os.Caption
            OSVersion            = $os.Version
            OSArchitecture       = $os.OSArchitecture
            BuildNumber          = $os.BuildNumber
            TotalRAM_GB          = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
            FreeRAM_GB           = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
            ProcessorName        = $cpu.Name
            ProcessorCores       = $cpu.NumberOfCores
            ProcessorThreads     = $cpu.NumberOfLogicalProcessors
            DiskTotal_GB         = [math]::Round($disk.Size / 1GB, 2)
            DiskFree_GB          = [math]::Round($disk.FreeSpace / 1GB, 2)
            PowerShellVersion    = $PSVersionTable.PSVersion.ToString()
            PowerShellEdition    = $PSVersionTable.PSEdition
            ExecutionPolicy      = (Get-ExecutionPolicy).ToString()
            ComputerName         = $env:COMPUTERNAME
            UserName             = $env:USERNAME
        }

        return $systemInfo
    }
    catch {
        Write-ErrorLog -Message "Failed to retrieve system information" -Exception $_.Exception -Fatal
        return $null
    }
}

function Show-SystemInformation {
    <#
    .SYNOPSIS
        Displays formatted system information
    .PARAMETER SystemInfo
        System information hashtable from Get-SystemInformation
    .EXAMPLE
        Show-SystemInformation -SystemInfo (Get-SystemInformation)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$SystemInfo
    )

    Write-SectionHeader "System Information"

    Write-InfoMessage "Operating System"
    Write-ColorOutput "  OS: $($SystemInfo.OSName)" -Color White
    Write-ColorOutput "  Version: $($SystemInfo.OSVersion) (Build $($SystemInfo.BuildNumber))" -Color White
    Write-ColorOutput "  Architecture: $($SystemInfo.OSArchitecture)" -Color White

    Write-InfoMessage "`nHardware"
    Write-ColorOutput "  Processor: $($SystemInfo.ProcessorName)" -Color White
    Write-ColorOutput "  Cores: $($SystemInfo.ProcessorCores) (Threads: $($SystemInfo.ProcessorThreads))" -Color White
    Write-ColorOutput "  RAM: $($SystemInfo.TotalRAM_GB) GB (Free: $($SystemInfo.FreeRAM_GB) GB)" -Color White
    Write-ColorOutput "  Disk C: $($SystemInfo.DiskTotal_GB) GB (Free: $($SystemInfo.DiskFree_GB) GB)" -Color White

    Write-InfoMessage "`nPowerShell Environment"
    Write-ColorOutput "  Version: $($SystemInfo.PowerShellVersion)" -Color White
    Write-ColorOutput "  Edition: $($SystemInfo.PowerShellEdition)" -Color White
    Write-ColorOutput "  Execution Policy: $($SystemInfo.ExecutionPolicy)" -Color White
}

function Test-WindowsVersion {
    <#
    .SYNOPSIS
        Checks if Windows version meets minimum requirements
    .PARAMETER MinimumVersion
        Minimum required Windows version (default: 10.0.0.0)
    .EXAMPLE
        Test-WindowsVersion -MinimumVersion "10.0.0.0"
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [version]$MinimumVersion = "10.0.0.0"
    )

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $currentVersion = [version]$os.Version

        if ($currentVersion -ge $MinimumVersion) {
            Write-SuccessMessage "Windows version check passed: $currentVersion >= $MinimumVersion"
            return $true
        }
        else {
            Write-ErrorLog -Message "Windows version $currentVersion does not meet minimum requirement: $MinimumVersion" -Fatal
            return $false
        }
    }
    catch {
        Write-ErrorLog -Message "Failed to check Windows version" -Exception $_.Exception -Fatal
        return $false
    }
}

function Test-PowerShellVersion {
    <#
    .SYNOPSIS
        Checks if PowerShell version meets minimum requirements
    .PARAMETER MinimumVersion
        Minimum required PowerShell version (default: 5.1)
    .EXAMPLE
        Test-PowerShellVersion -MinimumVersion "5.1"
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [version]$MinimumVersion = "5.1"
    )

    $currentVersion = $PSVersionTable.PSVersion

    if ($currentVersion -ge $MinimumVersion) {
        Write-SuccessMessage "PowerShell version check passed: $currentVersion >= $MinimumVersion"
        return $true
    }
    else {
        Write-ErrorLog -Message "PowerShell version $currentVersion does not meet minimum requirement: $MinimumVersion" -Fatal
        return $false
    }
}

function Test-AvailableRAM {
    <#
    .SYNOPSIS
        Checks if system has sufficient RAM
    .PARAMETER MinimumRAM_GB
        Minimum required RAM in GB (default: 8)
    .EXAMPLE
        Test-AvailableRAM -MinimumRAM_GB 8
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [int]$MinimumRAM_GB = 8
    )

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $totalRAM_GB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)

        if ($totalRAM_GB -ge $MinimumRAM_GB) {
            Write-SuccessMessage "RAM check passed: $totalRAM_GB GB >= $MinimumRAM_GB GB"
            return $true
        }
        else {
            Write-WarningLog "System has $totalRAM_GB GB RAM, which is less than recommended $MinimumRAM_GB GB"
            return $false
        }
    }
    catch {
        Write-ErrorLog -Message "Failed to check available RAM" -Exception $_.Exception
        return $false
    }
}

function Test-AvailableDiskSpace {
    <#
    .SYNOPSIS
        Checks if system has sufficient disk space
    .PARAMETER MinimumDiskSpace_GB
        Minimum required disk space in GB (default: 50)
    .PARAMETER DriveLetter
        Drive letter to check (default: C)
    .EXAMPLE
        Test-AvailableDiskSpace -MinimumDiskSpace_GB 50
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [int]$MinimumDiskSpace_GB = 50,

        [Parameter(Mandatory = $false)]
        [string]$DriveLetter = "C"
    )

    try {
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='${DriveLetter}:'"
        $freeSpace_GB = [math]::Round($disk.FreeSpace / 1GB, 2)

        if ($freeSpace_GB -ge $MinimumDiskSpace_GB) {
            Write-SuccessMessage "Disk space check passed: $freeSpace_GB GB >= $MinimumDiskSpace_GB GB"
            return $true
        }
        else {
            Write-WarningLog "Drive ${DriveLetter}: has $freeSpace_GB GB free, which is less than recommended $MinimumDiskSpace_GB GB"
            return $false
        }
    }
    catch {
        Write-ErrorLog -Message "Failed to check available disk space" -Exception $_.Exception
        return $false
    }
}

function Test-SystemRequirements {
    <#
    .SYNOPSIS
        Performs comprehensive system requirements check
    .PARAMETER ConfigPath
        Path to configuration file with system requirements
    .EXAMPLE
        Test-SystemRequirements -ConfigPath ".\config\tools-config.json"
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath
    )

    Write-SectionHeader "Checking System Requirements"

    $allChecksPassed = $true

    # Default requirements
    $minWindowsVersion = [version]"10.0.0.0"
    $minPowerShellVersion = [version]"5.1"
    $minRAM_GB = 8
    $minDiskSpace_GB = 50

    # Load custom requirements if config provided
    if ($ConfigPath -and (Test-Path $ConfigPath)) {
        try {
            $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
            if ($config.systemRequirements) {
                if ($config.systemRequirements.minimumWindowsVersion) {
                    $minWindowsVersion = [version]$config.systemRequirements.minimumWindowsVersion
                }
                if ($config.systemRequirements.minimumPowerShellVersion) {
                    $minPowerShellVersion = [version]$config.systemRequirements.minimumPowerShellVersion
                }
                if ($config.systemRequirements.minimumRAM_GB) {
                    $minRAM_GB = $config.systemRequirements.minimumRAM_GB
                }
                if ($config.systemRequirements.minimumDiskSpace_GB) {
                    $minDiskSpace_GB = $config.systemRequirements.minimumDiskSpace_GB
                }
            }
        }
        catch {
            Write-WarningLog "Failed to load system requirements from config, using defaults"
        }
    }

    # Perform checks
    $allChecksPassed = $allChecksPassed -and (Test-WindowsVersion -MinimumVersion $minWindowsVersion)
    $allChecksPassed = $allChecksPassed -and (Test-PowerShellVersion -MinimumVersion $minPowerShellVersion)

    # RAM and disk space are warnings, not fatal
    Test-AvailableRAM -MinimumRAM_GB $minRAM_GB | Out-Null
    Test-AvailableDiskSpace -MinimumDiskSpace_GB $minDiskSpace_GB | Out-Null

    if ($allChecksPassed) {
        Write-SuccessMessage "All critical system requirements checks passed"
    }
    else {
        Write-ErrorLog -Message "System requirements check failed" -Fatal
    }

    return $allChecksPassed
}

function Test-InternetConnection {
    <#
    .SYNOPSIS
        Tests internet connectivity
    .EXAMPLE
        Test-InternetConnection
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        Write-ProgressMessage "Testing internet connectivity..."

        $testConnection = Test-Connection -ComputerName "8.8.8.8" -Count 2 -Quiet -ErrorAction Stop

        if ($testConnection) {
            Write-SuccessMessage "Internet connection verified"
            return $true
        }
        else {
            Write-WarningLog "Internet connection test failed"
            return $false
        }
    }
    catch {
        Write-WarningLog "Unable to verify internet connection: $($_.Exception.Message)"
        return $false
    }
}

# Export module members
Export-ModuleMember -Function Get-SystemInformation, Show-SystemInformation,
                              Test-WindowsVersion, Test-PowerShellVersion,
                              Test-AvailableRAM, Test-AvailableDiskSpace,
                              Test-SystemRequirements, Test-InternetConnection
