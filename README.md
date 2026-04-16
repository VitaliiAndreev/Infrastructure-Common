# Infrastructure-Common

Shared PowerShell module providing common utilities for the
`Infrastructure-*` polyrepo family.

## Index

- [Overview](#overview)
- [Installation](#installation)
- [Publishing](#publishing)
- [API reference](#api-reference)
- [Repo structure](#repo-structure)

---

## Overview

Provides utilities used by all infrastructure repos so the logic does not
need to be duplicated and tested in each one independently:

- **`Assert-RequiredProperties`** - validates that a PSCustomObject has all
  required properties present and non-empty; collects every violation before
  throwing so the consumer sees the full picture in one run.
- **`Invoke-ModuleInstall`** - installs a module from PSGallery if absent or
  below the required minimum version, then imports it.

### Bootstrap note

`Invoke-ModuleInstall` cannot install itself. Each consumer script that needs
this module must include a short inline guard to install `Infrastructure.Common`
first — this is a one-time cost per script, and all other module installs then
flow through `Invoke-ModuleInstall`.

```powershell
# Inline bootstrap - cannot use Invoke-ModuleInstall to install itself.
$_common = Get-Module -ListAvailable -Name Infrastructure.Common |
    Sort-Object Version -Descending | Select-Object -First 1
if (-not $_common -or $_common.Version -lt [Version]'1.1.0') {
    Install-Module Infrastructure.Common -Scope CurrentUser -Force
}
Import-Module Infrastructure.Common -Force -ErrorAction Stop
```

---

## Installation

Consuming repos install automatically from PSGallery via the bootstrap block
above — no manual step needed.

To install manually:

```powershell
Install-Module Infrastructure.Common -Scope CurrentUser
```

To update an existing installation:

```powershell
Update-Module Infrastructure.Common
```

**For local development of this module:** use `Install.ps1` to install from
source instead of PSGallery.

---

## Publishing

Publishing is fully automated via GitHub Actions.

**To ship a new version:**

1. Bump `ModuleVersion` in [Infrastructure.Common/Infrastructure.Common.psd1](Infrastructure.Common/Infrastructure.Common.psd1)
2. Open a PR, get it reviewed and merged

On merge, [.github/workflows/tag.yml](.github/workflows/tag.yml) runs both
the unit and integration test workflows, creates a matching git tag, then
calls [.github/workflows/publish.yml](.github/workflows/publish.yml) to
publish to PSGallery. No manual tagging step required.

**One-time setup:** add your PSGallery API key as a repository secret named
`PSGALLERY_API_KEY` under Settings -> Secrets and variables -> Actions.
Generate a key at [powershellgallery.com/account/apikeys](https://www.powershellgallery.com/account/apikeys).

---

## API reference

### `Assert-RequiredProperties`

Validates that a PSCustomObject has all required properties present and
non-empty. All violations are collected before throwing so the consumer
sees the full picture in one run rather than fixing one field at a time.

| Parameter      | Type          | Required | Description                                              |
|----------------|---------------|----------|----------------------------------------------------------|
| `-Object`      | object        | Yes      | The PSCustomObject to validate (e.g. a config entry)     |
| `-Properties`  | string[]      | Yes      | Property names that must be present and non-empty        |
| `-Context`     | string        | Yes      | Identifies the object in error messages, e.g. `"VM 'ubuntu-01'"` |

```powershell
Assert-RequiredProperties -Object $vm `
    -Properties @('vmName', 'ipAddress') `
    -Context "VM '$($vm.vmName)'"
```

---

### `Invoke-ModuleInstall`

Installs a module from PSGallery if absent or below the minimum required
version, then imports it.

| Parameter        | Type    | Required | Description                                                     |
|------------------|---------|----------|-----------------------------------------------------------------|
| `-ModuleName`    | string  | Yes      | The module to install and import                                 |
| `-MinimumVersion`| Version | No       | Minimum acceptable version; any installed version accepted if omitted |

```powershell
# Install with a minimum version constraint
Invoke-ModuleInstall -ModuleName 'Infrastructure.Secrets' -MinimumVersion '1.2.0'

# Install if absent, accept any version
Invoke-ModuleInstall -ModuleName 'Posh-SSH'
```

---

## Repo structure

```
Infrastructure-Common/
|- Infrastructure.Common/
|  |- Public/
|  |  |- Assert-RequiredProperties.ps1
|  |  `- Invoke-ModuleInstall.ps1
|  |- Infrastructure.Common.psm1        # Dot-sources Public\ and exports functions
|  `- Infrastructure.Common.psd1        # Module manifest (version, GUID, exports)
|- Tests/
|  |- Public/                           # Unit tests mirroring production layout
|  `- Integration/                      # Integration tests - run in Docker only
|- .github/
|  |- actions/
|  |  |- tag-from-manifest/
|  |  |  |- action.yml                  # Creates git tag from manifest version
|  |  |  `- Invoke-TagFromManifest.ps1
|  |  |- run-unit-tests/
|  |  |  |- action.yml                  # Reusable composite action for unit tests
|  |  |  `- Run-Tests.ps1              # Canonical unit test runner implementation
|  |  `- run-integration-tests/
|  |     |- action.yml                  # Reusable composite action for integration tests
|  |     `- Run-IntegrationTests.ps1   # Canonical integration test runner implementation
|  `- workflows/
|     |- ci-powershell.yml        # Shared unit test workflow - reusable by other repos
|     |- ci-powershell-docker.yml # Shared integration test workflow - reusable by other repos
|     |- tag.yml                  # Fires on manifest change - runs CI then tags and publishes
|     `- publish.yml              # Reusable publish workflow - called by tag.yml
|- Install.ps1               # Installs from source for local development
|- Publish.ps1               # Publishes to PSGallery (called by publish.yml)
|- Run-Tests.ps1             # Runs unit tests locally (thin wrapper)
|- Run-IntegrationTests.ps1  # Runs integration tests locally in Docker (thin wrapper)
`- README.md
```
