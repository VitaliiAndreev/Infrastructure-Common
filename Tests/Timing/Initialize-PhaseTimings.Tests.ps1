BeforeAll {
    # The 2-level compat shims are dot-sourced over the timing-tree core and
    # its private helpers, exactly as the psm1 wires them, so the shared
    # $script:DefaultPhaseTimingTree default context lives in this file's
    # script scope for the assertions to read via Get-Variable.
    $timingPrivate = "$PSScriptRoot\..\..\Common.PowerShell\Private\Timing"
    $timingPublic  = "$PSScriptRoot\..\..\Common.PowerShell\Public\Timing"
    . "$timingPrivate\New-TimingSpanNode.ps1"
    . "$timingPrivate\Resolve-TimingSpanChildNode.ps1"
    . "$timingPrivate\Add-TimingSpanNodeElapsed.ps1"
    . "$timingPrivate\Add-TimingSpanSkeletonBranch.ps1"
    . "$timingPublic\New-TimingSpanTree.ps1"
    . "$timingPublic\Initialize-TimingSpanTree.ps1"
    . "$timingPublic\Measure-TimingSpan.ps1"
    . "$timingPublic\Initialize-PhaseTimings.ps1"
    . "$timingPublic\Invoke-WithPhaseTimer.ps1"
}

Describe 'Initialize-PhaseTimings' {

    It 'creates one node per declared phase, all NotStarted' {
        Initialize-PhaseTimings -Phases @('A', 'B', 'C')

        # The default context now backs the 2-level verbs; its root's children
        # are the top-level phases. Read it from script scope where the shim
        # declared it (the tree-model successor of $script:PhaseTimings).
        $tree = Get-Variable -Scope Script -Name DefaultPhaseTimingTree -ValueOnly
        $phases = @($tree.Root.Children | Sort-Object Order)

        $phases.Count        | Should -Be 3
        $phases[0].Name      | Should -Be 'A'
        $phases[0].Status    | Should -Be 'NotStarted'
        $phases[0].ElapsedMs | Should -BeNullOrEmpty
        ($phases | ForEach-Object Status) | Should -Be @(
            'NotStarted', 'NotStarted', 'NotStarted'
        )
        # Order is monotonic first-contact declaration order under the root.
        $phases[0].Order | Should -BeLessThan $phases[1].Order
        $phases[1].Order | Should -BeLessThan $phases[2].Order
    }

    It 'clears prior state on re-init' {
        Initialize-PhaseTimings -Phases @('A', 'B')
        Invoke-WithPhaseTimer -Name 'A' -Action { }

        Initialize-PhaseTimings -Phases @('X')

        # Re-init mints a fresh context, so the prior A/B (and A's run state)
        # are gone - only X remains under the root.
        $tree = Get-Variable -Scope Script -Name DefaultPhaseTimingTree -ValueOnly
        $phases = @($tree.Root.Children)
        $phases.Count   | Should -Be 1
        $phases[0].Name | Should -Be 'X'
    }

    It 'accepts hashtable entries with SubSteps and nests each under its phase' {
        # The hashtable form is how provision.ps1 pre-declares known sub-steps
        # so the report can show them as SKIPPED on runs where the work did
        # not apply. In the tree model a sub-step is a child of its phase node
        # rather than a flat row tagged with a Parent name.
        Initialize-PhaseTimings -Phases @(
            'A',
            @{ Name = 'B'; SubSteps = @('b1', 'b2') },
            'C'
        )

        $tree = Get-Variable -Scope Script -Name DefaultPhaseTimingTree -ValueOnly
        $phases = @($tree.Root.Children | Sort-Object Order)

        # Top-level phases in declaration order.
        ($phases | ForEach-Object Name) | Should -Be @('A', 'B', 'C')

        # B's sub-steps hang off B, not the root, in declaration order.
        $b = $phases | Where-Object { $_.Name -eq 'B' }
        $subs = @($b.Children | Sort-Object Order)
        ($subs | ForEach-Object Name) | Should -Be @('b1', 'b2')

        # A and C have no sub-steps.
        @(($phases | Where-Object { $_.Name -eq 'A' }).Children).Count | Should -Be 0
        @(($phases | Where-Object { $_.Name -eq 'C' }).Children).Count | Should -Be 0

        # Order threads across mixed depths (phase then its sub-steps then the
        # next phase) so the renderer can group with one sorted walk.
        $a = $phases | Where-Object { $_.Name -eq 'A' }
        $c = $phases | Where-Object { $_.Name -eq 'C' }
        $a.Order     | Should -BeLessThan $b.Order
        $b.Order     | Should -BeLessThan $subs[0].Order
        $subs[0].Order | Should -BeLessThan $subs[1].Order
        $subs[1].Order | Should -BeLessThan $c.Order

        # Every node starts NotStarted regardless of nesting depth.
        $allNodes = @($a, $b, $c, $subs[0], $subs[1])
        ($allNodes | ForEach-Object Status) -join ',' |
            Should -Be 'NotStarted,NotStarted,NotStarted,NotStarted,NotStarted'
    }

    It 'rejects an empty sub-step name with a message naming the parent' {
        { Initialize-PhaseTimings -Phases @(
            @{ Name = 'B'; SubSteps = @('') }
        ) } | Should -Throw "*'B'*empty sub-step*"
    }

    It 'rejects a phase entry with no Name' {
        { Initialize-PhaseTimings -Phases @(
            @{ SubSteps = @('x') }
        ) } | Should -Throw '*phase entry has no Name*'
    }
}
