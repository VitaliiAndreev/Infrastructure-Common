BeforeAll {
    . "$PSScriptRoot\..\Infrastructure.Common\Public\ConvertTo-Array.ps1"
}

Describe 'ConvertTo-Array' {

    Context 'scalar input' {

        It 'wraps a single PSCustomObject in an array' {
            $obj = [PSCustomObject]@{ state = 'in_progress' }
            $result = ConvertTo-Array $obj
            $result.Count   | Should -Be 1
            $result[0].state | Should -Be 'in_progress'
        }

        It 'wraps a single string in an array' {
            $result = ConvertTo-Array 'hello'
            $result.Count | Should -Be 1
            $result[0]    | Should -Be 'hello'
        }

        It 'wraps a single integer in an array' {
            $result = ConvertTo-Array 42
            $result.Count | Should -Be 1
            $result[0]    | Should -Be 42
        }
    }

    Context 'collection input' {

        It 'returns the same count for a multi-element array' {
            $arr = @(
                [PSCustomObject]@{ state = 'success' }
                [PSCustomObject]@{ state = 'failure' }
            )
            $result = ConvertTo-Array $arr
            $result.Count | Should -Be 2
        }

        It 'preserves element order' {
            $result = ConvertTo-Array @('a', 'b', 'c')
            $result[0] | Should -Be 'a'
            $result[1] | Should -Be 'b'
            $result[2] | Should -Be 'c'
        }
    }

    Context 'null and empty input' {

        It 'returns an empty array for $null' {
            $result = ConvertTo-Array $null
            $result.Count | Should -Be 0
        }

        It 'returns an empty array for an empty array' {
            $empty = @()
            $result = ConvertTo-Array $empty
            $result.Count | Should -Be 0
        }
    }

    Context 'output type' {

        It 'returns an object that has a Count property regardless of input type' {
            # This is the core guarantee - .Count must never throw.
            $inputs = @(
                [PSCustomObject]@{ id = 1 }
                @([PSCustomObject]@{ id = 1 }, [PSCustomObject]@{ id = 2 })
                $null
                @()
                'string'
            )
            foreach ($input in $inputs) {
                { (ConvertTo-Array $input).Count } | Should -Not -Throw
            }
        }
    }
}
