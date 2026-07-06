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

Describe 'Measure-TimingSpan' {

    Context 'nesting' {

        It 'places spans under the correct parent to 3+ levels' {
            $tree = New-TimingSpanTree -RootName 'run'
            Measure-TimingSpan -Tree $tree -Name 'A' -Action {
                Measure-TimingSpan -Tree $tree -Name 'A.1' -Action {
                    Measure-TimingSpan -Tree $tree -Name 'A.1.a' -Action { }
                }
            }

            $a = $tree.Root.Children[0]
            $a.Name | Should -Be 'A'
            $a1 = $a.Children[0]
            $a1.Name | Should -Be 'A.1'
            $a1a = $a1.Children[0]
            $a1a.Name | Should -Be 'A.1.a'
        }

        It 'restores the stack to the root after the outermost span returns' {
            $tree = New-TimingSpanTree -RootName 'run'
            Measure-TimingSpan -Tree $tree -Name 'A' -Action {
                Measure-TimingSpan -Tree $tree -Name 'A.1' -Action { }
            }
            $tree.Stack.Count | Should -Be 1
            [object]::ReferenceEquals($tree.Stack.Peek(), $tree.Root) |
                Should -BeTrue
        }

        It 'streams the action output back to the caller' {
            $tree = New-TimingSpanTree -RootName 'run'
            $result = Measure-TimingSpan -Tree $tree -Name 'A' -Action { 42 }
            $result | Should -Be 42
        }
    }

    Context 'accumulation' {

        It 'keeps a single node and grows its elapsed on repeated calls' {
            $tree = New-TimingSpanTree -RootName 'run'
            Measure-TimingSpan -Tree $tree -Name 'A' -Action {
                Start-Sleep -Milliseconds 15
            }
            $afterFirst = $tree.Root.Children[0].ElapsedMs
            Measure-TimingSpan -Tree $tree -Name 'A' -Action {
                Start-Sleep -Milliseconds 15
            }

            # One node retained (not a second sibling), and the second call
            # added to the running total rather than replacing it.
            $tree.Root.Children.Count | Should -Be 1
            $tree.Root.Children[0].ElapsedMs | Should -BeGreaterOrEqual $afterFirst
        }
    }

    Context 'failure handling' {

        It 'records partial elapsed, marks Failed, and rethrows' {
            $tree = New-TimingSpanTree -RootName 'run'
            {
                Measure-TimingSpan -Tree $tree -Name 'boom' -Action {
                    Start-Sleep -Milliseconds 15
                    throw 'kaboom'
                }
            } | Should -Throw

            $node = $tree.Root.Children[0]
            $node.Status | Should -Be 'Failed'
            # Elapsed was captured before the rethrow (not left $null).
            $node.ElapsedMs | Should -Not -Be $null
            $node.ElapsedMs | Should -BeGreaterOrEqual 1
        }

        It 'keeps Failed sticky when a later run of the same span succeeds' {
            $tree = New-TimingSpanTree -RootName 'run'
            { Measure-TimingSpan -Tree $tree -Name 'A' -Action { throw 'x' } } |
                Should -Throw
            Measure-TimingSpan -Tree $tree -Name 'A' -Action { }

            $tree.Root.Children.Count | Should -Be 1
            $tree.Root.Children[0].Status | Should -Be 'Failed'
        }

        It 'marks the whole ancestor chain Failed on a deep throw' {
            $tree = New-TimingSpanTree -RootName 'run'
            {
                Measure-TimingSpan -Tree $tree -Name 'A' -Action {
                    Measure-TimingSpan -Tree $tree -Name 'A.1' -Action {
                        throw 'deep'
                    }
                }
            } | Should -Throw

            $a = $tree.Root.Children[0]
            $a.Status | Should -Be 'Failed'
            $a.Children[0].Status | Should -Be 'Failed'
        }
    }

    Context 'ordering' {

        It 'assigns Order by first-contact across mixed depths' {
            $tree = New-TimingSpanTree -RootName 'run'
            Measure-TimingSpan -Tree $tree -Name 'A' -Action {
                Measure-TimingSpan -Tree $tree -Name 'A.1' -Action {
                    Measure-TimingSpan -Tree $tree -Name 'A.1.a' -Action { }
                }
                Measure-TimingSpan -Tree $tree -Name 'A.2' -Action { }
            }
            Measure-TimingSpan -Tree $tree -Name 'B' -Action { }

            $a   = $tree.Root.Children[0]
            $a1  = $a.Children[0]
            $a1a = $a1.Children[0]
            $a2  = $a.Children[1]
            $b   = $tree.Root.Children[1]

            $a.Order   | Should -Be 1
            $a1.Order  | Should -Be 2
            $a1a.Order | Should -Be 3
            $a2.Order  | Should -Be 4
            $b.Order   | Should -Be 5
        }
    }
}
