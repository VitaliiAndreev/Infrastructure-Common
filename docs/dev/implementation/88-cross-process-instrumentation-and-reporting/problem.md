# Feature 88 - Cross-process instrumentation and reporting

GitHub issue: #88.

## Index

- [Summary](#summary)
- [Motivation](#motivation)
- [Current state](#current-state)
- [What we want](#what-we-want)
- [Constraints and non-goals](#constraints-and-non-goals)
- [Solution approach](#solution-approach)
  - [Off-the-shelf survey result](#off-the-shelf-survey-result)
  - [Chosen direction](#chosen-direction)
  - [Artifact shape decision](#artifact-shape-decision)
- [Resolved decisions](#resolved-decisions)

## Summary

Produce a hierarchical timing report at the end of an E2E run
(`Infrastructure-E2E` runner-lifecycle run) that shows:

- how long the whole run took,
- how long each phase took,
- how long each part of each phase took,

drilling all the way down into the work done by child processes
(`provision.ps1`, `register-runners.ps1`, and the bash / Ansible flows),
so runtime can be diagnosed and optimisation targets found.

The report is emitted to the console at run end AND persisted as a rolling
JSON artifact (old artifacts pruned automatically).

## Motivation

- The runner-lifecycle run is the longest-running thing in the fleet and
  the hardest to reason about, because its cost is spread across four
  repos and several child processes.
- Optimising blind is guesswork. A per-part breakdown turns "the run is
  slow" into "`wait for SSH` is 4 of the 14 minutes" - an actionable
  target.
- A machine-readable rolling artifact lets successive runs be compared so
  a regression (a step that suddenly doubled) is visible.

## Current state

- The whole run is orchestrated by `Invoke-RunnerLifecycleTest`
  (`Infrastructure-E2E/agent/e2e/runner-lifecycle/`), a deeply nested call
  tree that shells out to `Infrastructure-Vm-Provisioner`,
  `Infrastructure-Vm-Users`, and `Infrastructure-GitHubRunners` scripts as
  separate processes.
- `Infrastructure-Vm-Provisioner` already has a phase-timing framework at
  `hyper-v/ubuntu/PowerShell/up/timing/`
  (`Initialize-PhaseTimings`, `Invoke-WithPhaseTimer`,
  `Invoke-WithSubStepTimer`, `Add-SubStepDuration`,
  `Write-PhaseTimingReport`). It is **2 levels** (phase + one sub-step),
  records-on-failure, and prints a `DarkGreen` console report. It has **no
  machine-readable export** - console only. Its state
  (`$script:PhaseTimings`) lives in the dot-source scope and dies with the
  process.
- `Common.PowerShell` already ships `Limit-RetainedItem`
  (`Public/Limit-RetainedItem.ps1`) - a rolling-file pruner by `-MaxItems`
  and/or `-MaxAgeDays`. This is the retention primitive to reuse.
- Nothing crosses the process boundary today: a parent process cannot see
  a child's timings, mirroring the note in
  `Invoke-PreTeardownRuntimeDiagCapture` that "callers may be in different
  processes; the vault is the SSOT".

## What we want

1. A single hierarchical timing report at the end of a runner-lifecycle
   run: total, each phase (% of total), each part (% of parent), to
   arbitrary depth including the child-process internals.
2. The report emitted **on both success and failure** (a failed or hung
   run must still show where the time went up to the failure point).
3. A rolling JSON artifact of the same tree, with old artifacts pruned via
   `Limit-RetainedItem`.
4. One consistent timing framework across all layers - not a second,
   parallel mechanism.

## Constraints and non-goals

- **No new heavyweight dependency** (no OpenTelemetry collector, no live
  observability backend). This is a one-shot end-of-run local report.
- **ASCII-only**, minus signs not long dashes, per house style.
- **Behaviour-preserving for `provision.ps1`**: its existing console report
  and control flow must not regress; the timer only observes.
- Promoting the shared primitive to `Common.PowerShell` trips the
  module-version-bump + CHANGELOG + consumer-pin gate - accepted cost,
  since there are already two consumers (provisioner + E2E).
- **Non-goal (deferred):** Perfetto / Chrome-trace export and any
  flame-graph viewer. The nested tree is the source of truth; a derived
  Perfetto exporter can be added later if wanted.
- **Non-goal:** cross-run trend analysis / dashboards. The rolling JSON
  makes this possible later but the feature only produces the artifacts.

## Solution approach

### Off-the-shelf survey result

Candidates evaluated: OpenTelemetry traces, .NET `System.Diagnostics`
`ActivitySource`, Chrome Trace Event / Perfetto format, PowerShell
`Measure-Command`, and the in-house `PhaseTimings` framework.

- OpenTelemetry and `ActivitySource` are built for online tracing with
  collectors/exporters; the integration cost (no first-class PowerShell
  SDK, a bash shim, a running collector) dwarfs a one-shot local report.
- `Measure-Command` times a single scriptblock - no nesting, no
  cross-process, no report.
- Chrome Trace / Perfetto is a serialization + viewer *format*, not a
  collection mechanism; it solves the artifact shape only, and its
  absolute-microsecond timestamp model is harder to assemble correctly
  across independent-clock processes.
- The in-house `PhaseTimings` framework already produces the exact report
  shape wanted (hierarchy, `[OK]/[FAILED]/[SKIPPED]` tags,
  records-on-failure, invariant-culture durations) and is already wired
  into the biggest time sink.

### Chosen direction

**Build custom by extending the in-house framework.** Generalise
`PhaseTimings` from 2 levels to an N-level nested tree, add a JSON
export/import so child processes can hand their tree up across the process
boundary, and have the E2E orchestrator graft child trees under the part
that invoked them. Promote the generalised primitive to `Common.PowerShell`
so `Infrastructure-Vm-Provisioner` and `Infrastructure-E2E` share one
framework. Reuse `Limit-RetainedItem` for rolling-JSON retention.

The only genuinely new problems - N-level depth, cross-process
export/merge, and a small bash emitter for the Ansible/bash flows - are
self-contained additions no off-the-shelf tool drops in cleanly given the
PowerShell + WSL-bash + separate-process topology.

### Artifact shape decision

The persisted artifact is the **in-house nested tree** (explicit
`children[]`, first-class `status`, duration-only `elapsedMs`). Decided
against the Perfetto/Chrome-trace shape for now because:

- hierarchy is explicit (no implicit timestamp-containment reconstruction),
- it carries `OK / FAILED / SKIPPED` status natively,
- cross-process merge is a trivial subtree graft rather than a timestamp
  rebase onto a shared clock,
- it renders the console report directly in one tree walk.

A derived Perfetto exporter remains a clean future add-on but is out of
scope here.

## Resolved decisions

- **PowerShell depth first (confirmed).** Instrument the PowerShell layers
  end to end first; each bash / Ansible flow (`register-runners.sh`,
  `provision-toolchains.sh`, `create-users.sh`) is timed as a single part
  initially. A tiny bash emitter that contributes sub-step depth in the
  same nested JSON schema lands as a later step, sequenced last in
  `plan.md`.
- **E2E parent before child emitters (walking skeleton).** The E2E
  orchestrator - instrument, graft, report + rolling artifact - is built
  before the child-process depth emitters. The graft is defensive (a missing
  child export leaves a part with no children, never an error), so the report
  ships complete with each shell-out as a single opaque span and every emitter
  then deepens a part that already renders. This gets the deliverable - the
  report - out soonest and validates the schema against a real orchestration
  before emitter code spreads across repos. The provisioner's migration onto
  the shared module is independent SSOT cleanup and stays early, ahead of the
  E2E work.
- **Artifact location (confirmed).** The rolling JSON artifact lives in a
  `timing/` folder under the run's existing diagnostics root, next to
  `runtime-diag.log` / `console.log`, so all artifacts for a run stay
  side by side.
- **Cross-process handoff is a neutral env-var opt-in.** The parent passes
  a per-invocation output path to each child through a neutral environment
  variable (e.g. `TIMING_TREE_OUTPUT_PATH`, final name settled in
  `plan.md`). When set, the child exports its timing tree to that path at
  end of run (success or failure); when unset, the child only prints its
  console report - today's behaviour, byte for byte. This keeps the
  library topology-agnostic and the production scripts test-agnostic (no
  script knows it is being driven by E2E).
