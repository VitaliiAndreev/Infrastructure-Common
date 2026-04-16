<#
.SYNOPSIS
    Runs integration tests in Docker containers.

.DESCRIPTION
    Canonical implementation for the Infrastructure-* polyrepo family.
    Called by the run-integration-tests composite action in CI, and by the
    root-level Run-IntegrationTests.ps1 wrapper for local dev.

    Each *.Tests.ps1 file found under <TestsRoot>\Tests\Integration\ is run
    in its own mcr.microsoft.com/powershell container so integration tests
    never affect the host environment. Local and CI runs use this same script,
    so behaviour is identical in both environments.

    Requires Docker to be available and running. On Windows use Docker Desktop
    with Linux containers; on Linux Docker must be installed on the host.

    Integration tests run under PowerShell 7 only. The mcr.microsoft.com/powershell
    image is Linux-based; PowerShell 5.1 is Windows-only and has no Docker image.
    Unit tests cover 5.1 compatibility via ci-powershell.yml on windows-latest.

.PARAMETER TestsRoot
    Root directory of the repo under test. Tests\Integration\ must be a
    direct descendant.

.EXAMPLE
    .\Run-IntegrationTests.ps1 -TestsRoot C:\a_Code\Infrastructure-Secrets
#>

param(
    [string] $TestsRoot = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Verify Docker is available.
# ---------------------------------------------------------------------------

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error 'docker is not available. Install Docker Desktop and ensure it is running.'
}

# ---------------------------------------------------------------------------
# Discover integration test files.
# ---------------------------------------------------------------------------

$integrationDir = [IO.Path]::Combine($TestsRoot, 'Tests', 'Integration')

$testFiles = Get-ChildItem -Path $integrationDir `
    -Filter '*.Tests.ps1' -Recurse -ErrorAction SilentlyContinue

if (-not $testFiles) {
    Write-Host "No integration test files found under $integrationDir." `
        -ForegroundColor Yellow
    exit 0
}

# ---------------------------------------------------------------------------
# Run each test file in its own container.
#   The repo root is mounted at /repo inside the container. Pester is
#   installed inside the container by each test run - it is not present
#   in the base image. This matches the CI environment exactly.
# ---------------------------------------------------------------------------

# Resolve to an absolute path so the Docker volume mount is unambiguous.
$resolvedRoot = (Resolve-Path $TestsRoot).Path

$failed = 0

foreach ($file in $testFiles) {
    # Build a container-relative path with forward slashes regardless of host
    # OS, e.g. Tests/Integration/Foo.Tests.ps1.
    # GetRelativePath handles both Windows and Linux path separators.
    $relativePath = $file.FullName.Substring($resolvedRoot.Length).TrimStart([IO.Path]::DirectorySeparatorChar)
    $relativePath = $relativePath.Replace('\', '/')
    $containerPath = "/repo/$relativePath"

    Write-Host ''
    Write-Host "---- $($file.Name) ----" -ForegroundColor Cyan

    # The here-string expands $containerPath from the outer (host) scope.
    # Variables prefixed with a backtick are left for the container's
    # PowerShell session to evaluate.
    $command = @"
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -SkipPublisherCheck
Import-Module Pester -MinimumVersion 5.0
`$config = New-PesterConfiguration
`$config.Run.Path         = '$containerPath'
`$config.Output.Verbosity = 'Detailed'
`$config.Run.PassThru     = `$true
`$result = Invoke-Pester -Configuration `$config
if (`$result.FailedCount -gt 0) { exit 1 }
"@

    docker run --rm `
        --volume "${resolvedRoot}:/repo" `
        mcr.microsoft.com/powershell:latest `
        pwsh -Command $command

    if ($LASTEXITCODE -ne 0) {
        Write-Host "$($file.Name) FAILED" -ForegroundColor Red
        $failed++
    }
}

Write-Host ''

if ($failed -gt 0) {
    Write-Host "$failed integration test file(s) failed." -ForegroundColor Red
    exit 1
}

Write-Host 'All integration tests passed.' -ForegroundColor Green
