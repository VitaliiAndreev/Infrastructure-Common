<#
.SYNOPSIS
    Installs Infrastructure.Common locally from source for development use.

.DESCRIPTION
    For development and testing of the module itself only.
    Consuming repos install from PSGallery - they do not call this script.

    Idempotent - skips installation if the module is already up to date.

.EXAMPLE
    .\Install.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleSrc   = Join-Path $PSScriptRoot 'Infrastructure.Common'
$moduleDst   = Join-Path ([Environment]::GetFolderPath('MyDocuments')) `
                   'WindowsPowerShell\Modules\Infrastructure.Common'

$srcVersion  = (Import-PowerShellDataFile `
                    (Join-Path $moduleSrc 'Infrastructure.Common.psd1')).ModuleVersion
$dstManifest = Join-Path $moduleDst 'Infrastructure.Common.psd1'
$dstVersion  = if (Test-Path $dstManifest) {
                   (Import-PowerShellDataFile $dstManifest).ModuleVersion
               } else { $null }

if ($srcVersion -eq $dstVersion) {
    Write-Host "Infrastructure.Common v$srcVersion already installed - skipping." `
        -ForegroundColor Green
    return
}

Write-Host "Installing Infrastructure.Common v$srcVersion from source ..."
if (Test-Path $moduleDst) { Remove-Item $moduleDst -Recurse -Force }
Copy-Item -Path $moduleSrc -Destination $moduleDst -Recurse
Write-Host "Infrastructure.Common v$srcVersion installed." -ForegroundColor Green
