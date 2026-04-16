<#
.SYNOPSIS
    Runs integration tests for the Infrastructure.Common module in Docker.

.EXAMPLE
    .\Run-IntegrationTests.ps1
#>

& ([IO.Path]::Combine($PSScriptRoot, '.github', 'actions', 'run-integration-tests', 'Run-IntegrationTests.ps1')) `
    -TestsRoot $PSScriptRoot
