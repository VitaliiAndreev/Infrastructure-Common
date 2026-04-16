<#
.SYNOPSIS
    Runs unit tests for a PowerShell repo.

.DESCRIPTION
    Canonical implementation for the Infrastructure-* polyrepo family.
    Called by the run-unit-tests composite action in CI, and by the
    root-level Run-Tests.ps1 wrapper for local dev.

    Installs Pester 5 if not already present, then runs every *.Tests.ps1
    file found under <TestsRoot>\Tests\, excluding Tests\Integration\ (which
    requires Docker - see run-integration-tests action).

.PARAMETER TestsRoot
    Root directory of the repo under test. Tests\ must be a direct child.

.EXAMPLE
    .\Run-Tests.ps1 -TestsRoot C:\a_Code\Infrastructure-Secrets
#>

param(
    [string] $TestsRoot = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Ensure Pester 5 is available.
#   Pester 3 ships with Windows PowerShell 5.1 and is incompatible with our
#   tests (different API). We require >= 5.0 explicitly.
# ---------------------------------------------------------------------------

$pester = Get-Module -ListAvailable -Name Pester |
    Where-Object { $_.Version.Major -ge 5 } |
    Sort-Object Version -Descending |
    Select-Object -First 1

if (-not $pester) {
    Write-Host 'Pester 5 not found - installing ...' -ForegroundColor Cyan
    Install-Module -Name Pester -MinimumVersion 5.0 `
        -Scope CurrentUser -Force -SkipPublisherCheck
}

Import-Module Pester -MinimumVersion 5.0

# ---------------------------------------------------------------------------
# Discover test files - exclude Tests\Integration\ (Docker only).
# ---------------------------------------------------------------------------

$integrationDir = [IO.Path]::Combine($TestsRoot, 'Tests', 'Integration')
$integrationPath = $null
if (Test-Path $integrationDir) {
    # Normalise so StartsWith works regardless of trailing separator.
    $integrationPath = (Get-Item $integrationDir).FullName.TrimEnd('\') + '\'
}

$testFiles = Get-ChildItem -Path ([IO.Path]::Combine($TestsRoot, 'Tests')) `
    -Filter '*.Tests.ps1' -Recurse -ErrorAction SilentlyContinue |
    Where-Object {
        -not $integrationPath -or
        -not $_.FullName.StartsWith($integrationPath)
    }

# Guard against running with no test files - Pester throws rather than
# returning a result object, which breaks the FailedCount check below.
if (-not $testFiles) {
    Write-Host 'No unit test files found - nothing to run.' -ForegroundColor Yellow
    exit 0
}

$config = New-PesterConfiguration
# Pass individual file paths so Pester does not re-discover the Tests\ folder
# (which would include Integration\ even though it was filtered above).
$config.Run.Path              = @($testFiles.FullName)
$config.Output.Verbosity      = 'Detailed'
$config.TestResult.Enabled    = $true
$config.TestResult.OutputPath = [IO.Path]::Combine($TestsRoot, 'TestResults.xml')
# PassThru is required for Invoke-Pester to return a result object;
# without it the return value is $null and FailedCount cannot be read.
$config.Run.PassThru          = $true

$result = Invoke-Pester -Configuration $config

if ($result.FailedCount -gt 0) {
    Write-Host "$($result.FailedCount) test(s) failed." -ForegroundColor Red
    exit 1
}
