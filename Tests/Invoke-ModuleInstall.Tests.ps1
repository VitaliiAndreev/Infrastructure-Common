BeforeAll {
    # Invoke-ModuleInstall has no external dependencies so it can be
    # dot-sourced directly with no stubs required.
    . "$PSScriptRoot\..\Infrastructure.Common\Public\Invoke-ModuleInstall.ps1"
}

Describe 'Invoke-ModuleInstall' {

    BeforeEach {
        Mock Install-Module {}
        Mock Import-Module  {}
    }

    Context 'module not installed' {

        BeforeEach {
            Mock Get-Module {}
        }

        It 'calls Install-Module' {
            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'
            Should -Invoke Install-Module -Times 1 -Exactly
        }

        It 'calls Import-Module' {
            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'
            Should -Invoke Import-Module -Times 1 -Exactly
        }

        It 'passes the correct module name to Install-Module' {
            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'
            Should -Invoke Install-Module -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'Foo'
            }
        }
    }

    Context 'module installed below minimum version' {

        BeforeEach {
            Mock Get-Module {
                [PSCustomObject]@{ Name = 'Foo'; Version = [Version]'0.9.0' }
            }
        }

        It 'calls Install-Module' {
            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'
            Should -Invoke Install-Module -Times 1 -Exactly
        }

        It 'calls Import-Module' {
            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'
            Should -Invoke Import-Module -Times 1 -Exactly
        }
    }

    Context 'module installed at exactly the minimum version' {

        BeforeEach {
            Mock Get-Module {
                [PSCustomObject]@{ Name = 'Foo'; Version = [Version]'1.0.0' }
            }
        }

        It 'does not call Install-Module' {
            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'
            Should -Invoke Install-Module -Times 0
        }

        It 'calls Import-Module' {
            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'
            Should -Invoke Import-Module -Times 1 -Exactly
        }
    }

    Context 'module installed above minimum version' {

        BeforeEach {
            Mock Get-Module {
                [PSCustomObject]@{ Name = 'Foo'; Version = [Version]'2.5.0' }
            }
        }

        It 'does not call Install-Module' {
            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'
            Should -Invoke Install-Module -Times 0
        }

        It 'calls Import-Module' {
            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'
            Should -Invoke Import-Module -Times 1 -Exactly
        }
    }

    Context 'no MinimumVersion specified' {

        It 'installs when the module is absent' {
            Mock Get-Module {}
            Invoke-ModuleInstall -ModuleName 'Foo'
            Should -Invoke Install-Module -Times 1 -Exactly
        }

        It 'does not install when the module is already present' {
            Mock Get-Module {
                [PSCustomObject]@{ Name = 'Foo'; Version = [Version]'0.1.0' }
            }
            Invoke-ModuleInstall -ModuleName 'Foo'
            Should -Invoke Install-Module -Times 0
        }

        It 'always imports the module' {
            Mock Get-Module {
                [PSCustomObject]@{ Name = 'Foo'; Version = [Version]'0.1.0' }
            }
            Invoke-ModuleInstall -ModuleName 'Foo'
            Should -Invoke Import-Module -Times 1 -Exactly
        }
    }

    Context 'multiple versions installed' {

        It 'uses the highest installed version for comparison' {
            # Simulates having both 0.8.0 and 1.1.0 installed.
            # Sort-Object Version -Descending picks 1.1.0, which meets the
            # minimum, so Install-Module must not be called.
            Mock Get-Module {
                @(
                    [PSCustomObject]@{ Name = 'Foo'; Version = [Version]'0.8.0' },
                    [PSCustomObject]@{ Name = 'Foo'; Version = [Version]'1.1.0' }
                )
            }
            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'
            Should -Invoke Install-Module -Times 0
        }
    }
}
