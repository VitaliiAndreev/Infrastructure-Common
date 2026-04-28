@{
    ModuleVersion     = '1.2.1'
    GUID              = 'b7d3f2a1-4c9e-4f8d-a2b5-3e6d7f8a9b0c'
    Author            = 'Vitaly Andrev'
    Description       = 'Shared PowerShell utilities for infrastructure repos.'
    PowerShellVersion = '5.1'
    RootModule        = 'Infrastructure.Common.psm1'
    FunctionsToExport = @(
        'Assert-RequiredProperties',
        'Invoke-ModuleInstall',
        'Invoke-SshClientCommand',
        'Set-DeploymentStatus'
    )
    CmdletsToExport   = @()
    AliasesToExport   = @()
}
