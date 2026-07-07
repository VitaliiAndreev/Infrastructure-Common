@{
    ModuleVersion        = '9.3.0'
    GUID                 = 'b7d3f2a1-4c9e-4f8d-a2b5-3e6d7f8a9b0c'
    Author               = 'Klark Morrigan'
    Description          = 'Shared PowerShell functions.'
    PowerShellVersion    = '7.0'
    CompatiblePSEditions = @('Core')
    RootModule        = 'Common.PowerShell.psm1'
    # FunctionsToExport is module discovery metadata: used by
    # Get-Module -ListAvailable, Find-Module, and PSGallery without loading
    # the module. It does NOT control what is callable at runtime - that is
    # governed by Export-ModuleMember in the psm1, which takes precedence.
    # Both lists must stay in sync. The shared Module.Tests.ps1 in the
    # run-unit-tests action enforces this.
    FunctionsToExport = @(
        # Top-level utilities
        'Assert-RequiredProperties',
        'ConvertTo-Array',
        'Invoke-ModuleInstall',
        'Limit-RetainedItem',
        # Retry loop (Public/Retry/)
        'Invoke-WithExitCodeRetry',
        'Invoke-WithRetry',
        # Transient-error strategies (Public/Retry/TransientErrorStrategies/)
        'New-FileLockRetryStrategy',
        'New-TransientPowerShellModuleInstallRetryStrategy',
        'New-TransientNetworkRetryStrategy',
        # Backoff strategies (Public/Retry/BackoffStrategies/)
        'New-ConstantBackoffStrategy',
        'New-CustomBackoffStrategy',
        'New-ExponentialBackoffStrategy',
        'New-LinearBackoffStrategy',
        # Timing tree (Public/Timing/)
        'Add-TimingSpanDuration',
        'Export-TimingSpanTree',
        'Import-TimingSpanTree',
        'Initialize-TimingSpanTree',
        'Measure-TimingSpan',
        'New-TimingSpanTree',
        'Write-TimingSpanReport',
        # Timing tree - 2-level compat shims (Public/Timing/)
        'Add-SubStepDuration',
        'Export-PhaseTimingTree',
        'Export-PhaseTimingTreeIfRequested',
        'Initialize-PhaseTimings',
        'Invoke-WithPhaseTimer',
        'Invoke-WithSubStepTimer',
        'Write-PhaseTimingReport'
    )
    CmdletsToExport   = @()
    AliasesToExport   = @()
    # PSData surfaces the project/license links, search tags, and release
    # notes on the PowerShell Gallery package page. Without it the gallery
    # listing has no link back to the source repository.
    PrivateData = @{
        PSData = @{
            ProjectUri   = 'https://github.com/Klark-Morrigan/Common-PowerShell'
            LicenseUri   = 'https://github.com/Klark-Morrigan/Common-PowerShell/blob/master/LICENSE'
            ReleaseNotes = 'https://github.com/Klark-Morrigan/Common-PowerShell/releases'
        }
    }
}
