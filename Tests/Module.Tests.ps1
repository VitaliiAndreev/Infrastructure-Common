BeforeAll {
    $root   = [IO.Path]::Combine($PSScriptRoot, '..', 'Infrastructure.Common')
    $psd1   = [IO.Path]::Combine($root, 'Infrastructure.Common.psd1')
    $psm1   = [IO.Path]::Combine($root, 'Infrastructure.Common.psm1')

    $script:manifest    = Import-PowerShellDataFile $psd1
    $script:psm1Content = Get-Content $psm1 -Raw

    # Convention: filename == function name (e.g. ConvertTo-Array.ps1).
    $script:publicFns = Get-ChildItem `
        -Path   ([IO.Path]::Combine($root, 'Public')) `
        -Filter '*.ps1' |
        Select-Object -ExpandProperty BaseName
}

Describe 'Infrastructure.Common module registration' {

    It 'all Public functions are listed in FunctionsToExport' {
        $missing = $script:publicFns |
            Where-Object { $_ -notin $script:manifest.FunctionsToExport }
        $missing | Should -BeNullOrEmpty
    }

    It 'all Public functions are dot-sourced in the psm1' {
        $missing = $script:publicFns |
            Where-Object { $script:psm1Content -notmatch [regex]::Escape("$_.ps1") }
        $missing | Should -BeNullOrEmpty
    }

    It 'all Public functions are in Export-ModuleMember' {
        $missing = $script:publicFns |
            Where-Object { $script:psm1Content -notmatch [regex]::Escape($_) }
        $missing | Should -BeNullOrEmpty
    }
}
