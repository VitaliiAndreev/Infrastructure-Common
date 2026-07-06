BeforeAll {
    # Dot-source the 2-level compat shims over the timing-tree core + private
    # helpers, mirroring the psm1 wiring, so the shared default context is in
    # this file's script scope.
    $timingPrivate = "$PSScriptRoot\..\..\Common.PowerShell\Private\Timing"
    $timingPublic  = "$PSScriptRoot\..\..\Common.PowerShell\Public\Timing"
    . "$timingPrivate\New-TimingSpanNode.ps1"
    . "$timingPrivate\Resolve-TimingSpanChildNode.ps1"
    . "$timingPrivate\Add-TimingSpanNodeElapsed.ps1"
    . "$timingPrivate\Add-TimingSpanSkeletonBranch.ps1"
    . "$timingPrivate\Format-TimingSpanElapsed.ps1"
    . "$timingPrivate\Get-TimingSpanStatusTag.ps1"
    . "$timingPublic\New-TimingSpanTree.ps1"
    . "$timingPublic\Initialize-TimingSpanTree.ps1"
    . "$timingPublic\Measure-TimingSpan.ps1"
    . "$timingPublic\Initialize-PhaseTimings.ps1"
    . "$timingPublic\Invoke-WithPhaseTimer.ps1"
    . "$timingPublic\Add-SubStepDuration.ps1"
    . "$timingPublic\Invoke-WithSubStepTimer.ps1"
    . "$timingPublic\Write-PhaseTimingReport.ps1"
}

Describe 'Write-PhaseTimingReport' {

    BeforeEach {
        Initialize-PhaseTimings -Phases @('A', 'B', 'C')
    }

    It 'emits one line per phase in declared order, marking statuses correctly' {
        Invoke-WithPhaseTimer -Name 'A' -Action { }
        { Invoke-WithPhaseTimer -Name 'B' -Action { throw 'x' } } |
            Should -Throw
        # C left NotStarted

        $output = (Write-PhaseTimingReport 6>&1 | Out-String) -split "`r?`n"

        # @() wraps each Where-Object so .Count works even when a single-element
        # match would otherwise unwrap to a scalar.
        @($output | Where-Object {
            $_ -match '\bA\b' -and $_ -match '\[OK\]' }).Count |
            Should -Be 1
        @($output | Where-Object {
            $_ -match '\bB\b' -and $_ -match '\[FAILED\]' }).Count |
            Should -Be 1
        @($output | Where-Object {
            $_ -match '\bC\b' -and $_ -match '\[SKIPPED\]' }).Count |
            Should -Be 1
        @($output | Where-Object {
            $_ -match '^=== Provisioning timing report ===$' }).Count |
            Should -Be 2
        @($output | Where-Object {
            $_ -match 'total observed' }).Count |
            Should -Be 1
    }

    It 'shows a dash duration for SKIPPED phases (no number, no exception)' {
        $output = (Write-PhaseTimingReport 6>&1 | Out-String) -split "`r?`n"
        $skippedLines = @($output | Where-Object { $_ -match '\[SKIPPED\]' })
        $skippedLines.Count | Should -Be 3
        foreach ($l in $skippedLines) {
            $l | Should -Match '-'
        }
    }

    It 'is a no-op when Initialize was never called' {
        # The shim keys off the default context; nulling it reproduces the
        # "never initialised" state.
        Set-Variable -Scope Script -Name DefaultPhaseTimingTree -Value $null
        $output = Write-PhaseTimingReport 6>&1 | Out-String
        $output.Trim() | Should -BeNullOrEmpty
    }

    Context 'sub-step rendering' {

        BeforeEach {
            Initialize-PhaseTimings -Phases @(
                @{ Name = 'Post-provisioning'; SubSteps = @('cloud-init wait', 'files') }
            )
            Invoke-WithPhaseTimer   -Name 'Post-provisioning' -Action {
                Invoke-WithSubStepTimer -Parent 'Post-provisioning' -Name 'cloud-init wait' -Action {}
                Invoke-WithSubStepTimer -Parent 'Post-provisioning' -Name 'files'           -Action {}
            }
        }

        It 'renders sub-step rows indented under the parent' {
            $output = (Write-PhaseTimingReport 6>&1 | Out-String) -split "`r?`n"

            # The parent row starts with two leading spaces (the standard
            # column indent) then the parent name. The sub-step row starts
            # with two MORE spaces (the sub-step indent) before the name.
            # Matching on the prefix is the cleanest signal that the hierarchy
            # renders correctly.
            @($output | Where-Object {
                $_ -match '^  Post-provisioning' }).Count |
                Should -Be 1
            @($output | Where-Object {
                $_ -match '^    cloud-init wait' }).Count |
                Should -Be 1
            @($output | Where-Object {
                $_ -match '^    files' }).Count |
                Should -Be 1
        }

        It 'sums only top-level phases into total observed (sub-steps not double-counted)' {
            # Synthesise concrete durations on the tree so the assertion is
            # exact. Walk the default context's nodes by name.
            $tree = Get-Variable -Scope Script -Name DefaultPhaseTimingTree -ValueOnly
            $phase = $tree.Root.Children | Where-Object { $_.Name -eq 'Post-provisioning' }
            $phase.ElapsedMs = 1000
            foreach ($sub in $phase.Children) {
                if ($sub.Name -eq 'cloud-init wait') { $sub.ElapsedMs = 400 }
                if ($sub.Name -eq 'files')           { $sub.ElapsedMs = 200 }
            }

            $output = (Write-PhaseTimingReport 6>&1 | Out-String) -split "`r?`n"
            $totalLine = @($output | Where-Object { $_ -match 'total observed' })[0]

            # Top-level contribution is 1000 ms = 1.00 s. Sub-step time is
            # already inside the parent's measured wall-clock; adding it to the
            # total would double-count it.
            $totalLine | Should -Match '1\.00 s'
        }
    }

    Context 'pre-migration snapshot' {

        It 'renders a 2-level tree byte-for-byte as the legacy report' {
            # Behaviour-preserving migration ([Constraints] in problem.md):
            # a 2-level tree built via the old verbs must render identically to
            # the pre-generalisation Write-PhaseTimingReport. Durations are
            # pinned (not wall-clock) so the whole block is deterministic.
            Initialize-PhaseTimings -Phases @(
                'Acquire',
                @{ Name = 'Post-provisioning'; SubSteps = @('cloud-init wait', 'files') },
                'Teardown'
            )
            $tree = Get-Variable -Scope Script -Name DefaultPhaseTimingTree -ValueOnly

            $acquire = $tree.Root.Children | Where-Object { $_.Name -eq 'Acquire' }
            $acquire.Status = 'OK'; $acquire.ElapsedMs = 2000

            $post = $tree.Root.Children | Where-Object { $_.Name -eq 'Post-provisioning' }
            $post.Status = 'OK'; $post.ElapsedMs = 3000
            $cloud = $post.Children | Where-Object { $_.Name -eq 'cloud-init wait' }
            $cloud.Status = 'OK'; $cloud.ElapsedMs = 1500
            # 'files' and 'Teardown' left NotStarted / no elapsed -> SKIPPED.

            $output = (Write-PhaseTimingReport 6>&1 | Out-String).TrimEnd() -split "`r?`n"

            $expected = @(
                '',
                '=== Provisioning timing report ===',
                '  Acquire            [OK]           2.00 s',
                '  Post-provisioning  [OK]           3.00 s',
                '    cloud-init wait  [OK]           1.50 s',
                '    files            [SKIPPED]       -    ',
                '  Teardown           [SKIPPED]       -    ',
                '  ----------------------------------',
                '  total observed:     5.00 s',
                '=== Provisioning timing report ==='
            )

            ($output -join "`n") | Should -Be ($expected -join "`n")
        }
    }
}
