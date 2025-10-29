@{
    # Module Info
    ModuleVersion = '1.0.0'
    GUID = '8f4e6c3a-1d2b-4e5f-9a7c-3d8e6b1f4a2c'
    Author = 'DevJessParker'
    Description = 'Employee reference scanner for finding employee names, emails, and potential secrets in codebases'

    # Module Components
    RootModule = 'IGScan.psm1'
    PowerShellVersion = '5.1'

    # Exports
    FunctionsToExport = @('Invoke-EmployeeRefScan')
    AliasesToExport = @('igscan')
    CmdletsToExport = @()
    VariablesToExport = @()

    # Private Data
    PrivateData = @{
        PSData = @{
            Tags = @('Security', 'Scanning', 'Employee', 'Secrets')
        }
    }
}
