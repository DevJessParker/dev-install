#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs Docker CE (Community Edition) for CI/CD environments
.DESCRIPTION
    Installs Docker CE on Windows Server for use in CI/CD pipelines (TeamCity, Jenkins, etc.)
    This is the lightweight Docker Engine without Docker Desktop GUI.

    NOTE: This script is designed for Windows Server environments, not Windows 10/11 Desktop.
    For desktop environments, use Docker Desktop via Chocolatey instead.
.EXAMPLE
    .\install-docker-ce.ps1
.NOTES
    - Requires Windows Server 2016 or later
    - Requires administrator privileges
    - Requires Hyper-V or Containers Windows feature
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Import required modules
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath ".." | Join-Path -ChildPath "modules"
Import-Module (Join-Path -Path $modulePath -ChildPath "ColorConfig.psm1") -Force
Import-Module (Join-Path -Path $modulePath -ChildPath "ErrorHandling.psm1") -Force

Write-HeaderMessage "Docker CE Installation for CI/CD"

# Check if running on Windows Server
$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
$isServer = $osInfo.ProductType -ne 1  # 1 = Workstation, 2 = Domain Controller, 3 = Server

if (-not $isServer) {
    Write-WarningMessage "This script is designed for Windows Server environments."
    Write-WarningMessage "Detected: $($osInfo.Caption)"
    Write-WarningMessage "For Windows 10/11 Desktop, use Docker Desktop instead."
    Write-Host ""
    $response = Read-Host "Continue anyway? (Y/N)"
    if ($response -notmatch '^[Yy]') {
        Write-InfoMessage "Installation cancelled."
        exit 0
    }
}

try {
    # Check if Docker is already installed
    $dockerService = Get-Service -Name docker -ErrorAction SilentlyContinue
    $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue

    if ($dockerService -and $dockerCmd) {
        $dockerVersion = docker --version 2>$null
        Write-SuccessMessage "Docker is already installed: $dockerVersion"

        # Ensure service is running
        if ($dockerService.Status -ne 'Running') {
            Write-InfoMessage "Starting Docker service..."
            Start-Service -Name docker
            Write-SuccessMessage "Docker service started"
        }

        exit 0
    }

    Write-InfoMessage "Docker CE not found. Beginning installation..."

    # Step 1: Check Windows version
    Write-ProgressMessage "Checking Windows version..."
    $windowsVersion = [System.Environment]::OSVersion.Version
    if ($windowsVersion.Major -lt 10) {
        Write-ErrorLog -Message "Docker CE requires Windows Server 2016 or later (Windows 10.0+)" -Fatal
        exit 1
    }
    Write-SuccessMessage "Windows version check passed: $($osInfo.Caption)"

    # Step 2: Enable Containers feature
    Write-ProgressMessage "Checking Containers Windows feature..."
    $containersFeature = Get-WindowsOptionalFeature -Online -FeatureName Containers -ErrorAction SilentlyContinue

    if (-not $containersFeature -or $containersFeature.State -ne 'Enabled') {
        Write-InfoMessage "Enabling Containers Windows feature..."
        Enable-WindowsOptionalFeature -Online -FeatureName Containers -All -NoRestart
        Write-SuccessMessage "Containers feature enabled (restart may be required)"
        $restartRequired = $true
    }
    else {
        Write-SuccessMessage "Containers feature is already enabled"
    }

    # Step 3: Install Docker via PowerShell provider
    Write-ProgressMessage "Installing Docker CE..."

    # Install DockerMsftProvider module if not present
    if (-not (Get-Module -ListAvailable -Name DockerMsftProvider)) {
        Write-InfoMessage "Installing DockerMsftProvider module..."
        Install-Module -Name DockerMsftProvider -Repository PSGallery -Force
        Write-SuccessMessage "DockerMsftProvider module installed"
    }

    # Install Docker package
    Write-InfoMessage "Installing Docker package (this may take several minutes)..."
    Install-Package -Name docker -ProviderName DockerMsftProvider -Force -ErrorAction Stop
    Write-SuccessMessage "Docker CE package installed"

    # Step 4: Start Docker service
    Write-ProgressMessage "Starting Docker service..."
    Start-Service -Name docker
    Write-SuccessMessage "Docker service started"

    # Step 5: Verify installation
    Write-ProgressMessage "Verifying Docker installation..."
    $dockerVersion = docker --version 2>$null
    if ($dockerVersion) {
        Write-SuccessMessage "Docker CE installed successfully: $dockerVersion"
    }
    else {
        Write-ErrorLog -Message "Docker installation verification failed" -Fatal
        exit 1
    }

    # Step 6: Test Docker with hello-world (optional)
    Write-ProgressMessage "Testing Docker with hello-world container..."
    try {
        docker run --rm hello-world 2>$null | Out-Null
        Write-SuccessMessage "Docker hello-world test passed"
    }
    catch {
        Write-WarningLog "Docker hello-world test failed, but Docker is installed. This is normal in some CI environments."
    }

    # Check if restart is required
    if ($restartRequired) {
        Write-Host ""
        Write-WarningMessage "A system restart is required to complete the installation."
        Write-WarningMessage "Please restart the system and verify Docker is running."
    }

    Write-Host ""
    Write-HeaderMessage "Docker CE Installation Complete"
    Write-SuccessMessage "Docker is ready to use in CI/CD pipelines"

    exit 0
}
catch {
    Write-ErrorLog -Message "Docker CE installation failed" -Exception $_.Exception -Fatal
    exit 1
}
