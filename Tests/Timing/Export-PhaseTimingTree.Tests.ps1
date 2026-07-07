BeforeAll {
    # Dot-source the 2-level compat shims (which own the shared default context)
    # plus the core export/import used by the shim and its round-trip assertion,
    # mirroring the psm1 wiring so the default context is in this file's script
    # scope.
    $timingPrivate = "$PSScriptRoot\..\..\Common.PowerShell\Private\Timing"
    $timingPublic  = "$PSScriptRoot\..\..\Common.PowerShell\Public\Timing"
    . "$timingPrivate\New-TimingSpanNode.ps1"
    . "$timingPrivate\Resolve-TimingSpanChildNode.ps1"
    . "$timingPrivate\Add-TimingSpanNodeElapsed.ps1"
    . "$timingPrivate\Add-TimingSpanSkeletonBranch.ps1"
    . "$timingPrivate\ConvertTo-TimingSpanExportNode.ps1"
    . "$timingPrivate\ConvertFrom-TimingSpanImportNode.ps1"
    . "$timingPublic\New-TimingSpanTree.ps1"
    . "$timingPublic\Initialize-TimingSpanTree.ps1"
    . "$timingPublic\Measure-TimingSpan.ps1"
    . "$timingPublic\Initialize-PhaseTimings.ps1"
    . "$timingPublic\Invoke-WithPhaseTimer.ps1"
    . "$timingPublic\Add-SubStepDuration.ps1"
    . "$timingPublic\Invoke-WithSubStepTimer.ps1"
    . "$timingPublic\Export-TimingSpanTree.ps1"
    . "$timingPublic\Import-TimingSpanTree.ps1"
    . "$timingPublic\Export-PhaseTimingTree.ps1"
}

Describe 'Export-PhaseTimingTree' {

    It 'writes a schema-valid JSON matching the populated default context' {
        # Build a 2-level tree through the shims, then serialise it via the
        # export shim and re-import: the round-trip must reproduce the phase /
        # sub-step names and statuses the default context holds, proving the
        # shim read the module-private context and delegated to the core.
        Initialize-PhaseTimings -Phases @(
            'Acquire',
            @{ Name = 'Post-provisioning'; SubSteps = @('cloud-init wait') }
        )
        Invoke-WithPhaseTimer -Name 'Acquire' -Action { }
        Invoke-WithPhaseTimer -Name 'Post-provisioning' -Action {
            Invoke-WithSubStepTimer `
                -Parent 'Post-provisioning' -Name 'cloud-init wait' -Action { }
        }

        $path = Join-Path $TestDrive 'phase-tree.json'
        Export-PhaseTimingTree -Path $path

        Test-Path -LiteralPath $path | Should -BeTrue
        $doc = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $doc.schema | Should -Be 'e2e-timing/v1'

        $subtree = Import-TimingSpanTree -Path $path
        $subtree.Name                          | Should -Be 'Provisioning'
        ($subtree.Children | Sort-Object Order)[0].Name | Should -Be 'Acquire'
        $post = $subtree.Children |
            Where-Object { $_.Name -eq 'Post-provisioning' }
        $post.Status              | Should -Be 'OK'
        $post.Children[0].Name    | Should -Be 'cloud-init wait'
        $post.Children[0].Status  | Should -Be 'OK'
    }

    It 'is a no-op when Initialize was never called (parity with the report shim)' {
        # The shim keys off the default context; nulling it reproduces the
        # "never initialised" state. It must write no file and not throw so an
        # outer finally can call it unconditionally.
        Set-Variable -Scope Script -Name DefaultPhaseTimingTree -Value $null
        $path = Join-Path $TestDrive 'uninitialised.json'

        { Export-PhaseTimingTree -Path $path } | Should -Not -Throw
        Test-Path -LiteralPath $path | Should -BeFalse
    }
}
