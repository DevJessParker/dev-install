#Requires -Version 5.1

<#
.SYNOPSIS
    Test script to validate TeamCity service message formatting
.DESCRIPTION
    Simulates TeamCity environment and tests the ColorConfig module's TeamCity integration
#>

# Set TeamCity environment variable to simulate CI
$env:TEAMCITY_VERSION = "2023.11"

# Import the ColorConfig module
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath "modules"
Import-Module (Join-Path -Path $modulePath -ChildPath "ColorConfig.psm1") -Force

Write-Host "`n=== TeamCity Service Message Test ==="
Write-Host "Environment: TEAMCITY_VERSION = $env:TEAMCITY_VERSION"
Write-Host "Is TeamCity: $(Test-TeamCityEnvironment)"
Write-Host ""

# Test basic messages
Write-Host "--- Testing Basic Messages ---"
Write-SuccessMessage "Installation completed successfully"
Write-ErrorMessage "Failed to install package"
Write-WarningMessage "Version mismatch detected"
Write-InfoMessage "Checking system requirements"
Write-ProgressMessage "Installing Node.js 18.19.1"

# Test blocks
Write-Host "`n--- Testing Blocks ---"
Write-HeaderMessage "Development Tools Installation"
Write-InfoMessage "Inside main header block"

Open-TeamCityBlock -Name "Wave 1" -Description "Installing bootstrap tools"
Write-InfoMessage "Installing chocolatey"
Write-SuccessMessage "Chocolatey installed"
Close-TeamCityBlock -Name "Wave 1"

Open-TeamCityBlock -Name "Wave 2" -Description "Installing development tools"
Write-InfoMessage "Installing git"
Write-WarningMessage "Git already installed, skipping"
Close-TeamCityBlock -Name "Wave 2"

# Test section blocks
Write-SectionHeader "Installed Tools"
Write-InfoMessage "Tool: Node.js v18.19.1"
Write-InfoMessage "Tool: Yarn v1.22.22"
Close-TeamCityBlock -Name "Installed Tools"

Write-SectionHeader "Failed Tools"
Write-ErrorMessage "Tool: AWS CLI - Network timeout"
Close-TeamCityBlock -Name "Failed Tools"

# Close main header
Close-TeamCityBlock -Name "Development Tools Installation"

Write-Host "`n--- Test Complete ---"
Write-Host "Review the output above to verify TeamCity service messages are formatted correctly"
Write-Host "Expected format: ##teamcity[messageType attribute='value']`n"

# Clean up
Remove-Item Env:\TEAMCITY_VERSION
