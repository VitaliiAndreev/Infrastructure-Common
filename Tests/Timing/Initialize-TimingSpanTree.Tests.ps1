BeforeAll {
    $timingPrivate = "$PSScriptRoot\..\..\Common.PowerShell\Private\Timing"
    $timingPublic  = "$PSScriptRoot\..\..\Common.PowerShell\Public\Timing"
    . "$timingPrivate\New-TimingSpanNode.ps1"
    . "$timingPrivate\Resolve-TimingSpanChildNode.ps1"
    . "$timingPrivate\Add-TimingSpanNodeElapsed.ps1"
    . "$timingPrivate\Add-TimingSpanSkeletonBranch.ps1"
    . "$timingPublic\New-TimingSpanTree.ps1"
    . "$timingPublic\Initialize-TimingSpanTree.ps1"
    . "$timingPublic\Measure-TimingSpan.ps1"
}

Describe 'Initialize-TimingSpanTree' {

    It 'pre-declares a nested skeleton under the root' {
        $tree = New-TimingSpanTree -RootName 'run'
        Initialize-TimingSpanTree -Tree $tree -Skeleton @(
            'Setup',
            @{ Name = 'Phase 1'; Children = @('boot', 'ssh') },
            'Teardown'
        )

        $tree.Root.Children.Name | Should -Be @('Setup', 'Phase 1', 'Teardown')
        $phase1 = $tree.Root.Children[1]
        $phase1.Children.Name | Should -Be @('boot', 'ssh')
    }

    It 'creates pre-declared nodes NotStarted with no elapsed' {
        $tree = New-TimingSpanTree -RootName 'run'
        Initialize-TimingSpanTree -Tree $tree -Skeleton @(
            @{ Name = 'Phase 1'; Children = @('boot') }
        )

        $phase1 = $tree.Root.Children[0]
        $phase1.Status    | Should -Be 'NotStarted'
        $phase1.ElapsedMs | Should -Be $null
        $phase1.Children[0].Status    | Should -Be 'NotStarted'
        $phase1.Children[0].ElapsedMs | Should -Be $null
    }

    It 'orders pre-declared nodes depth-first by declaration' {
        $tree = New-TimingSpanTree -RootName 'run'
        Initialize-TimingSpanTree -Tree $tree -Skeleton @(
            'Setup',
            @{ Name = 'Phase 1'; Children = @('boot', 'ssh') },
            'Teardown'
        )

        $tree.Root.Children[0].Order              | Should -Be 1  # Setup
        $tree.Root.Children[1].Order              | Should -Be 2  # Phase 1
        $tree.Root.Children[1].Children[0].Order  | Should -Be 3  # boot
        $tree.Root.Children[1].Children[1].Order  | Should -Be 4  # ssh
        $tree.Root.Children[2].Order              | Should -Be 5  # Teardown
    }

    It 'leaves an un-run pre-declared branch NotStarted' {
        $tree = New-TimingSpanTree -RootName 'run'
        Initialize-TimingSpanTree -Tree $tree -Skeleton @('Setup', 'Phase 1')
        Measure-TimingSpan -Tree $tree -Name 'Setup' -Action { }

        # Setup ran; Phase 1 never did and must still be visible as NotStarted.
        $tree.Root.Children[0].Status | Should -Be 'OK'
        $tree.Root.Children[1].Status | Should -Be 'NotStarted'
    }

    It 'reuses a pre-declared node when its span later runs' {
        $tree = New-TimingSpanTree -RootName 'run'
        Initialize-TimingSpanTree -Tree $tree -Skeleton @('Setup')
        $order = $tree.Root.Children[0].Order
        Measure-TimingSpan -Tree $tree -Name 'Setup' -Action { }

        # No duplicate sibling minted, and the original Order is preserved.
        $tree.Root.Children.Count | Should -Be 1
        $tree.Root.Children[0].Order  | Should -Be $order
        $tree.Root.Children[0].Status | Should -Be 'OK'
    }

    It 'throws on a skeleton entry with no name' {
        $tree = New-TimingSpanTree -RootName 'run'
        { Initialize-TimingSpanTree -Tree $tree -Skeleton @('   ') } |
            Should -Throw
    }
}
