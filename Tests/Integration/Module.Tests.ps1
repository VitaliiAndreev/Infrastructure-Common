BeforeAll {
    $psd1 = [IO.Path]::Combine(
        $PSScriptRoot, '..', '..', 'Infrastructure.Common', 'Infrastructure.Common.psd1')
    Import-Module (Resolve-Path $psd1).Path -Force -ErrorAction Stop
    $Script:Manifest = Import-PowerShellDataFile (Resolve-Path $psd1).Path
}

Describe 'Infrastructure.Common module exports' -Tag 'Integration' {

    It 'all FunctionsToExport are callable after Import-Module' {
        # A function missing from Export-ModuleMember in the psm1 would appear
        # in FunctionsToExport (psd1) but fail Get-Command here.
        $notFound = $Script:Manifest.FunctionsToExport | Where-Object {
            -not (Get-Command $_ -Module Infrastructure.Common -ErrorAction SilentlyContinue)
        }
        $notFound | Should -BeNullOrEmpty
    }
}
