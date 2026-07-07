# Changelog

All notable changes to `Common.PowerShell` are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org).

Add entries under `[Unreleased]` as changes merge; at release the
`[Unreleased]` heading is promoted to the new version + date and a fresh
`[Unreleased]` is opened above it. Changes prior to 8.1.0 live in the git
history and the tag list.

## [Unreleased]

## [9.3.0] - 2026-07-07

### Added
- `Export-PhaseTimingTreeIfRequested` - the self-guarding opt-in wrapper over
  `Export-PhaseTimingTree`. Reads the output-path environment variable (default
  `TIMING_TREE_OUTPUT_PATH`, overridable via `-EnvVariableName`) and delegates
  to `Export-PhaseTimingTree` only when it is set; unset/empty, or a
  never-initialised default context, is a no-op. Centralises the env-var guard
  every child emitter (`provision.ps1`, `create-users.ps1`, `remove-users.ps1`,
  `register-runners.ps1`) previously hand-wrote at each export site, so the
  opt-in contract name lives in exactly one place - a typo can no longer
  silently disable a single consumer's export - and each call site collapses to
  one intention-revealing call. The core `Export-TimingSpanTree` and its shim
  `Export-PhaseTimingTree` stay mandatory on their path argument; the env-var
  read lives only in this opt-in-aware layer.

## [9.2.0] - 2026-07-07

### Added
- `Export-PhaseTimingTree` - the export counterpart of the 2-level
  `Write-PhaseTimingReport` compat shim. Serialises the module-private default
  context (`$script:DefaultPhaseTimingTree`, the tree the phase/sub-step shims
  build) to the versioned nested-JSON schema (`e2e-timing/v1`) by delegating to
  the context-explicit core `Export-TimingSpanTree`. Same no-`-Tree` surface and
  same "return silently when the context was never initialised" null-guard as
  `Write-PhaseTimingReport`, so it is safe to call from the same outer finally.
  Gives a shim consumer (`provision.ps1`, `register-runners.ps1`) the missing
  handle to serialise its timings for the cross-process handoff, on the
  `TIMING_TREE_OUTPUT_PATH` opt-in, without exposing the default context or
  overloading the core verb with a hidden-global fallback.

## [9.1.0] - 2026-07-06

### Added
- Timing-tree framework (`New-TimingSpanTree`, `Initialize-TimingSpanTree`,
  `Measure-TimingSpan`, `Add-TimingSpanDuration`) - an arbitrary-depth,
  context-owned nested span model with by-name accumulation and sticky-Failed
  status. Generalises the provisioner's 2-level phase-timing framework so
  timings can nest to any depth and, later in the feature, cross the process
  boundary.
- `Export-TimingSpanTree` / `Import-TimingSpanTree` - the cross-process
  handoff for the timing tree. Export serialises a context's whole tree to
  the versioned nested-JSON schema (`e2e-timing/v1`; explicit `children[]`,
  first-class `status`, invariant-culture numbers); Import rebuilds it into
  an in-memory subtree, tolerating a missing or malformed file (returns
  `$null` with a warning, never throws) so a crashed child never fails the
  parent's own report.
- `Write-TimingSpanReport` - renders a timing context or a bare node subtree
  as a depth-indented, single-colour (`DarkGreen`) console block: per span a
  fixed-width `[OK]`/`[FAILED]`/`[SKIPPED]`/`[RUNNING]` tag, invariant-culture
  `F2` seconds, and percent of its parent's effective elapsed, closed by a
  `total observed` line for the root. The arbitrary-depth, merge-aware
  counterpart of the provisioner's 2-level `Write-PhaseTimingReport`; a
  `SKIPPED` node shows a dash and no percent, and the total counts the root's
  effective elapsed (top-level spans, no sub-step double-count).
- 2-level phase-timing compat shims (`Initialize-PhaseTimings`,
  `Invoke-WithPhaseTimer`, `Invoke-WithSubStepTimer`, `Add-SubStepDuration`,
  `Write-PhaseTimingReport`) - the provisioner's pre-generalisation timing
  surface, re-expressed as thin wrappers over the timing-tree core and a
  single module-scoped default context so existing call sites keep their exact
  signatures (no `-Tree` argument). Behaviour-preserving: the verbs throw on
  the same undeclared-phase / not-initialised conditions and
  `Write-PhaseTimingReport` emits the byte-identical legacy report (fixed
  banner, no percent column, top-level-only total). Lets a consumer migrate to
  one framework without rewriting call sites.

## [9.0.1] - 2026-06-17

### Fixed
- `Invoke-ModuleInstall` now imports the target module with `-Global`. Because
  the function is itself a module export, a plain `Import-Module` placed the
  installed module's commands in this module's session state rather than the
  caller's, so callers silently relied on command auto-loading. When two
  installed modules export the same command (e.g. a renamed/split module
  leaves an old copy behind), auto-load resolved to the alphabetically-first
  one - which could be the stale version. `-Global` makes the explicit import
  authoritative in the caller's scope, so resolution is deterministic.

## [9.0.0] - 2026-06-17

### Changed
- Major version bump; no functional changes (version realignment).

## [8.1.0] - 2026-06-14

### Added
- `Invoke-WithExitCodeRetry` - exit-code counterpart to `Invoke-WithRetry`
  for native commands (`netsh`, `git`, `docker`, `wsl`, ...) that signal
  failure through `$LASTEXITCODE` instead of a thrown exception. Reuses the
  existing backoff strategies; scope retries with an optional
  `-RetryableExitCode` set, or throw and use `Invoke-WithRetry` for
  predicate-based classification.

[Unreleased]: https://github.com/Klark-Morrigan/Common-PowerShell/compare/9.3.0...HEAD
[9.3.0]: https://github.com/Klark-Morrigan/Common-PowerShell/compare/9.2.0...9.3.0
[9.2.0]: https://github.com/Klark-Morrigan/Common-PowerShell/compare/9.1.0...9.2.0
[9.1.0]: https://github.com/Klark-Morrigan/Common-PowerShell/compare/9.0.1...9.1.0
[9.0.1]: https://github.com/Klark-Morrigan/Common-PowerShell/compare/9.0.0...9.0.1
[9.0.0]: https://github.com/Klark-Morrigan/Common-PowerShell/compare/8.1.0...9.0.0
[8.1.0]: https://github.com/Klark-Morrigan/Common-PowerShell/compare/8.0.0...8.1.0
