BeforeAll {
    $timingPrivate = "$PSScriptRoot\..\..\Common.PowerShell\Private\Timing"
    $timingPublic  = "$PSScriptRoot\..\..\Common.PowerShell\Public\Timing"
    . "$timingPrivate\New-TimingSpanNode.ps1"
    . "$timingPublic\Write-TimingSpanReport.ps1"

    # A hand-built 4-level tree with exact durations so indent, tags, percent,
    # and total assertions are deterministic (no wall-clock from Measure):
    #   run (Running, root)
    #     A       [OK]       1000 ms
    #       A.1   [OK]        600 ms
    #         A.1.a [OK]      300 ms
    #     B       [SKIPPED]   never ran
    #     C       [FAILED]    200 ms
    # Effective root = top-level A + C = 1200 ms; A.1/A.1.a live INSIDE A's
    # measured 1000 ms and must not inflate the total.
    function New-FourLevelTree {
        $root  = New-TimingSpanNode -Order 0 -Name 'run'   -Status 'Running'
        $a     = New-TimingSpanNode -Order 1 -Name 'A'     -Status 'OK'         -ElapsedMs 1000
        $a1    = New-TimingSpanNode -Order 2 -Name 'A.1'   -Status 'OK'         -ElapsedMs 600
        $a1a   = New-TimingSpanNode -Order 3 -Name 'A.1.a' -Status 'OK'         -ElapsedMs 300
        $b     = New-TimingSpanNode -Order 4 -Name 'B'     -Status 'NotStarted'
        $c     = New-TimingSpanNode -Order 5 -Name 'C'     -Status 'Failed'     -ElapsedMs 200

        $a1.Children.Add($a1a)
        $a.Children.Add($a1)
        $root.Children.Add($a)
        $root.Children.Add($b)
        $root.Children.Add($c)
        return $root
    }

    function Get-ReportLines($tree) {
        return (Write-TimingSpanReport -Tree $tree 6>&1 | Out-String) -split "`r?`n"
    }
}

Describe 'Write-TimingSpanReport' {

    It 'renders a 4-level tree with correct per-depth indent and status tags' {
        $lines = Get-ReportLines (New-FourLevelTree)

        # Two leading spaces of base column indent, then two more per depth.
        # Depth 0 -> 2 spaces, depth 1 -> 4, depth 2 -> 6.
        @($lines | Where-Object { $_ -match '^  A\s+\[OK\]' }).Count       | Should -Be 1
        @($lines | Where-Object { $_ -match '^    A\.1\s+\[OK\]' }).Count   | Should -Be 1
        @($lines | Where-Object { $_ -match '^      A\.1\.a\s+\[OK\]' }).Count | Should -Be 1
        @($lines | Where-Object { $_ -match '^  B\s+\[SKIPPED\]' }).Count   | Should -Be 1
        @($lines | Where-Object { $_ -match '^  C\s+\[FAILED\]' }).Count    | Should -Be 1

        # Banner brackets the block (open + close), naming the root.
        @($lines | Where-Object { $_ -match '^=== Timing report: run ===$' }).Count |
            Should -Be 2
    }

    It 'shows percent-of-parent that sums sensibly at each level' {
        $lines = Get-ReportLines (New-FourLevelTree)

        # Top level is a share of the run total (1200 ms): A=1000 -> 83%,
        # C=200 -> 17%, together 100%. Deeper nodes are a share of their own
        # measured parent: A.1=600 of A's 1000 -> 60%; A.1.a=300 of 600 -> 50%.
        @($lines | Where-Object { $_ -match '^  A\s.*\( 83%\)' }).Count      | Should -Be 1
        @($lines | Where-Object { $_ -match '^  C\s.*\( 17%\)' }).Count      | Should -Be 1
        @($lines | Where-Object { $_ -match '^    A\.1\s.*\( 60%\)' }).Count | Should -Be 1
        @($lines | Where-Object { $_ -match '^      A\.1\.a\s.*\( 50%\)' }).Count | Should -Be 1
    }

    It 'caps percent-of-parent at 100% when a grafted subtree outweighs the parent span' {
        # The D2 merge grafts a child process's subtree under a part whose own
        # measured span can be shorter than the child's reported total (clock
        # skew, or the parent timing only the shell-out wrapper). The child's
        # share of such a parent must not read above 100%.
        $root  = New-TimingSpanNode -Order 0 -Name 'run'  -Status 'Running'
        $part  = New-TimingSpanNode -Order 1 -Name 'part' -Status 'OK' -ElapsedMs 100
        $child = New-TimingSpanNode -Order 2 -Name 'graft' -Status 'OK' -ElapsedMs 5000
        $part.Children.Add($child)
        $root.Children.Add($part)

        $graftLine = @((Get-ReportLines $root) |
            Where-Object { $_ -match '^    graft\s' })[0]

        # 5000 of an effective parent of max(100, 5000) = 5000 -> exactly 100%,
        # never the 5000% a raw parent-own denominator would produce.
        $graftLine | Should -Match '\(100%\)'
    }

    It 'shows a dash and no percent for a SKIPPED node, partial elapsed for FAILED' {
        $lines = Get-ReportLines (New-FourLevelTree)

        $skipped = @($lines | Where-Object { $_ -match '^  B\s+\[SKIPPED\]' })[0]
        $skipped | Should -Match '-'
        # A skipped node never ran, so it carries no seconds and no share.
        $skipped | Should -Not -Match '\d\.\d\d s'
        $skipped | Should -Not -Match '%\)'

        $failed = @($lines | Where-Object { $_ -match '^  C\s+\[FAILED\]' })[0]
        $failed | Should -Match '0\.20 s'
    }

    It 'totals the root effective elapsed only, without double-counting sub-steps' {
        $lines = Get-ReportLines (New-FourLevelTree)
        $total = @($lines | Where-Object { $_ -match 'total observed' })[0]

        # A (1000) + C (200) = 1200 ms = 1.20 s. A.1 (600) and A.1.a (300) are
        # inside A's measured time; adding them would double-count.
        $total | Should -Match '1\.20 s'
    }

    It 'accepts a context object (with a Root) equivalently to a bare node' {
        $node    = New-FourLevelTree
        $context = [pscustomobject]@{
            Root      = $node
            Stack     = $null
            NextOrder = 6
        }

        (Get-ReportLines $context) -join "`n" |
            Should -Be ((Get-ReportLines $node) -join "`n")
    }

    It 'renders a childless root as just the banner and a zero total' {
        $root  = New-TimingSpanNode -Order 0 -Name 'empty' -Status 'Running'
        $lines = Get-ReportLines $root

        @($lines | Where-Object { $_ -match 'total observed:\s+0\.00 s' }).Count |
            Should -Be 1
        @($lines | Where-Object { $_ -match '^=== Timing report: empty ===$' }).Count |
            Should -Be 2
    }
}
