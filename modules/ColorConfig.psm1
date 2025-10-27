#Requires -Version 5.1

<#
.SYNOPSIS
    Terminal color configuration module for consistent output formatting
.DESCRIPTION
    Provides standardized color schemes and output functions for installation scripts.
    Automatically detects TeamCity CI environment and uses service messages for enhanced log formatting.
#>

# Color scheme configuration
$Script:ColorScheme = @{
    Success      = 'Green'
    Error        = 'Red'
    Warning      = 'Yellow'
    Info         = 'Cyan'
    Progress     = 'Magenta'
    Header       = 'White'
    Subtle       = 'DarkGray'
    Highlight    = 'Blue'
    Prompt       = 'Yellow'
}

# TeamCity environment detection
$Script:IsTeamCity = [bool]$env:TEAMCITY_VERSION

# Track open TeamCity blocks for proper nesting
$Script:TeamCityBlockStack = New-Object System.Collections.Generic.Stack[string]

function Test-TeamCityEnvironment {
    <#
    .SYNOPSIS
        Checks if the script is running in TeamCity CI environment
    .DESCRIPTION
        Returns true if TEAMCITY_VERSION environment variable is set
    .OUTPUTS
        Boolean indicating if running in TeamCity
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    return $Script:IsTeamCity
}

function Write-TeamCityMessage {
    <#
    .SYNOPSIS
        Writes a TeamCity service message
    .DESCRIPTION
        Formats and outputs TeamCity service messages with proper escaping
    .PARAMETER MessageType
        Type of TeamCity message (message, buildProblem, blockOpened, blockClosed, etc.)
    .PARAMETER Attributes
        Hashtable of attributes for the service message
    .EXAMPLE
        Write-TeamCityMessage -MessageType "message" -Attributes @{ text="Success"; status="NORMAL" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MessageType,

        [Parameter(Mandatory = $true)]
        [hashtable]$Attributes
    )

    # Escape special characters for TeamCity service messages
    $escapedAttrs = @{}
    foreach ($key in $Attributes.Keys) {
        $value = $Attributes[$key].ToString()
        # Escape |, ', [, ], and newlines according to TeamCity spec
        $value = $value -replace '\|', '||'
        $value = $value -replace "'", "|'"
        $value = $value -replace '\[', '|['
        $value = $value -replace '\]', '|]'
        $value = $value -replace "`r", '|r'
        $value = $value -replace "`n", '|n'
        $escapedAttrs[$key] = $value
    }

    # Build service message
    $attrString = ($escapedAttrs.GetEnumerator() | ForEach-Object { "$($_.Key)='$($_.Value)'" }) -join ' '
    Write-Output "##teamcity[$MessageType $attrString]"
}

function Open-TeamCityBlock {
    <#
    .SYNOPSIS
        Opens a collapsible block in TeamCity build log
    .PARAMETER Name
        Name of the block to open
    .PARAMETER Description
        Optional description for the block
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$Description
    )

    if (Test-TeamCityEnvironment) {
        $attrs = @{ name = $Name }
        if ($Description) {
            $attrs['description'] = $Description
        }
        Write-TeamCityMessage -MessageType "blockOpened" -Attributes $attrs
        $Script:TeamCityBlockStack.Push($Name)
    }
}

function Close-TeamCityBlock {
    <#
    .SYNOPSIS
        Closes the most recently opened TeamCity block
    .PARAMETER Name
        Name of the block to close (must match the most recent Open-TeamCityBlock)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (Test-TeamCityEnvironment) {
        if ($Script:TeamCityBlockStack.Count -gt 0) {
            $expectedName = $Script:TeamCityBlockStack.Pop()
            if ($expectedName -ne $Name) {
                Write-Warning "TeamCity block mismatch: expected '$expectedName', got '$Name'"
            }
        }
        Write-TeamCityMessage -MessageType "blockClosed" -Attributes @{ name = $Name }
    }
}

function Write-ColorOutput {
    <#
    .SYNOPSIS
        Writes colored output to the console
    .DESCRIPTION
        Outputs text with specified color, compatible with PS 5.1+
    .PARAMETER Message
        The message to write
    .PARAMETER Color
        The color to use for the message
    .PARAMETER NoNewline
        Don't add a newline after the message
    .EXAMPLE
        Write-ColorOutput -Message "Success!" -Color Green
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [System.ConsoleColor]$Color = [System.ConsoleColor]::White,

        [Parameter(Mandatory = $false)]
        [switch]$NoNewline
    )

    process {
        $params = @{
            Object       = $Message
            ForegroundColor = $Color
        }

        if ($NoNewline) {
            $params.Add('NoNewline', $true)
        }

        Write-Host @params
    }
}

function Write-SuccessMessage {
    <#
    .SYNOPSIS
        Writes a success message in green (local) or TeamCity service message (CI)
    .PARAMETER Message
        The success message to display
    .EXAMPLE
        Write-SuccessMessage "Installation completed successfully"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowEmptyString()]
        [string]$Message
    )

    process {
        if (Test-TeamCityEnvironment) {
            Write-TeamCityMessage -MessageType "message" -Attributes @{
                text = "SUCCESS: $Message"
                status = "NORMAL"
            }
        }
        else {
            Write-ColorOutput -Message "SUCCESS: $Message" -Color $Script:ColorScheme.Success
        }
    }
}

function Write-ErrorMessage {
    <#
    .SYNOPSIS
        Writes an error message in red (local) or TeamCity error message (CI)
    .PARAMETER Message
        The error message to display
    .EXAMPLE
        Write-ErrorMessage "Installation failed"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowEmptyString()]
        [string]$Message
    )

    process {
        if (Test-TeamCityEnvironment) {
            Write-TeamCityMessage -MessageType "message" -Attributes @{
                text = "ERROR: $Message"
                status = "ERROR"
                errorDetails = $Message
            }
        }
        else {
            Write-ColorOutput -Message "ERROR: $Message" -Color $Script:ColorScheme.Error
        }
    }
}

function Write-WarningMessage {
    <#
    .SYNOPSIS
        Writes a warning message in yellow (local) or TeamCity warning message (CI)
    .PARAMETER Message
        The warning message to display
    .EXAMPLE
        Write-WarningMessage "Version mismatch detected"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowEmptyString()]
        [string]$Message
    )

    process {
        if (Test-TeamCityEnvironment) {
            Write-TeamCityMessage -MessageType "message" -Attributes @{
                text = "WARNING: $Message"
                status = "WARNING"
            }
        }
        else {
            Write-ColorOutput -Message "WARNING: $Message" -Color $Script:ColorScheme.Warning
        }
    }
}

function Write-InfoMessage {
    <#
    .SYNOPSIS
        Writes an informational message in cyan (local) or TeamCity info message (CI)
    .PARAMETER Message
        The info message to display
    .EXAMPLE
        Write-InfoMessage "Checking system requirements"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowEmptyString()]
        [string]$Message
    )

    process {
        if (Test-TeamCityEnvironment) {
            # TeamCity info messages use NORMAL status
            Write-TeamCityMessage -MessageType "message" -Attributes @{
                text = "INFO: $Message"
                status = "NORMAL"
            }
        }
        else {
            Write-ColorOutput -Message "INFO: $Message" -Color $Script:ColorScheme.Info
        }
    }
}

function Write-ProgressMessage {
    <#
    .SYNOPSIS
        Writes a progress message in magenta (local) or TeamCity progress message (CI)
    .PARAMETER Message
        The progress message to display
    .EXAMPLE
        Write-ProgressMessage "Installing Node.js 18.19.1"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowEmptyString()]
        [string]$Message
    )

    process {
        if (Test-TeamCityEnvironment) {
            Write-TeamCityMessage -MessageType "progressMessage" -Attributes @{
                text = $Message
            }
        }
        else {
            Write-ColorOutput -Message "[PROGRESS] $Message" -Color $Script:ColorScheme.Progress
        }
    }
}

function Write-HeaderMessage {
    <#
    .SYNOPSIS
        Writes a header message with decorative borders (local) or TeamCity block (CI)
    .PARAMETER Message
        The header message to display
    .PARAMETER Width
        Width of the header box (default: 80) - ignored in TeamCity
    .EXAMPLE
        Write-HeaderMessage "Development Environment Setup"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [int]$Width = 80
    )

    if (Test-TeamCityEnvironment) {
        # Use TeamCity block for headers (collapsible sections)
        Open-TeamCityBlock -Name $Message
    }
    else {
        $border = '=' * $Width
        $padding = ' ' * [Math]::Max(0, [Math]::Floor(($Width - $Message.Length) / 2) - 1)

        Write-ColorOutput -Message "`n$border" -Color $Script:ColorScheme.Header
        Write-ColorOutput -Message "$padding$Message" -Color $Script:ColorScheme.Header
        Write-ColorOutput -Message "$border`n" -Color $Script:ColorScheme.Header
    }
}

function Write-SectionHeader {
    <#
    .SYNOPSIS
        Writes a section header with subtle borders (local) or TeamCity sub-block (CI)
    .PARAMETER Message
        The section header message to display
    .EXAMPLE
        Write-SectionHeader "Installing Development Tools"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (Test-TeamCityEnvironment) {
        # Use TeamCity block for section headers (nested collapsible sections)
        Open-TeamCityBlock -Name $Message
    }
    else {
        $border = '-' * 80
        Write-ColorOutput -Message "`n$border" -Color $Script:ColorScheme.Subtle
        Write-ColorOutput -Message $Message -Color $Script:ColorScheme.Highlight
        Write-ColorOutput -Message "$border" -Color $Script:ColorScheme.Subtle
    }
}

function Write-StepMessage {
    <#
    .SYNOPSIS
        Writes a numbered step message
    .PARAMETER StepNumber
        The step number
    .PARAMETER TotalSteps
        Total number of steps
    .PARAMETER Message
        The step message
    .EXAMPLE
        Write-StepMessage -StepNumber 1 -TotalSteps 5 -Message "Checking prerequisites"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$StepNumber,

        [Parameter(Mandatory = $true)]
        [int]$TotalSteps,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-ColorOutput -Message "`n[$StepNumber/$TotalSteps] " -Color $Script:ColorScheme.Progress -NoNewline
    Write-ColorOutput -Message $Message -Color $Script:ColorScheme.Info
}

function Write-DevSummary {
    <#
    .SYNOPSIS
        Writes a formatted developer summary at the end of script execution
    .PARAMETER Title
        Title of the summary
    .PARAMETER Sections
        Hashtable of sections to display
    .EXAMPLE
        Write-DevSummary -Title "Installation Summary" -Sections @{...}
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [hashtable]$Sections
    )

    Write-HeaderMessage -Message $Title

    foreach ($section in $Sections.GetEnumerator()) {
        if (Test-TeamCityEnvironment) {
            Write-Output "`n$($section.Key):"
        }
        else {
            Write-ColorOutput -Message "`n$($section.Key):" -Color $Script:ColorScheme.Highlight
        }

        if ($section.Value -is [array]) {
            foreach ($item in $section.Value) {
                if (Test-TeamCityEnvironment) {
                    Write-Output "  - $item"
                }
                else {
                    Write-ColorOutput -Message "  - $item" -Color $Script:ColorScheme.Info
                }
            }
        }
        else {
            if (Test-TeamCityEnvironment) {
                Write-Output "  $($section.Value)"
            }
            else {
                Write-ColorOutput -Message "  $($section.Value)" -Color $Script:ColorScheme.Info
            }
        }
    }

    if (Test-TeamCityEnvironment) {
        # Close the block opened by Write-HeaderMessage
        Close-TeamCityBlock -Name $Title
    }
    else {
        Write-ColorOutput -Message "`n$('=' * 80)`n" -Color $Script:ColorScheme.Header
    }
}

# Export module members
Export-ModuleMember -Function Write-ColorOutput, Write-SuccessMessage, Write-ErrorMessage,
                              Write-WarningMessage, Write-InfoMessage, Write-ProgressMessage,
                              Write-HeaderMessage, Write-SectionHeader, Write-StepMessage,
                              Write-DevSummary, Test-TeamCityEnvironment, Write-TeamCityMessage,
                              Open-TeamCityBlock, Close-TeamCityBlock
Export-ModuleMember -Variable ColorScheme
