BeforeAll {
    $timingPrivate = "$PSScriptRoot\..\..\Common.PowerShell\Private\Timing"
    $timingPublic  = "$PSScriptRoot\..\..\Common.PowerShell\Public\Timing"
    . "$timingPrivate\New-TimingSpanNode.ps1"
    . "$timingPrivate\Resolve-TimingSpanChildNode.ps1"
    . "$timingPrivate\Add-TimingSpanNodeElapsed.ps1"
    . "$timingPrivate\Add-TimingSpanSkeletonBranch.ps1"
    . "$timingPublic\New-TimingSpanTree.ps1"
    . "$timingPublic\Measure-TimingSpan.ps1"
    . "$timingPublic\Add-TimingSpanDuration.ps1"
}

Describe 'Add-TimingSpanDuration' {

    It 'adds a leaf span under the current node with the given elapsed' {
        $tree = New-TimingSpanTree -RootName 'run'
        Add-TimingSpanDuration -Tree $tree -Name 'x' -ElapsedMs 100

        $node = $tree.Root.Children[0]
        $node.Name      | Should -Be 'x'
        $node.ElapsedMs | Should -Be 100
        $node.Status    | Should -Be 'OK'
    }

    It 'accumulates the exact sum across repeated calls, one node' {
        $tree = New-TimingSpanTree -RootName 'run'
        Add-TimingSpanDuration -Tree $tree -Name 'x' -ElapsedMs 100
        Add-TimingSpanDuration -Tree $tree -Name 'x' -ElapsedMs 50

        $tree.Root.Children.Count | Should -Be 1
        $tree.Root.Children[0].ElapsedMs | Should -Be 150
    }

    It 'attaches under whatever node is current' {
        $tree = New-TimingSpanTree -RootName 'run'
        Measure-TimingSpan -Tree $tree -Name 'A' -Action {
            Add-TimingSpanDuration -Tree $tree -Name 'sub' -ElapsedMs 10
        }

        $a = $tree.Root.Children[0]
        $a.Children.Count | Should -Be 1
        $a.Children[0].Name      | Should -Be 'sub'
        $a.Children[0].ElapsedMs | Should -Be 10
    }

    Context 'status' {

        It 'marks Failed with -Failed' {
            $tree = New-TimingSpanTree -RootName 'run'
            Add-TimingSpanDuration -Tree $tree -Name 'x' -ElapsedMs 5 -Failed
            $tree.Root.Children[0].Status | Should -Be 'Failed'
        }

        It 'keeps Failed sticky under a later successful add' {
            $tree = New-TimingSpanTree -RootName 'run'
            Add-TimingSpanDuration -Tree $tree -Name 'x' -ElapsedMs 5 -Failed
            Add-TimingSpanDuration -Tree $tree -Name 'x' -ElapsedMs 5
            $tree.Root.Children[0].Status | Should -Be 'Failed'
        }
    }

    Context 'source' {

        It 'backfills Source onto a node first created without one' {
            $tree = New-TimingSpanTree -RootName 'run'
            Add-TimingSpanDuration -Tree $tree -Name 'x' -ElapsedMs 5
            Add-TimingSpanDuration -Tree $tree -Name 'x' -ElapsedMs 5 `
                -Source 'child.ps1'
            $tree.Root.Children[0].Source | Should -Be 'child.ps1'
        }

        It 'does not overwrite an existing Source' {
            $tree = New-TimingSpanTree -RootName 'run'
            Add-TimingSpanDuration -Tree $tree -Name 'x' -ElapsedMs 5 `
                -Source 'first.ps1'
            Add-TimingSpanDuration -Tree $tree -Name 'x' -ElapsedMs 5 `
                -Source 'second.ps1'
            $tree.Root.Children[0].Source | Should -Be 'first.ps1'
        }
    }
}
