BeforeAll {
    $timingPrivate = "$PSScriptRoot\..\..\Common.PowerShell\Private\Timing"
    $timingPublic  = "$PSScriptRoot\..\..\Common.PowerShell\Public\Timing"
    . "$timingPrivate\Resolve-TimingSpanChildNode.ps1"
    . "$timingPrivate\Add-TimingSpanNodeElapsed.ps1"
    . "$timingPrivate\Add-TimingSpanSkeletonBranch.ps1"
    . "$timingPublic\New-TimingSpanTree.ps1"
}

Describe 'New-TimingSpanTree' {

    It 'creates a root node with the given name at Order 0' {
        $tree = New-TimingSpanTree -RootName 'run'
        $tree.Root.Name  | Should -Be 'run'
        $tree.Root.Order | Should -Be 0
    }

    It 'starts the root Running with no elapsed and no children' {
        $tree = New-TimingSpanTree -RootName 'run'
        $tree.Root.Status    | Should -Be 'Running'
        $tree.Root.ElapsedMs | Should -Be $null
        $tree.Root.Children.Count | Should -Be 0
    }

    It 'seeds the current-node stack with the root' {
        $tree = New-TimingSpanTree -RootName 'run'
        $tree.Stack.Count | Should -Be 1
        # Reference equality: the top of the stack IS the root node.
        [object]::ReferenceEquals($tree.Stack.Peek(), $tree.Root) |
            Should -BeTrue
    }

    It 'hands out Order 1 next, since the root took 0' {
        $tree = New-TimingSpanTree -RootName 'run'
        $tree.NextOrder | Should -Be 1
    }

    It 'leaves Source null when none is supplied' {
        $tree = New-TimingSpanTree -RootName 'run'
        $tree.Root.Source | Should -Be $null
    }

    It 'tags the root with the supplied Source' {
        $tree = New-TimingSpanTree -RootName 'run' -Source 'e2e.ps1'
        $tree.Root.Source | Should -Be 'e2e.ps1'
    }

    It 'rejects an empty root name' {
        { New-TimingSpanTree -RootName '' } | Should -Throw
    }
}
