BeforeAll {
    $timingPrivate = "$PSScriptRoot\..\..\Common.PowerShell\Private\Timing"
    $timingPublic  = "$PSScriptRoot\..\..\Common.PowerShell\Public\Timing"
    . "$timingPrivate\New-TimingSpanNode.ps1"
    . "$timingPrivate\Resolve-TimingSpanChildNode.ps1"
    . "$timingPrivate\Add-TimingSpanNodeElapsed.ps1"
    . "$timingPrivate\ConvertTo-TimingSpanExportNode.ps1"
    . "$timingPublic\New-TimingSpanTree.ps1"
    . "$timingPublic\Measure-TimingSpan.ps1"
    . "$timingPublic\Add-TimingSpanDuration.ps1"
    . "$timingPublic\Export-TimingSpanTree.ps1"
}

Describe 'Export-TimingSpanTree' {

    It 'writes a schema-tagged document at the given path' {
        $tree = New-TimingSpanTree -RootName 'run'
        $path = Join-Path $TestDrive 'tree.json'

        Export-TimingSpanTree -Tree $tree -Path $path

        Test-Path -LiteralPath $path | Should -BeTrue
        $doc = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $doc.schema | Should -Be 'e2e-timing/v1'
    }

    It 'serialises the root node under camelCase keys' {
        $tree = New-TimingSpanTree -RootName 'run' -Source 'provision.ps1'
        Add-TimingSpanDuration -Tree $tree -Name 'x' -ElapsedMs 100
        $path = Join-Path $TestDrive 'tree.json'

        Export-TimingSpanTree -Tree $tree -Path $path
        $root = (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).root

        $root.order  | Should -Be 0
        $root.name   | Should -Be 'run'
        $root.source | Should -Be 'provision.ps1'
        $root.children[0].name      | Should -Be 'x'
        $root.children[0].elapsedMs | Should -Be 100
        $root.children[0].status    | Should -Be 'OK'
    }

    It 'preserves nesting to arbitrary depth' {
        $tree = New-TimingSpanTree -RootName 'run'
        Measure-TimingSpan -Tree $tree -Name 'A' -Action {
            Measure-TimingSpan -Tree $tree -Name 'A.1' -Action {
                Add-TimingSpanDuration -Tree $tree -Name 'A.1.a' -ElapsedMs 5
            }
        }
        $path = Join-Path $TestDrive 'tree.json'

        Export-TimingSpanTree -Tree $tree -Path $path
        $root = (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).root

        $root.children[0].name                       | Should -Be 'A'
        $root.children[0].children[0].name           | Should -Be 'A.1'
        $root.children[0].children[0].children[0].name | Should -Be 'A.1.a'
    }

    It 'emits a leaf node children field as an empty JSON array' {
        $tree = New-TimingSpanTree -RootName 'run'
        Add-TimingSpanDuration -Tree $tree -Name 'leaf' -ElapsedMs 1
        $path = Join-Path $TestDrive 'tree.json'

        Export-TimingSpanTree -Tree $tree -Path $path

        # A leaf must serialise "children": [] so the import side always finds
        # a list, never a missing or scalar field.
        $raw = Get-Content -LiteralPath $path -Raw
        $raw | Should -Match '"children"\s*:\s*\[\s*\]'
    }
}
