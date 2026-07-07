BeforeAll {
    # Dot-source the 2-level compat shims (which own the shared default context),
    # the export shim this verb delegates to, and the core export/import used by
    # its round-trip assertion - mirroring the psm1 wiring so the default context
    # lives in this file's script scope.
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
    . "$timingPublic\Export-PhaseTimingTreeIfRequested.ps1"
}

Describe 'Export-PhaseTimingTreeIfRequested' {

    AfterEach {
        # Each test owns its opt-in state; clear both the default and the custom
        # env vars so a set-var from one test cannot leak into the next.
        Remove-Item Env:\TIMING_TREE_OUTPUT_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:\CUSTOM_TIMING_PATH      -ErrorAction SilentlyContinue
    }

    It 'exports schema-valid JSON when the env var is set and the context is populated' {
        # Build a 2-level tree through the shims, point the opt-in env var at a
        # temp file, then let the self-guarding shim read that var and delegate:
        # the round-trip must reproduce the phase / sub-step names and statuses
        # the default context holds.
        Initialize-PhaseTimings -Phases @(
            'Acquire',
            @{ Name = 'Post-provisioning'; SubSteps = @('cloud-init wait') }
        )
        Invoke-WithPhaseTimer -Name 'Acquire' -Action { }
        Invoke-WithPhaseTimer -Name 'Post-provisioning' -Action {
            Invoke-WithSubStepTimer `
                -Parent 'Post-provisioning' -Name 'cloud-init wait' -Action { }
        }

        $path = Join-Path $TestDrive 'requested-tree.json'
        $env:TIMING_TREE_OUTPUT_PATH = $path

        Export-PhaseTimingTreeIfRequested

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
    }

    It 'does not delegate the export and does not throw when the env var is unset (opt-out)' {
        # A populated context but no opt-in path: the guard is false, so the
        # delegate never runs and an operator run leaves no stray artifact.
        # Mock the delegate (rather than probing the filesystem) so the check is
        # exact and immune to the file the sibling tests leave under TestDrive.
        Mock Export-PhaseTimingTree { }
        Initialize-PhaseTimings -Phases @('Acquire')
        Invoke-WithPhaseTimer -Name 'Acquire' -Action { }
        Remove-Item Env:\TIMING_TREE_OUTPUT_PATH -ErrorAction SilentlyContinue

        { Export-PhaseTimingTreeIfRequested } | Should -Not -Throw

        Should -Invoke Export-PhaseTimingTree -Times 0 -Exactly
    }

    It 'is a no-op when Initialize was never called even with the env var set' {
        # Null-guard parity with Write-PhaseTimingReport, inherited from the
        # Export-PhaseTimingTree delegate: a run that never initialised timings
        # must write no file and not throw so an outer finally can call this
        # unconditionally.
        Set-Variable -Scope Script -Name DefaultPhaseTimingTree -Value $null
        $path = Join-Path $TestDrive 'uninitialised.json'
        $env:TIMING_TREE_OUTPUT_PATH = $path

        { Export-PhaseTimingTreeIfRequested } | Should -Not -Throw
        Test-Path -LiteralPath $path | Should -BeFalse
    }

    It 'honours a custom -EnvVariableName' {
        # A caller with its own opt-in convention can point the guard at a
        # different variable; the default TIMING_TREE_OUTPUT_PATH stays unset and
        # must not drive the export.
        Initialize-PhaseTimings -Phases @('Acquire')
        Invoke-WithPhaseTimer -Name 'Acquire' -Action { }

        $path = Join-Path $TestDrive 'custom-var.json'
        $env:CUSTOM_TIMING_PATH = $path
        Remove-Item Env:\TIMING_TREE_OUTPUT_PATH -ErrorAction SilentlyContinue

        Export-PhaseTimingTreeIfRequested -EnvVariableName 'CUSTOM_TIMING_PATH'

        Test-Path -LiteralPath $path | Should -BeTrue
        (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).schema |
            Should -Be 'e2e-timing/v1'
    }
}
