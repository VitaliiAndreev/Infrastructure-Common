# Changelog

All notable changes to `Common.PowerShell` are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org).

Add entries under `[Unreleased]` as changes merge; at release the
`[Unreleased]` heading is promoted to the new version + date and a fresh
`[Unreleased]` is opened above it. Changes prior to 8.1.0 live in the git
history and the tag list.

## [Unreleased]

### Added
- Timing-tree framework (`New-TimingSpanTree`, `Initialize-TimingSpanTree`,
  `Measure-TimingSpan`, `Add-TimingSpanDuration`) - an arbitrary-depth,
  context-owned nested span model with by-name accumulation and sticky-Failed
  status. Generalises the provisioner's 2-level phase-timing framework so
  timings can nest to any depth and, later in the feature, cross the process
  boundary. The report renderer and the version bump land in subsequent
  steps.
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
  effective elapsed (top-level spans, no sub-step double-count). The version
  bump lands in a subsequent step.

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

[Unreleased]: https://github.com/Klark-Morrigan/Common-PowerShell/compare/9.0.1...HEAD
[9.0.1]: https://github.com/Klark-Morrigan/Common-PowerShell/compare/9.0.0...9.0.1
[9.0.0]: https://github.com/Klark-Morrigan/Common-PowerShell/compare/8.1.0...9.0.0
[8.1.0]: https://github.com/Klark-Morrigan/Common-PowerShell/compare/8.0.0...8.1.0
