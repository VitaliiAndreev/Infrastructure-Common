# Common-PowerShell

Shared PowerShell functions and reusable PowerShell centric GitHub composite actions and workflows.

## Index

- [Requirements](#requirements)
- [Overview](#overview)
- [Installation](#installation)
- [Publishing](#publishing)
  - [Shipping a module release (PSGallery)](#shipping-a-module-release-psgallery)
  - [Shipping an action / workflow release (for `@vN` consumers)](#shipping-an-action--workflow-release-for-vn-consumers)
- [API reference](#api-reference)
  - Top-level utilities
    - [Assert-RequiredProperties](#assert-requiredproperties)
    - [ConvertTo-Array](#convertto-array)
    - [Invoke-ModuleInstall](#invoke-moduleinstall)
  - Retry (`Public/Retry/`)
    - Loop
      - [Invoke-WithExitCodeRetry](#invoke-withexitcoderetry)
      - [Invoke-WithRetry](#invoke-withretry)
    - Transient-error strategies (`Public/Retry/TransientErrorStrategies/`)
      - [New-TransientNetworkRetryStrategy](#new-transientnetworkretrystrategy)
      - [New-FileLockRetryStrategy](#new-filelockretrystrategy)
      - [New-TransientPowerShellModuleInstallRetryStrategy](#new-transientpowershellmoduleinstallretrystrategy)
    - Backoff strategies (`Public/Retry/BackoffStrategies/`)
      - [New-ExponentialBackoffStrategy](#new-exponentialbackoffstrategy)
      - [New-LinearBackoffStrategy](#new-linearbackoffstrategy)
      - [New-ConstantBackoffStrategy](#new-constantbackoffstrategy)
      - [New-CustomBackoffStrategy](#new-custombackoffstrategy)
  - Timing tree (`Public/Timing/`)
    - [New-TimingSpanTree](#new-timingspantree)
    - [Initialize-TimingSpanTree](#initialize-timingspantree)
    - [Measure-TimingSpan](#measure-timingspan)
    - [Add-TimingSpanDuration](#add-timingspanduration)
    - [Export-TimingSpanTree](#export-timingspantree)
    - [Import-TimingSpanTree](#import-timingspantree)
- [Reusable CI](#reusable-ci)
- [Repo structure](#repo-structure)

---

## Requirements

PowerShell 7+ (`pwsh`).

---

## Overview

Provides cross-cutting utilities used by all infrastructure repos so the logic
does not need to be duplicated and tested in each one independently. Functions
are grouped on disk by concern; the retry family lives under
`Public/Retry/`.

**Top-level utilities**
- **`Assert-RequiredProperties`** - validates that a PSCustomObject has all
  required properties present and non-empty; collects every violation before
  throwing so the consumer sees the full picture in one run.
- **`ConvertTo-Array`** - ensures a value is always an array regardless of
  whether PowerShell unrolled a single-item collection.
- **`Invoke-ModuleInstall`** - installs a module from PSGallery if absent or
  below the required minimum version, then imports it.

**Retry (`Public/Retry/`)** - subdivided by strategy category so each
folder stays small as more factories land:

- *Loop (root of `Public/Retry/`)*
  - **`Invoke-WithExitCodeRetry`** - exit-code counterpart for native
    commands (`netsh`, `git`, `docker`, `wsl`, ...) that fail via
    `$LASTEXITCODE` rather than a thrown exception. Reuses the same backoff
    strategies; retries any non-zero exit by default, or only a
    caller-supplied `-RetryableExitCode` set. For predicate-based
    classification, throw and use `Invoke-WithRetry` instead.
  - **`Invoke-WithRetry`** - generic retry loop. Consumes hashtable-shaped
    retry strategies (`ShouldRetry` classifiers) and a backoff strategy
    (`GetDelay` provider). Multiple retry strategies are OR-composed so a
    single call can cover several legitimately-transient failure classes
    (e.g. network + file-lock). Defaults to exponential backoff when none
    is supplied.
- *Transient-error strategies (`Public/Retry/TransientErrorStrategies/`)* - factories that
  return `@{ Name; ShouldRetry }` classifiers consumed by
  `Invoke-WithRetry`. Compose multiple via `-RetryStrategy`
  when a single call legitimately touches several transient-failure
  classes (e.g. network + file-lock).
  - **`New-TransientNetworkRetryStrategy`** - matches DNS/socket/5xx.
  - **`New-FileLockRetryStrategy`** - matches `System.IO.IOException`
    (Hyper-V VMMS handle-release case).
  - **`New-TransientPowerShellModuleInstallRetryStrategy`** - matches
    PSGallery source-resolution flakes from `Install-Module` /
    `Install-Package`. OR-compose with the network strategy for the
    full transient surface.
- *Backoff strategies (`Public/Retry/BackoffStrategies/`)* - factories
  that return `@{ Name; GetDelay }` providers consumed by
  `Invoke-WithRetry` via `-BackoffStrategy`. Pick the curve that
  matches the underlying failure; reach for `New-CustomBackoffStrategy`
  when the built-ins do not (HTTP 429 `Retry-After`, jittered
  exponential, deadline-aware backoff, ...).
  - **`New-ExponentialBackoffStrategy`** - doubles each attempt up to a
    cap. Sensible default for most call sites.
  - **`New-LinearBackoffStrategy`** - grows linearly per attempt up to
    a cap. Predictable spacing when exponential ramps up too fast.
  - **`New-ConstantBackoffStrategy`** - same delay every attempt. Use
    when the failure has a known fixed recovery window.
  - **`New-CustomBackoffStrategy`** - wraps a caller-supplied
    `GetDelay` script block in the standard hashtable shape.

**Timing tree (`Public/Timing/`)** - an arbitrary-depth instrumentation
framework: a context object owns a nested span tree so timings can nest to
any depth and cross a process boundary as JSON. A context, rather
than a module-scoped global, lets two trees (e.g. an orchestrator's own tree
and one imported from a child process) coexist in one process.

- **`New-TimingSpanTree`** - creates the root node and returns the context
  that owns the tree and its current-node stack.
- **`Initialize-TimingSpanTree`** - optionally pre-declares a nested skeleton
  so branches that never run still render (as `SKIPPED`) instead of vanishing.
- **`Measure-TimingSpan`** - times a script block as a span under the current
  node; accumulates by name-within-parent, marks terminal status
  (`OK`/`Failed`, sticky-Failed), and lets exceptions propagate unchanged.
- **`Add-TimingSpanDuration`** - the measure-less counterpart for callers that
  already have an elapsed value to fold in.
- **`Export-TimingSpanTree`** / **`Import-TimingSpanTree`** - the cross-process
  handoff: Export serialises a tree to the versioned nested-JSON schema
  (`e2e-timing/v1`); Import rebuilds it defensively (missing/malformed ->
  `$null` + warning, never throws) so a parent can graft a child's timings.

This repo is also the canonical home of the reusable CI workflows and composite
actions that every infrastructure module shares - see
[Reusable CI](#reusable-ci).

### Bootstrap note

`Invoke-ModuleInstall` cannot install itself. Each consumer script that needs
this module must include a short inline guard to install `Common.PowerShell`
first - this is a one-time cost per script, and all other module installs then
flow through `Invoke-ModuleInstall`.

```powershell
# Inline bootstrap - cannot use Invoke-ModuleInstall to install itself.
$_common = Get-Module -ListAvailable -Name Common.PowerShell |
    Sort-Object Version -Descending | Select-Object -First 1
if (-not $_common -or $_common.Version -lt [Version]'4.0.1') {
    Install-Module Common.PowerShell -Scope CurrentUser -Force
    # Re-query so the comparison below uses the freshly installed version.
    $_common = Get-Module -ListAvailable -Name Common.PowerShell |
        Sort-Object Version -Descending | Select-Object -First 1
}
# Reload only when the loaded state differs from the target (multiple
# versions live, or wrong version live). Mirrors the conditional in
# Invoke-ModuleInstall - inlined here because the bootstrap installs
# the very module that defines that function.
$_loaded = @(Get-Module -Name Common.PowerShell)
if ($_loaded.Count -ne 1 -or $_loaded[0].Version -ne $_common.Version) {
    if ($_loaded) { $_loaded | Remove-Module -Force }
    Import-Module Common.PowerShell -Force -ErrorAction Stop
}
```

---

## Installation

Consuming repos install automatically from PSGallery via the bootstrap block
above - no manual step needed.

To install manually:

```powershell
Install-Module Common.PowerShell -Scope CurrentUser
```

To update an existing installation:

```powershell
Update-Module Common.PowerShell
```

**For local development of this module:** use `scripts\Install.ps1` to install
from source instead of PSGallery.

---

## Publishing

This repo carries **two independent tag streams** that share the git repo
but not the version numbering. Each has its own release flow.

| Stream | Tag shape | Driven by | Consumed by |
|---|---|---|---|
| Module | `X.Y.Z` (e.g. `6.0.0`) | Automated: `tag-from-manifest` on `.psd1` bump | `Install-Module Common.PowerShell` from PSGallery |
| Actions | `vX.Y.Z` + rolling `vX` (e.g. `v7.0.0`, `v7`) | Manual: [scripts/Publish-VersionTags.ps1](scripts/Publish-VersionTags.ps1) | Other repos pinning `uses: Klark-Morrigan/Common-PowerShell/.github/.../<name>@vN` |

The two namespaces never collide (`7.0.0` and `v7.0.0` are different tag
names), so each stream can advance on its own cadence. Numbers across
streams may drift; they are not required to align.

### Shipping a module release (PSGallery)

1. Bump `ModuleVersion` in [Common.PowerShell/Common.PowerShell.psd1](Common.PowerShell/Common.PowerShell.psd1)
2. Promote the `## [Unreleased]` section in [CHANGELOG.md](CHANGELOG.md) to
   `## [X.Y.Z] - <date>` (matching the new version), open a fresh empty
   `[Unreleased]` above it, and add the footer compare link
3. Open a PR, get it reviewed and merged

On merge, [.github/workflows/release.yml](.github/workflows/release.yml)
checks the version is **not yet on PSGallery** (the gallery, not the git tag,
is the source of truth for "already released"), **asserts the manifest and
changelog agree on `X.Y.Z`** (the `assert-changelog-version` action - the
release fails here if you forgot to promote the changelog), runs the unit +
integration tests, then creates a matching `X.Y.Z` git tag, publishes to
PSGallery, and creates a **GitHub Release** whose body is the `X.Y.Z`
CHANGELOG.md section (Common-Automation's `create-github-release`). No manual
tagging or release-notes step required.

Each tail step is idempotent against its real artifact, so the pipeline is
**self-healing**: if publish fails, the tag stays but the version is still
absent from the gallery, so simply re-running the release (or
`Re-run failed jobs`) re-publishes instead of skipping. Publish self-skips a
version already on the gallery, and the GitHub Release is skipped if it already
exists - so a retry never double-publishes or errors on a duplicate, and a
stuck tag can no longer block a release.

Add entries under `[Unreleased]` as you merge feature work, so step 2 at
release time is only the rename. GitHub Releases attach to this module
(`X.Y.Z`) stream; the `vN` actions stream below stays release-free - those
tags are ref pins, not published artifacts.

**One-time setup:** add your PSGallery API key as a repository secret named
`PSGALLERY_API_KEY` under Settings -> Secrets and variables -> Actions.
Generate a key at [powershellgallery.com/account/apikeys](https://www.powershellgallery.com/account/apikeys).

### Shipping an action / workflow release (for `@vN` consumers)

When you change a reusable workflow under `.github/workflows/` or a
composite action under `.github/actions/`, downstream repos pinning
`uses: …@vN` will not see the change until you publish new action tags.
Run from any branch:

```powershell
.\scripts\Publish-VersionTags.ps1 -Version vX.Y.Z
```

It resolves `origin/master` to an explicit commit SHA, creates the
immutable `vX.Y.Z` tag (refuses to re-point), and force-moves the rolling
`vX` tag to that SHA. Consumers on `@vX` automatically get the new release
on their next workflow run; consumers can pin to `@vX.Y.Z` for an
immutable reference.

Triggering is intentionally manual so PSGallery does not receive a module
release for what is purely a CI / workflow change.

---

## API reference

Functions are grouped on disk by concern. Top-level utilities sit at the
root of `Public/`; the retry family lives under `Public/Retry/` and is
further subdivided into `TransientErrorStrategies/` and (in a later
step) `BackoffStrategies/`.

### Top-level utilities

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

### `ConvertTo-Array`

Wraps a value in a single-element array if PowerShell unrolled it down to a
scalar, and returns an existing array unchanged. Use after any pipeline or
`ConvertFrom-Json` call where a one-item result must still be enumerable.

| Parameter   | Type   | Required | Description                          |
|-------------|--------|----------|--------------------------------------|
| `-Value`    | object | Yes      | The value to normalise to an array   |

```powershell
$entries = ConvertTo-Array ($json | ConvertFrom-Json)
foreach ($entry in $entries) { ... }   # safe even when $json had one element
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
Invoke-ModuleInstall -ModuleName 'Pester' -MinimumVersion '5.0'

# Install if absent, accept any version
Invoke-ModuleInstall -ModuleName 'Posh-SSH'
```

---

### Retry (`Public/Retry/`)

#### Loop

### `Invoke-WithExitCodeRetry`

Exit-code counterpart to `Invoke-WithRetry`. Native commands (`netsh`,
`git`, `docker`, `wsl`, ...) signal failure through `$LASTEXITCODE`, not
exceptions, so `Invoke-WithRetry`'s `ShouldRetry` predicates cannot
classify them. This loop reads `$LASTEXITCODE` after each attempt and
reuses the same backoff strategies.

Contract: the script block's final statement must be the native command
whose exit code matters - `$LASTEXITCODE` is read immediately after the
block returns. Thrown exceptions are not retried here; use
`Invoke-WithRetry` for exception-classified retry.

Retriability is intentionally limited to a data-driven exit-code set
(`-RetryableExitCode`), keeping the function true to "retry on the exit
code". For anything a set cannot express - "retry all except these
permanent codes", ranges, classifying on stderr - throw inside the
script block and use `Invoke-WithRetry`, whose `ShouldRetry` strategies
are the home for predicate-based classification.

| Parameter            | Type        | Required | Description                                                                                                                |
|----------------------|-------------|----------|----------------------------------------------------------------------------------------------------------------------------|
| `-ScriptBlock`       | scriptblock | Yes      | The work to attempt. Its pipeline output is the return value on success (exit 0).                                          |
| `-BackoffStrategy`   | hashtable   | No       | A `@{ Name; GetDelay }` strategy. `GetDelay` receives `(attempt, $null)` - exit-code failures carry no `ErrorRecord`, so the same strategies that pair with `Invoke-WithRetry` work unchanged. Defaults to `New-ExponentialBackoffStrategy`. |
| `-MaxAttempts`       | int         | No       | Total attempts including the first. Defaults to `3`. Pass `1` to disable retry.                                            |
| `-RetryableExitCode` | int[]       | No       | Exit codes that count as retryable. Empty (default) means any non-zero. Pass a set to retry only those, fail fast on the rest. |
| `-OperationName`     | string      | No       | Label surfaced in the per-retry warning and failure message. Defaults to `native command`.                                |

```powershell
# Refresh a netsh portproxy rule, absorbing a transient iphlpsvc hiccup.
Invoke-WithExitCodeRetry `
    -OperationName 'netsh portproxy add' `
    -ScriptBlock {
        & netsh interface portproxy add v4tov4 `
            listenaddress=0.0.0.0 listenport=2222 `
            connectaddress=192.168.137.10 connectport=22 | Out-Null
    }
```

---

### `Invoke-WithRetry`

Generic retry loop. The classification of "what counts as retryable" is
supplied by hashtable-shaped retry strategies (`ShouldRetry`
predicates); the inter-attempt pacing comes from a backoff strategy
(`GetDelay` provider). Multiple retry strategies are OR-composed: if
any predicate returns `$true`, the loop retries; if none match, the
failure propagates immediately. The matched strategy's `Name` is
surfaced in the per-retry warning so operators can tell which policy
fired when several are composed.

`-BackoffStrategy` defaults to `New-ExponentialBackoffStrategy`
(2s -> 4s -> 8s, capped at 30s) because that policy fits both currently
known call sites (HTTP + file-lock); callers wanting a different curve
pass one explicitly.

| Parameter         | Type          | Required | Description                                                                                  |
|-------------------|---------------|----------|----------------------------------------------------------------------------------------------|
| `-ScriptBlock`    | scriptblock   | Yes      | The work to attempt. Its return value is the function's return value on success.             |
| `-RetryStrategy`  | hashtable[]   | Yes      | One or more `@{ Name; ShouldRetry }` strategies. Mandatory so "never retries" cannot happen silently. |
| `-BackoffStrategy`| hashtable     | No       | A `@{ Name; GetDelay }` strategy. Defaults to `New-ExponentialBackoffStrategy`.              |
| `-MaxAttempts`    | int           | No       | Total attempts including the first. Defaults to `3`. Pass `1` to disable retry.              |
| `-OperationName`  | string        | No       | Label surfaced in the per-retry warning. Defaults to `operation`.                            |

```powershell
# Network call with default exponential backoff.
$json = Invoke-WithRetry `
    -OperationName 'Adoptium release lookup' `
    -RetryStrategy (New-TransientNetworkRetryStrategy) `
    -ScriptBlock   { Invoke-RestMethod $uri }

# File-lock with a tighter attempt budget.
Invoke-WithRetry `
    -OperationName 'delete VHDX' `
    -RetryStrategy (New-FileLockRetryStrategy) `
    -MaxAttempts   5 `
    -ScriptBlock   { Remove-Item $vhdxPath -Force -ErrorAction Stop }
```

---

#### Transient-error strategies (`Public/Retry/TransientErrorStrategies/`)

### `New-TransientNetworkRetryStrategy`

Builds a retry-strategy hashtable matching transient network failures
(DNS hiccups, connection drops, 5xx responses, HttpClient timeouts) for
use with `Invoke-WithRetry`. 4xx HttpResponseExceptions and non-network
errors are treated as permanent so failures stay fast.

Takes no parameters. Returns:

```powershell
@{
    Name        = 'TransientNetwork'
    ShouldRetry = { param($ErrorRecord) <bool> }
}
```

```powershell
Invoke-WithRetry `
    -ScriptBlock   { Invoke-RestMethod $uri } `
    -RetryStrategy (New-TransientNetworkRetryStrategy)
```

---

### `New-FileLockRetryStrategy`

Builds a retry-strategy hashtable matching `System.IO.IOException`
anywhere in the exception chain - the canonical Hyper-V VMMS
handle-release case where `Remove-Item` briefly fails after `Remove-VM`.
`UnauthorizedAccessException` is intentionally **not** matched: ACL
problems will not resolve on their own, and retrying just stalls the
caller before the real error surfaces.

Takes no parameters. Returns:

```powershell
@{
    Name        = 'FileLock'
    ShouldRetry = { param($ErrorRecord) <bool> }
}
```

```powershell
Invoke-WithRetry `
    -ScriptBlock   { Remove-Item -Path $vhdxPath -Force -ErrorAction Stop } `
    -RetryStrategy (New-FileLockRetryStrategy) `
    -MaxAttempts   5
```

---

### `New-TransientPowerShellModuleInstallRetryStrategy`

Builds a retry-strategy hashtable matching transient PSGallery
source-resolution failures emitted by `Install-Module` /
`Install-Package` (e.g. `Unable to resolve package source`). Generic
network failures (DNS, timeout, 5xx) are intentionally out of scope -
OR-compose with `New-TransientNetworkRetryStrategy` to cover both.
Permanent errors (typos, signature mismatches, auth) propagate
immediately so misconfiguration fails fast instead of burning the
full attempt budget.

Takes no parameters. Returns:

```powershell
@{
    Name        = 'TransientPowerShellModuleInstall'
    ShouldRetry = { param($ErrorRecord) <bool> }
}
```

```powershell
Invoke-WithRetry `
    -ScriptBlock   { Install-Module Foo -ErrorAction Stop } `
    -RetryStrategy @(
        (New-TransientPowerShellModuleInstallRetryStrategy),
        (New-TransientNetworkRetryStrategy)
    ) `
    -MaxAttempts   6
```

---

#### Backoff strategies (`Public/Retry/BackoffStrategies/`)

All four factories return the same hashtable shape consumed by
`Invoke-WithRetry` via `-BackoffStrategy`:

```powershell
@{
    Name     = '<curve name>'
    GetDelay = { param($Attempt, $LastError) <seconds> }
}
```

`GetDelay` receives the current attempt number (1-based) and the most
recent `ErrorRecord` so custom providers can adapt the delay to the
failure (HTTP 429 `Retry-After`, deadline-aware backoff, ...).

### `New-ExponentialBackoffStrategy`

Doubles the delay each attempt, capped at a configurable ceiling.
Formula: `delay = min(InitialDelaySeconds * 2^(Attempt - 1), MaxIntervalSeconds)`.
Defaults (2s initial, 30s cap) suit the currently known call sites
(HTTP + file-lock).

| Parameter              | Type | Required | Description                                  |
|------------------------|------|----------|----------------------------------------------|
| `-InitialDelaySeconds` | int  | No       | Seconds before the first retry. Default `2`. |
| `-MaxIntervalSeconds`  | int  | No       | Upper bound per attempt. Default `30`.       |

```powershell
$backoff = New-ExponentialBackoffStrategy -InitialDelaySeconds 1 -MaxIntervalSeconds 10
```

---

### `New-LinearBackoffStrategy`

Grows the delay linearly per attempt up to a cap.
Formula: `delay = min(StepSeconds * Attempt, MaxIntervalSeconds)`.

| Parameter             | Type | Required | Description                                  |
|-----------------------|------|----------|----------------------------------------------|
| `-StepSeconds`        | int  | No       | Increment per attempt. Default `2`.          |
| `-MaxIntervalSeconds` | int  | No       | Upper bound per attempt. Default `30`.       |

```powershell
$backoff = New-LinearBackoffStrategy -StepSeconds 2 -MaxIntervalSeconds 10
# Delays: 2, 4, 6, 8, 10, 10, ...
```

---

### `New-ConstantBackoffStrategy`

Returns the same delay on every attempt. Use when the failure has a
known fixed recovery window (service restart cycle, fixed lease
renewal, ...) and exponential growth would just oversleep.

| Parameter       | Type | Required | Description                          |
|-----------------|------|----------|--------------------------------------|
| `-DelaySeconds` | int  | No       | Delay returned every call. Default `2`. |

```powershell
$backoff = New-ConstantBackoffStrategy -DelaySeconds 5
```

---

### `New-CustomBackoffStrategy`

Wraps a caller-supplied `GetDelay` script block in the standard
backoff-strategy hashtable shape. Escape hatch for cases the built-ins
do not cover (HTTP 429 `Retry-After`, jittered exponential,
deadline-aware backoff).

| Parameter        | Type        | Required | Description                                                                |
|------------------|-------------|----------|----------------------------------------------------------------------------|
| `-DelayProvider` | scriptblock | Yes      | Called as `& $DelayProvider $Attempt $LastError`; must return seconds.     |
| `-Name`          | string      | No       | Label surfaced by `Invoke-WithRetry` in the per-retry warning. Default `Custom`. |

```powershell
$jittered = New-CustomBackoffStrategy -Name 'JitteredExponential' `
    -DelayProvider {
        param($Attempt, $LastError)
        $base = [Math]::Min(2 * [Math]::Pow(2, $Attempt - 1), 30)
        $base + (Get-Random -Minimum 0 -Maximum 2)
    }
```

---

### Timing tree (`Public/Timing/`)

An arbitrary-depth timing framework. Every span is a node
`{ Order; Name; Status; ElapsedMs; Source; Children }`; a *context* object
owns the root node plus a current-node stack, so spans nest simply by running
one `Measure-TimingSpan` inside another. Accumulation is by name-within-parent
(a span run once per VM sums into one node), and `Failed` is sticky (a later
success does not clear an earlier failure). The framework only observes:
exceptions propagate unchanged, so wrapping existing control flow never alters
it.

#### `New-TimingSpanTree`

Creates the root node and returns the context every other timing verb
operates on. The context is `{ Root; Stack; NextOrder }`, with the stack
seeded by the root so the first span attaches as a top-level child.

| Parameter    | Type   | Required | Description                                                     |
|--------------|--------|----------|-----------------------------------------------------------------|
| `-RootName`  | string | Yes      | Display name of the root node; the report's total line.         |
| `-Source`    | string | No       | Optional provenance tag for the root, carried through the merge.|

```powershell
$tree = New-TimingSpanTree -RootName 'runner-lifecycle'
```

---

#### `Initialize-TimingSpanTree`

Optionally pre-declares a nested skeleton under the root so conditionally-run
branches are visibly accounted for (rendered `SKIPPED`) instead of being
absent. Pre-declaration is optional - any span first seen via
`Measure-TimingSpan` / `Add-TimingSpanDuration` is created lazily anyway.

| Parameter   | Type       | Required | Description                                                              |
|-------------|------------|----------|--------------------------------------------------------------------------|
| `-Tree`     | context    | Yes      | The context from `New-TimingSpanTree`.                                    |
| `-Skeleton` | object[]   | Yes      | Nested declaration: plain strings and/or `@{ Name; Children; Source }`.  |

```powershell
Initialize-TimingSpanTree -Tree $tree -Skeleton @(
    'Setup',
    @{ Name = 'Phase 1'; Children = @('boot VM', 'wait for SSH') },
    'Teardown'
)
```

---

#### `Measure-TimingSpan`

Times `-Action` as a span under the current node: finds-or-creates the node,
pushes it (so anything the action itself times nests beneath), accumulates the
elapsed, sets terminal status, and pops on both the success and failure paths.
The action's output streams back to the caller.

| Parameter | Type        | Required | Description                                              |
|-----------|-------------|----------|----------------------------------------------------------|
| `-Tree`   | context     | Yes      | The context from `New-TimingSpanTree`.                   |
| `-Name`   | string      | Yes      | Span name; unique within the current node's children.    |
| `-Action` | scriptblock | Yes      | Work to time. Runs as-is; exceptions propagate.          |
| `-Source` | string      | No       | Provenance tag applied on first creation of the node.    |

```powershell
Measure-TimingSpan -Tree $tree -Name 'Phase 1' -Action {
    Measure-TimingSpan -Tree $tree -Name 'boot VM' -Action { Start-Vm }
}
```

---

#### `Add-TimingSpanDuration`

The measure-less primitive: folds a pre-measured elapsed value into a span
under the current node (no scriptblock, so the span is a leaf contribution).
Same accumulation and sticky-`Failed` semantics as `Measure-TimingSpan`.

| Parameter    | Type    | Required | Description                                             |
|--------------|---------|----------|---------------------------------------------------------|
| `-Tree`      | context | Yes      | The context from `New-TimingSpanTree`.                  |
| `-Name`      | string  | Yes      | Span name; unique within the current node's children.   |
| `-ElapsedMs` | int64   | Yes      | Milliseconds to add to the span's running total.        |
| `-Failed`    | switch  | No       | Mark the span `Failed` (sticky) - the work threw.       |
| `-Source`    | string  | No       | Provenance tag applied on first creation of the node.   |

```powershell
Add-TimingSpanDuration -Tree $tree -Name 'provider: files' -ElapsedMs 1200
```

---

#### `Export-TimingSpanTree`

Serialises a context's whole tree to the versioned nested-JSON schema so
another process can import and graft it. The document is
`{ "schema": "e2e-timing/v1", "root": { ...node... } }` with camelCase keys,
explicit `children[]`, first-class `status`, and invariant-culture numbers
(a subtree graft, not a timestamp trace). The caller owns `-Path`; its parent
directory must exist.

| Parameter | Type    | Required | Description                                             |
|-----------|---------|----------|---------------------------------------------------------|
| `-Tree`   | context | Yes      | The context from `New-TimingSpanTree`.                  |
| `-Path`   | string  | Yes      | Destination JSON file (typically a per-invocation temp).|

```powershell
Export-TimingSpanTree -Tree $tree -Path $env:TIMING_TREE_OUTPUT_PATH
```

---

#### `Import-TimingSpanTree`

Rebuilds a child's export into an in-memory subtree (the same
`List[object]`-backed node shape the live framework mints) for grafting under
a part span. Defensive by contract: a missing, empty, malformed, or root-less
file yields `$null` with a warning and never throws, so a crashed child never
fails the parent's own end-of-run report.

| Parameter | Type   | Required | Description                                            |
|-----------|--------|----------|--------------------------------------------------------|
| `-Path`   | string | Yes      | The JSON file written by `Export-TimingSpanTree`.      |

```powershell
$subtree = Import-TimingSpanTree -Path $childTempPath
if ($null -ne $subtree) { <graft $subtree.Children under the part span> }
```

---

## Reusable CI

The composite actions under `.github/actions/` and the reusable workflows
under `.github/workflows/` are consumed by sibling repos
(`Infrastructure-GitHub`, `Infrastructure-HyperV`, `Infrastructure-Secrets`,
`Infrastructure-GitHubRunners`, ...). They are the canonical implementation;
sibling repos call them via `workflow_call` and `uses:` references to
`@master` rather than duplicating the logic.

| Reusable workflow | Purpose |
|---|---|
| `ci-powershell.yml` | `unit` job (static lints - parse gate, bare-`return @()`, PSScriptAnalyzer - then Pester unit tests on Windows) plus an `integration` job gated behind it (`needs: unit`) that runs Docker-host and SSH-target Pester integration tests on Ubuntu; each integration shape is scanned first and skipped when the repo has no tests for it |
| `tag.yml` | Creates a git tag from the manifest version |
| `publish.yml` | Publishes a module directory to PSGallery |

This repo also *consumes* Common-Automation's reusable lint workflows for its
own YAML and bash surfaces, the same way sibling repos consume the table above:

| Consumer workflow | Delegates to (in `Common-Automation`) |
|---|---|
| `ci-yaml.yml` | `ci-yaml.yml` - actionlint, action-validator, yamllint, ansible-lint (each auto-skips when its surface is absent) |
| `ci-bash.yml` | `ci-bash.yml` - shellcheck on the `scripts/` shims, check-sh-executable, bats |

Run the same checks locally via three sibling shims (Docker required; each shims to
Common-Automation's engine - pointed at this repo through
`COMMON_AUTOMATION_TARGET_REPO` - so local and CI cannot drift). `Common-Automation`
must be a sibling checkout (`..\Common-Automation`):

- `scripts/run-ci-yaml-and-bash.sh` (+ `.bat`) - PRIMARY local entry: runs the full
  lint suite AND the bats tests (local equivalent of this repo's `ci-yaml.yml` +
  `ci-bash.yml`).
- `scripts/run-lint-yaml-and-bash.sh` (+ `.bat`) - run a single half: the LINT half
  only (shellcheck, actionlint, action-validator, yamllint, ansible-lint).
- `scripts/run-tests-bash.sh` (+ `.bat`) - run a single half: the bats TEST half only.

---

## Repo structure

```
Common-PowerShell/
|- Common.PowerShell/
|  |- Private/                          # Module-internal helpers (not exported); mirrors Public\ layout
|  |  |- Retry/
|  |  |  `- Assert-RetryStrategyShape.ps1
|  |  `- Timing/                        # Timing-tree internals (node factory / mint / accumulate / skeleton walk / JSON map)
|  |     |- New-TimingSpanNode.ps1
|  |     |- Resolve-TimingSpanChildNode.ps1
|  |     |- Add-TimingSpanNodeElapsed.ps1
|  |     |- Add-TimingSpanSkeletonBranch.ps1
|  |     |- ConvertTo-TimingSpanExportNode.ps1
|  |     `- ConvertFrom-TimingSpanImportNode.ps1
|  |- Public/
|  |  |- Assert-RequiredProperties.ps1
|  |  |- ConvertTo-Array.ps1
|  |  |- Invoke-ModuleInstall.ps1
|  |  |- Retry/                         # Retry family (loop + strategies)
|  |  |  |- Invoke-WithRetry.ps1             # generic retry loop
|  |  |  |- TransientErrorStrategies/       # ShouldRetry classifiers
|  |  |  |  |- New-FileLockRetryStrategy.ps1
|  |  |  |  |- New-TransientNetworkRetryStrategy.ps1
|  |  |  |  `- New-TransientPowerShellModuleInstallRetryStrategy.ps1
|  |  |  `- BackoffStrategies/              # GetDelay providers
|  |  |     |- New-ConstantBackoffStrategy.ps1
|  |  |     |- New-CustomBackoffStrategy.ps1
|  |  |     |- New-ExponentialBackoffStrategy.ps1
|  |  |     `- New-LinearBackoffStrategy.ps1
|  |  `- Timing/                        # Arbitrary-depth timing framework (model + accumulation + JSON handoff)
|  |     |- New-TimingSpanTree.ps1
|  |     |- Initialize-TimingSpanTree.ps1
|  |     |- Measure-TimingSpan.ps1
|  |     |- Add-TimingSpanDuration.ps1
|  |     |- Export-TimingSpanTree.ps1
|  |     `- Import-TimingSpanTree.ps1
|  |- Common.PowerShell.psm1        # Dot-sources Public\ (recursively); exports Public functions
|  `- Common.PowerShell.psd1        # Module manifest (version, GUID, exports)
|- Tests/                               # One .Tests.ps1 per Public\ fn, mirroring its layout (Retry\, ...)
|  |- ...                               #   plus these CI-helper tests with no Public\ counterpart:
|  |- Find-IntegrationTests.Tests.ps1   # Shared CI helper tests
|  |- Get-UnitTestFiles.Tests.ps1       # run-unit-tests\lib helper
|  |- Invoke-Publish.Tests.ps1
|  |- Invoke-TagFromManifest.Tests.ps1
|  |- Limit-TestLogRetention.Tests.ps1  # run-unit-tests\lib helper (+ .IntegrationTests)
|  |- Run-IntegrationTests.Tests.ps1
|  |- Test-ManifestVersionIsNew.Tests.ps1 # check-version-is-new gate helper tests
|  |- Test-NoBareReturnEmptyArray.Tests.ps1
|  |- Test-PowerShellParses.Tests.ps1   # Syntax-gate lint helper tests
|  |- Invoke-PsScriptAnalyzer.Tests.ps1 # PSScriptAnalyzer-gate lint helper tests
|  `- Integration.DockerHost/           # Integration tests - run in Docker only
|- .github/
|  |- actions/                          # Reusable composite actions (canonical)
|  |  |- Helpers.ps1                    # Shared PS helpers dot-sourced by action scripts
|  |  |- check-version-is-new/
|  |  |- tag-from-manifest/
|  |  |- run-unit-tests/                 # Unit test runner (canonical)
|  |  |  |- Run-Tests.ps1                #   Entry point: dispatch + optional self-logging
|  |  |  |- Module.Tests.ps1             #   Shared module-registration test (injected)
|  |  |  `- lib/                         #   Helpers, one per file, dot-sourced
|  |  |     |- Get-UnitTestFiles.ps1     #     Discovers unit test files (excludes Docker dirs)
|  |  |     |- Invoke-UnitTestRun.ps1    #     Installs Pester, runs discovered tests
|  |  |     `- Limit-TestLogRetention.ps1 #   Prunes old logs via Limit-RetainedItem
|  |  |- run-integration-tests/
|  |  |- run-ssh-integration-tests/
|  |  |- scan-integration-tests/
|  |  |- lint-no-bare-return-empty-array/  # Regex lint: bans bare `return @()` (invoked by ci-powershell.yml)
|  |  |- lint-powershell-parses/            # Syntax gate: parses every .ps1/.psm1/.psd1 via the PS parser
|  |  |- lint-powershell-psscriptanalyzer/  # PSScriptAnalyzer gate: full rule set (settings .psd1 = rule SSOT)
|  |  `- publish/
|  `- workflows/                        # Reusable workflows (canonical)
|     |- ci-powershell.yml              # unit + integration (Docker) jobs; integration needs unit
|     |- tag.yml
|     |- publish.yml
|     |- release.yml
|     |- ci-bash.yml                     #   Consumer wrapper -> Common-Automation ci-bash (shellchecks scripts\ shims)
|     `- ci-yaml.yml                     #   Consumer wrapper -> Common-Automation ci-yaml (actionlint/yamllint/...)
|- docs/
|  `- dev/
|     `- implementation/                # Per-feature problem.md + plan.md
|- scripts/                  # User-facing entry-point scripts
|  |- Install.ps1            # Installs from source for local development
|  |- Publish.ps1            # Publishes to PSGallery (called by publish.yml)
|  |- Publish-VersionTags.ps1 # Publishes GitHub Actions vX.Y.Z + rolling vX tags
|  |- Find-GitBashExecutable.ps1     # Helper dot-sourced by Publish-VersionTags
|  |- Run-Tests.ps1          # Runs Pester unit tests locally (thin wrapper)
|  |- Run-IntegrationTests-InDocker.ps1  # Integration tests in Docker
|  |- Run-IntegrationTests-AgainstDockerTarget.ps1
|  |- run-ci-yaml-and-bash.sh / .bat     # PRIMARY local entry: full lint suite + bats tests -> Common-Automation
|  |- run-lint-yaml-and-bash.sh / .bat   # Lint half only (shellcheck/actionlint/action-validator/yamllint/ansible-lint)
|  |- run-tests-bash.sh / .bat           # Bats test half only -> Common-Automation
|  `- fix-permissions.sh / .bat  # Re-stages +x on tracked *.sh via the Common-Automation engine
|- .gitattributes           # Pins *.sh -> LF, *.bat -> CRLF (Linux runners reject CRLF shebangs)
`- README.md
```
