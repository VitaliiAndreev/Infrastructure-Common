BeforeAll {
    $timingPrivate = "$PSScriptRoot\..\..\Common.PowerShell\Private\Timing"
    $timingPublic  = "$PSScriptRoot\..\..\Common.PowerShell\Public\Timing"
    . "$timingPrivate\New-TimingSpanNode.ps1"
    . "$timingPrivate\Resolve-TimingSpanChildNode.ps1"
    . "$timingPrivate\Add-TimingSpanNodeElapsed.ps1"
    . "$timingPrivate\ConvertTo-TimingSpanExportNode.ps1"
    . "$timingPrivate\ConvertFrom-TimingSpanImportNode.ps1"
    . "$timingPublic\New-TimingSpanTree.ps1"
    . "$timingPublic\Measure-TimingSpan.ps1"
    . "$timingPublic\Add-TimingSpanDuration.ps1"
    . "$timingPublic\Export-TimingSpanTree.ps1"
    . "$timingPublic\Import-TimingSpanTree.ps1"
}

Describe 'Import-TimingSpanTree' {

    Context 'round-trip (export then import)' {

        It 'reconstructs an equivalent subtree' {
            $tree = New-TimingSpanTree -RootName 'run' -Source 'provision.ps1'
            Measure-TimingSpan -Tree $tree -Name 'A' -Action {
                Add-TimingSpanDuration -Tree $tree -Name 'A.1' -ElapsedMs 250
            }
            Add-TimingSpanDuration -Tree $tree -Name 'B' -ElapsedMs 40 -Failed
            $path = Join-Path $TestDrive 'tree.json'
            Export-TimingSpanTree -Tree $tree -Path $path

            $imported = Import-TimingSpanTree -Path $path

            $imported.Order  | Should -Be $tree.Root.Order
            $imported.Name   | Should -Be $tree.Root.Name
            $imported.Source | Should -Be $tree.Root.Source

            $a = $imported.Children[0]
            $a.Name             | Should -Be 'A'
            $a.Children[0].Name      | Should -Be 'A.1'
            $a.Children[0].ElapsedMs | Should -Be 250

            $b = $imported.Children[1]
            $b.Name      | Should -Be 'B'
            $b.ElapsedMs | Should -Be 40
            $b.Status    | Should -Be 'Failed'
        }

        It 'rebuilds Children as a mutable list the graft step can extend' {
            $tree = New-TimingSpanTree -RootName 'run'
            Add-TimingSpanDuration -Tree $tree -Name 'only' -ElapsedMs 1
            $path = Join-Path $TestDrive 'tree.json'
            Export-TimingSpanTree -Tree $tree -Path $path

            $imported = Import-TimingSpanTree -Path $path

            # Comma-wrap so the pipeline unrolls the wrapper, not the list
            # itself - otherwise Should -BeOfType inspects the first element.
            , $imported.Children | Should -BeOfType ([System.Collections.Generic.List[object]])
            # A grafted leaf's own children are an empty list, not $null.
            $imported.Children[0].Children.Count | Should -Be 0
        }
    }

    Context 'defensive contract (never throws)' {

        It 'returns null with a warning when the file is missing' {
            $path = Join-Path $TestDrive 'absent.json'
            $result = Import-TimingSpanTree -Path $path -WarningAction SilentlyContinue
            $result | Should -Be $null
        }

        It 'does not throw on a missing file' {
            $path = Join-Path $TestDrive 'absent.json'
            { Import-TimingSpanTree -Path $path -WarningAction SilentlyContinue } |
                Should -Not -Throw
        }

        It 'emits a warning for a missing file' {
            $path = Join-Path $TestDrive 'absent.json'
            Import-TimingSpanTree -Path $path -WarningVariable warnings `
                -WarningAction SilentlyContinue | Out-Null
            $warnings | Should -Not -BeNullOrEmpty
        }

        It 'returns null with a warning on malformed JSON' {
            $path = Join-Path $TestDrive 'broken.json'
            Set-Content -LiteralPath $path -Value '{ not valid json' -Encoding utf8

            $result = Import-TimingSpanTree -Path $path -WarningVariable warnings `
                -WarningAction SilentlyContinue
            $result   | Should -Be $null
            $warnings | Should -Not -BeNullOrEmpty
        }

        It 'does not throw on malformed JSON' {
            $path = Join-Path $TestDrive 'broken.json'
            Set-Content -LiteralPath $path -Value '{ not valid json' -Encoding utf8
            { Import-TimingSpanTree -Path $path -WarningAction SilentlyContinue } |
                Should -Not -Throw
        }

        It 'returns null when the document has no root node' {
            $path = Join-Path $TestDrive 'rootless.json'
            Set-Content -LiteralPath $path -Value '{ "schema": "e2e-timing/v1" }' `
                -Encoding utf8

            $result = Import-TimingSpanTree -Path $path -WarningAction SilentlyContinue
            $result | Should -Be $null
        }
    }
}
