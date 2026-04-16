BeforeAll {
    . "$PSScriptRoot\..\..\Infrastructure.Common\Public\Invoke-ModuleInstall.ps1"
}

Describe 'Invoke-ModuleInstall' -Tag 'Integration' {

    It 'installs an absent module and makes it importable' {
        # Microsoft.PowerShell.SecretManagement is not pre-installed in the
        # base mcr.microsoft.com/powershell container image, making it a
        # reliable absent-module test case. The workflow installs only Pester
        # before running this file.
        $moduleName = 'Microsoft.PowerShell.SecretManagement'
        Remove-Module $moduleName -ErrorAction SilentlyContinue

        Invoke-ModuleInstall -ModuleName $moduleName

        Get-Module -Name $moduleName | Should -Not -BeNullOrEmpty
    }

    It 'does not reinstall a module that already meets the minimum version' {
        # Pester is always present in the test environment. Use it as a
        # reliable already-installed subject. Verify no new version appears
        # after the call (i.e. Install-Module was not invoked).
        $before = (Get-Module -ListAvailable -Name Pester |
            Sort-Object Version -Descending | Select-Object -First 1).Version

        Invoke-ModuleInstall -ModuleName 'Pester' -MinimumVersion '5.0'

        $after = (Get-Module -ListAvailable -Name Pester |
            Sort-Object Version -Descending | Select-Object -First 1).Version

        $after | Should -Be $before
    }
}
