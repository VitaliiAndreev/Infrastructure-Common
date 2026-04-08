BeforeAll {
    . "$PSScriptRoot\..\Infrastructure.Common\Public\Assert-RequiredProperties.ps1"

    # Builds a PSCustomObject from a hashtable - mirrors what ConvertFrom-Json
    # produces so tests reflect real consumer usage.
    function New-TestObject([hashtable] $props) {
        [PSCustomObject] $props
    }
}

Describe 'Assert-RequiredProperties' {

    Context 'when all required properties are present and non-empty' {

        It 'does not throw' {
            $obj = New-TestObject @{ vmName = 'ubuntu-01'; ipAddress = '10.0.0.1' }
            { Assert-RequiredProperties -Object $obj `
                -Properties @('vmName', 'ipAddress') `
                -Context 'VM' } | Should -Not -Throw
        }

        It 'accepts numeric properties (cpuCount, etc.)' {
            # Numeric values must be cast to [string] internally before
            # IsNullOrWhiteSpace - this test catches regressions on that path.
            $obj = New-TestObject @{ cpuCount = 4; vmName = 'node-01' }
            { Assert-RequiredProperties -Object $obj `
                -Properties @('cpuCount', 'vmName') `
                -Context 'VM' } | Should -Not -Throw
        }
    }

    Context 'when a required property is missing' {

        It 'throws naming the missing property' {
            $obj = New-TestObject @{ vmName = 'ubuntu-01' }
            { Assert-RequiredProperties -Object $obj `
                -Properties @('vmName', 'ipAddress') `
                -Context "VM 'ubuntu-01'" } |
                Should -Throw -ExpectedMessage "*missing required property 'ipAddress'*"
        }

        It 'includes the Context string in the error' {
            $obj = New-TestObject @{ vmName = 'ubuntu-01' }
            { Assert-RequiredProperties -Object $obj `
                -Properties @('ipAddress') `
                -Context "VM 'ubuntu-01'" } |
                Should -Throw -ExpectedMessage "*VM 'ubuntu-01'*"
        }
    }

    Context 'when a required property is an array' {

        It 'does not throw when a required array property is non-empty' {
            $obj = New-TestObject @{ items = @('a', 'b') }
            { Assert-RequiredProperties -Object $obj `
                -Properties @('items') `
                -Context 'VM' } | Should -Not -Throw
        }

        It 'does not throw when the array contains PSCustomObjects (real ConvertFrom-Json output)' {
            $obj = New-TestObject @{
                users = @(
                    [PSCustomObject]@{ username = 'u-deploy'; shell = '/bin/bash' }
                )
            }
            { Assert-RequiredProperties -Object $obj `
                -Properties @('users') `
                -Context 'VM' } | Should -Not -Throw
        }

        It 'throws on an empty array' {
            # [string](@()) = "" so the old IsNullOrWhiteSpace approach would
            # also catch this, but for the wrong reason. Count-based detection
            # is explicit and handles all collection types uniformly.
            $obj = New-TestObject @{ items = @() }
            { Assert-RequiredProperties -Object $obj `
                -Properties @('items') `
                -Context 'VM' } |
                Should -Throw -ExpectedMessage "*empty required property 'items'*"
        }
    }

    Context 'when a required property is empty or whitespace' {

        It 'throws on an empty string' {
            $obj = New-TestObject @{ vmName = '' }
            { Assert-RequiredProperties -Object $obj `
                -Properties @('vmName') `
                -Context 'VM' } |
                Should -Throw -ExpectedMessage "*empty required property 'vmName'*"
        }

        It 'throws on a whitespace-only string' {
            $obj = New-TestObject @{ vmName = '   ' }
            { Assert-RequiredProperties -Object $obj `
                -Properties @('vmName') `
                -Context 'VM' } |
                Should -Throw -ExpectedMessage "*empty required property 'vmName'*"
        }

        It 'throws on a tab-only string' {
            $obj = New-TestObject @{ vmName = "`t" }
            { Assert-RequiredProperties -Object $obj `
                -Properties @('vmName') `
                -Context 'VM' } |
                Should -Throw -ExpectedMessage "*empty required property 'vmName'*"
        }

        It 'throws on a null property value' {
            # ConvertFrom-Json can produce $null for omitted optional fields;
            # [string]$null coerces to "" so IsNullOrWhiteSpace catches it.
            $obj = New-TestObject @{ vmName = $null }
            { Assert-RequiredProperties -Object $obj `
                -Properties @('vmName') `
                -Context 'VM' } |
                Should -Throw -ExpectedMessage "*empty required property 'vmName'*"
        }
    }

    Context 'when multiple properties fail validation' {

        It 'reports all failing properties in a single throw' {
            # All properties are checked before throwing so the consumer sees
            # the full picture in one run rather than fixing one field at a time.
            $obj = New-TestObject @{ vmName = 'node-01' }
            { Assert-RequiredProperties -Object $obj `
                -Properties @('missingA', 'vmName', 'missingB') `
                -Context 'VM' } |
                Should -Throw -ExpectedMessage "*missing required property 'missingA'*"
        }

        It 'includes every failing property name when multiple are missing' {
            $obj = New-TestObject @{ vmName = 'node-01' }
            $threw = $false
            try {
                Assert-RequiredProperties -Object $obj `
                    -Properties @('missingA', 'vmName', 'missingB') `
                    -Context 'VM'
            }
            catch {
                $threw = $true
                $_.Exception.Message | Should -Match 'missingA'
                $_.Exception.Message | Should -Match 'missingB'
            }
            $threw | Should -BeTrue
        }

        It 'reports both missing and empty properties together' {
            # A missing property and a blank property on the same object
            # must both appear in the single thrown message.
            $obj = New-TestObject @{ emptyProp = '' }
            $threw = $false
            try {
                Assert-RequiredProperties -Object $obj `
                    -Properties @('missingProp', 'emptyProp') `
                    -Context 'VM'
            }
            catch {
                $threw = $true
                $_.Exception.Message | Should -Match 'missingProp'
                $_.Exception.Message | Should -Match 'emptyProp'
            }
            $threw | Should -BeTrue
        }

        It 'does not throw when only some properties pass (the passing ones are silent)' {
            # Verify that passing properties do not produce noise - only
            # failures are reported.
            $obj = New-TestObject @{ good = 'value'; bad = '' }
            { Assert-RequiredProperties -Object $obj `
                -Properties @('good', 'bad') `
                -Context 'VM' } |
                Should -Throw -ExpectedMessage "*empty required property 'bad'*"
        }
    }
}
