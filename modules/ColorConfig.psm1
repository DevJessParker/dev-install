#Requires -Version 5.1

<#
.SYNOPSIS
    Terminal color configuration module for consistent output formatting
.DESCRIPTION
    Provides standardized color schemes and output functions for installation scripts
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
        Writes a success message in green
    .PARAMETER Message
        The success message to display
    .EXAMPLE
        Write-SuccessMessage "Installation completed successfully"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Message
    )

    process {
        Write-ColorOutput -Message "SUCCESS: $Message" -Color $Script:ColorScheme.Success
    }
}

function Write-ErrorMessage {
    <#
    .SYNOPSIS
        Writes an error message in red
    .PARAMETER Message
        The error message to display
    .EXAMPLE
        Write-ErrorMessage "Installation failed"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Message
    )

    process {
        Write-ColorOutput -Message "ERROR: $Message" -Color $Script:ColorScheme.Error
    }
}

function Write-WarningMessage {
    <#
    .SYNOPSIS
        Writes a warning message in yellow
    .PARAMETER Message
        The warning message to display
    .EXAMPLE
        Write-WarningMessage "Version mismatch detected"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Message
    )

    process {
        Write-ColorOutput -Message "WARNING: $Message" -Color $Script:ColorScheme.Warning
    }
}

function Write-InfoMessage {
    <#
    .SYNOPSIS
        Writes an informational message in cyan
    .PARAMETER Message
        The info message to display
    .EXAMPLE
        Write-InfoMessage "Checking system requirements"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Message
    )

    process {
        Write-ColorOutput -Message "INFO: $Message" -Color $Script:ColorScheme.Info
    }
}

function Write-ProgressMessage {
    <#
    .SYNOPSIS
        Writes a progress message in magenta
    .PARAMETER Message
        The progress message to display
    .EXAMPLE
        Write-ProgressMessage "Installing Node.js 18.19.1"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Message
    )

    process {
        Write-ColorOutput -Message "[PROGRESS] $Message" -Color $Script:ColorScheme.Progress
    }
}

function Write-HeaderMessage {
    <#
    .SYNOPSIS
        Writes a header message with decorative borders
    .PARAMETER Message
        The header message to display
    .PARAMETER Width
        Width of the header box (default: 80)
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

    $border = '=' * $Width
    $padding = ' ' * [Math]::Max(0, [Math]::Floor(($Width - $Message.Length) / 2) - 1)

    Write-ColorOutput -Message "`n$border" -Color $Script:ColorScheme.Header
    Write-ColorOutput -Message "$padding$Message" -Color $Script:ColorScheme.Header
    Write-ColorOutput -Message "$border`n" -Color $Script:ColorScheme.Header
}

function Write-SectionHeader {
    <#
    .SYNOPSIS
        Writes a section header with subtle borders
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

    $border = '-' * 80
    Write-ColorOutput -Message "`n$border" -Color $Script:ColorScheme.Subtle
    Write-ColorOutput -Message $Message -Color $Script:ColorScheme.Highlight
    Write-ColorOutput -Message "$border" -Color $Script:ColorScheme.Subtle
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
        Write-ColorOutput -Message "`n$($section.Key):" -Color $Script:ColorScheme.Highlight

        if ($section.Value -is [array]) {
            foreach ($item in $section.Value) {
                Write-ColorOutput -Message "  - $item" -Color $Script:ColorScheme.Info
            }
        }
        else {
            Write-ColorOutput -Message "  $($section.Value)" -Color $Script:ColorScheme.Info
        }
    }

    Write-ColorOutput -Message "`n$('=' * 80)`n" -Color $Script:ColorScheme.Header
}

# Export module members
Export-ModuleMember -Function Write-ColorOutput, Write-SuccessMessage, Write-ErrorMessage,
                              Write-WarningMessage, Write-InfoMessage, Write-ProgressMessage,
                              Write-HeaderMessage, Write-SectionHeader, Write-StepMessage,
                              Write-DevSummary
Export-ModuleMember -Variable ColorScheme
