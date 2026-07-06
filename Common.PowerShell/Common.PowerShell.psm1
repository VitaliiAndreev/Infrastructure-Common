<#
.SYNOPSIS
    Shared PowerShell utilities for infrastructure repos.

.DESCRIPTION
    Provides cross-cutting utilities that are not specific to any single
    infrastructure concern (secrets, provisioning, users, etc.).

    Current functions:
    - Assert-RequiredProperties: validates object fields are present and
      non-empty; throws a descriptive error if not.
    - ConvertTo-Array: ensures a value is always an array regardless of
      whether PowerShell unrolled a single-item collection.
    - Invoke-ModuleInstall: installs a PSGallery module if absent or below a
      minimum version, then imports it.
    - Limit-RetainedItem: prunes items in a directory by age and/or count
      (no Windows logrotate equivalent; callers use this for at-write-time
      retention sweeps on log / diag folders).
    - Invoke-WithExitCodeRetry: exit-code counterpart to Invoke-WithRetry
      for native commands (netsh, git, docker, wsl, ...) that fail via
      $LASTEXITCODE rather than a thrown exception. Reuses the same backoff
      strategies.
    - Invoke-WithRetry: generic retry loop that consumes hashtable-shaped
      retry (ShouldRetry) and backoff (GetDelay) strategies. The classifier
      and pacing are caller-supplied; the loop just orchestrates.
    - New-TransientNetworkRetryStrategy: builds a retry-strategy hashtable
      that matches transient network failures, consumed by Invoke-WithRetry.
    - New-FileLockRetryStrategy: builds a retry-strategy hashtable that
      matches System.IO.IOException (file-lock contention, e.g. Hyper-V
      VMMS handle release after Remove-VM).
    - New-ExponentialBackoffStrategy / New-LinearBackoffStrategy /
      New-ConstantBackoffStrategy / New-CustomBackoffStrategy: build
      backoff-strategy hashtables (@{ Name; GetDelay }) consumed by
      Invoke-WithRetry. Custom is the escape hatch for cases the three
      built-ins (exponential / linear / constant) do not cover (HTTP 429
      Retry-After, jittered exponential, ...).
    - New-TimingSpanTree / Initialize-TimingSpanTree / Measure-TimingSpan /
      Add-TimingSpanDuration: the arbitrary-depth timing framework. A context
      object owns a nested span tree (model + accumulation); Measure times a
      scriptblock as a span under the current node, Add feeds a pre-measured
      elapsed, Initialize pre-declares a skeleton so un-run branches still
      render.
    - Export-TimingSpanTree / Import-TimingSpanTree: the cross-process handoff.
      Export serialises a tree to the versioned nested-JSON schema
      ('e2e-timing/v1'); Import rebuilds it defensively (missing/malformed ->
      $null + warning, never throws) so a parent process can graft a child's
      timings under its own tree.
    - Write-TimingSpanReport: renders an N-level tree as a depth-indented,
      single-colour console block (status tag, F2 seconds, percent-of-parent,
      and a total line for the root) - the arbitrary-depth, merge-aware
      counterpart of the 2-level Write-PhaseTimingReport.
    - Initialize-PhaseTimings / Invoke-WithPhaseTimer / Invoke-WithSubStepTimer
      / Add-SubStepDuration / Write-PhaseTimingReport: the 2-level compat
      verbs, re-expressed as thin shims over the timing-tree core and a single
      module-scoped default context. They keep the pre-generalisation
      signatures (no -Tree argument) and byte-identical console report so
      existing call sites migrate to one framework without behaviour change.

    Hyper-V VM helpers (SSH execution, host file server) were moved to the
    Infrastructure.HyperV module to keep this module focused on genuinely
    generic utilities. GitHub API helpers live in Infrastructure.GitHub.
    WSL helpers (Assert-Wsl2Ready, Assert-WslHasBash, Invoke-WslShell)
    moved to Infrastructure.Wsl in 7.0.0; consumers using WSL must now
    Install/Import that module separately.

    Each function lives in its own file under Public\ and is dot-sourced
    below so diffs stay focused on a single function per commit.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Module-internal helpers (not exported). Loaded first so functions
# dot-sourced from Public\ can rely on them at parse / call time.
. "$PSScriptRoot\Private\Retry\Assert-RetryStrategyShape.ps1"

# Timing-tree internals - the single node-mint / accumulate / skeleton-walk
# implementations shared by the Public\Timing\ verbs. Loaded before them so
# the verbs resolve these at call time.
. "$PSScriptRoot\Private\Timing\Add-TimingSpanNodeElapsed.ps1"
. "$PSScriptRoot\Private\Timing\Add-TimingSpanSkeletonBranch.ps1"
. "$PSScriptRoot\Private\Timing\ConvertFrom-TimingSpanImportNode.ps1"
. "$PSScriptRoot\Private\Timing\ConvertTo-TimingSpanExportNode.ps1"
. "$PSScriptRoot\Private\Timing\Format-TimingSpanElapsed.ps1"
. "$PSScriptRoot\Private\Timing\Get-TimingSpanStatusTag.ps1"
. "$PSScriptRoot\Private\Timing\New-TimingSpanNode.ps1"
. "$PSScriptRoot\Private\Timing\Resolve-TimingSpanChildNode.ps1"

# Top-level utilities (no domain grouping yet).
. "$PSScriptRoot\Public\Assert-RequiredProperties.ps1"
. "$PSScriptRoot\Public\ConvertTo-Array.ps1"
. "$PSScriptRoot\Public\Invoke-ModuleInstall.ps1"
. "$PSScriptRoot\Public\Limit-RetainedItem.ps1"

# Retry primitives - grouped because they form a self-contained family
# (loop + predicate strategies + backoff strategies). Subdivided by
# strategy category: TransientErrorStrategies\ for ShouldRetry classifiers
# and BackoffStrategies\ for GetDelay providers. Strategy factories are
# dot-sourced before the loop helpers so the loop's relocated classifier
# helper resolves at module-load time.
. "$PSScriptRoot\Public\Retry\TransientErrorStrategies\New-FileLockRetryStrategy.ps1"
. "$PSScriptRoot\Public\Retry\TransientErrorStrategies\New-TransientPowerShellModuleInstallRetryStrategy.ps1"
. "$PSScriptRoot\Public\Retry\TransientErrorStrategies\New-TransientNetworkRetryStrategy.ps1"
. "$PSScriptRoot\Public\Retry\BackoffStrategies\New-ConstantBackoffStrategy.ps1"
. "$PSScriptRoot\Public\Retry\BackoffStrategies\New-CustomBackoffStrategy.ps1"
. "$PSScriptRoot\Public\Retry\BackoffStrategies\New-ExponentialBackoffStrategy.ps1"
. "$PSScriptRoot\Public\Retry\BackoffStrategies\New-LinearBackoffStrategy.ps1"
. "$PSScriptRoot\Public\Retry\Invoke-WithExitCodeRetry.ps1"
. "$PSScriptRoot\Public\Retry\Invoke-WithRetry.ps1"

# Timing tree - the N-level span framework (nested model + accumulation +
# cross-process JSON export/import + the depth-indented console renderer).
# The 2-level compat verbs (Add-SubStepDuration, Initialize-PhaseTimings,
# Invoke-WithPhaseTimer, Invoke-WithSubStepTimer, Write-PhaseTimingReport)
# are thin shims over this core, sharing one module-scoped default context;
# they preserve the pre-generalisation surface for existing call sites.
. "$PSScriptRoot\Public\Timing\Add-SubStepDuration.ps1"
. "$PSScriptRoot\Public\Timing\Add-TimingSpanDuration.ps1"
. "$PSScriptRoot\Public\Timing\Export-TimingSpanTree.ps1"
. "$PSScriptRoot\Public\Timing\Import-TimingSpanTree.ps1"
. "$PSScriptRoot\Public\Timing\Initialize-PhaseTimings.ps1"
. "$PSScriptRoot\Public\Timing\Initialize-TimingSpanTree.ps1"
. "$PSScriptRoot\Public\Timing\Invoke-WithPhaseTimer.ps1"
. "$PSScriptRoot\Public\Timing\Invoke-WithSubStepTimer.ps1"
. "$PSScriptRoot\Public\Timing\Measure-TimingSpan.ps1"
. "$PSScriptRoot\Public\Timing\New-TimingSpanTree.ps1"
. "$PSScriptRoot\Public\Timing\Write-PhaseTimingReport.ps1"
. "$PSScriptRoot\Public\Timing\Write-TimingSpanReport.ps1"

# Export-ModuleMember controls what is actually callable after Import-Module.
# It takes precedence over FunctionsToExport in the psd1 at runtime, so both
# must be kept in sync. FunctionsToExport serves a separate purpose: it is
# read by Get-Module -ListAvailable, Find-Module, and PSGallery for fast
# discovery without loading the module. The shared Module.Tests.ps1 in the
# run-unit-tests action enforces that every Public\*.ps1 file appears in both.
Export-ModuleMember -Function `
    Assert-RequiredProperties, `
    ConvertTo-Array, `
    Invoke-ModuleInstall, `
    Limit-RetainedItem, `
    `
    Invoke-WithExitCodeRetry, `
    Invoke-WithRetry, `
    New-FileLockRetryStrategy, `
    New-TransientPowerShellModuleInstallRetryStrategy, `
    New-TransientNetworkRetryStrategy, `
    `
    New-ConstantBackoffStrategy, `
    New-CustomBackoffStrategy, `
    New-ExponentialBackoffStrategy, `
    New-LinearBackoffStrategy, `
    `
    Add-SubStepDuration, `
    Add-TimingSpanDuration, `
    Export-TimingSpanTree, `
    Import-TimingSpanTree, `
    Initialize-PhaseTimings, `
    Initialize-TimingSpanTree, `
    Invoke-WithPhaseTimer, `
    Invoke-WithSubStepTimer, `
    Measure-TimingSpan, `
    New-TimingSpanTree, `
    Write-PhaseTimingReport, `
    Write-TimingSpanReport
