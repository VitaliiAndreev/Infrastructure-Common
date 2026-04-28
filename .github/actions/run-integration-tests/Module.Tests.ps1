# Shared module exports integration test, injected by Run-IntegrationTests.ps1
# for every repo in the Infrastructure-* family. The module root is passed via
# the MODULE_TESTS_ROOT environment variable; any RequiredModules declared in
# the manifest are installed from PSGallery before the import is attempted.
BeforeAll {
    $root = $env:MODULE_TESTS_ROOT
    if (-not $root) {
        throw 'MODULE_TESTS_ROOT env var is not set. This file must be run via Run-IntegrationTests.ps1.'
    }

    $psd1Path = Get-ChildItem -Path $root -Filter '*.psd1' |
        Select-Object -First 1 -ExpandProperty FullName

    $Script:Manifest    = Import-PowerShellDataFile $psd1Path
    $Script:ModuleName  = [IO.Path]::GetFileNameWithoutExtension($psd1Path)

    # Install any RequiredModules declared in the manifest so Import-Module
    # does not fail on a missing dependency (e.g. Infrastructure.Common for
    # Infrastructure.Secrets). The guard is necessary because a missing key
    # returns $null, and @($null) would produce a one-element null array.
    if ($Script:Manifest.RequiredModules) {
        foreach ($req in @($Script:Manifest.RequiredModules)) {
            $name = if ($req -is [string]) { $req } else { $req.ModuleName }
            if ($name -and -not (Get-Module -ListAvailable -Name $name)) {
                Install-Module $name -Scope CurrentUser -Force -SkipPublisherCheck
            }
        }
    }

    Import-Module $psd1Path -Force -ErrorAction Stop
}

Describe 'Module exports' -Tag 'Integration' {

    It 'all FunctionsToExport are callable after Import-Module' {
        $notFound = $Script:Manifest.FunctionsToExport | Where-Object {
            -not (Get-Command $_ -Module $Script:ModuleName -ErrorAction SilentlyContinue)
        }
        $notFound | Should -BeNullOrEmpty
    }
}
