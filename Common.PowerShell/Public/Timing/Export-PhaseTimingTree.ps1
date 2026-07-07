<#
.NOTES
    Compatibility shim - the export counterpart of Write-PhaseTimingReport.
    A shim consumer (provision.ps1, register-runners.ps1) drives timing through
    the 2-level verbs, whose tree lives in the module-private default context
    ($script:DefaultPhaseTimingTree). That context is reachable today only from
    inside the module (Write-PhaseTimingReport reads it to render); a consumer
    has no handle to it and so cannot serialise it for the cross-process
    handoff. This verb exposes exactly that read, delegating the actual write to
    the context-explicit core Export-TimingSpanTree. The core keeps its -Tree
    mandatory on purpose: overloading it with a hidden default-context fallback
    would turn a forgotten -Tree into silent action-at-a-distance instead of a
    binding error, blurring the clean context-explicit core / default-context
    shim split the module was built on.
#>

function Export-PhaseTimingTree {
<#
.SYNOPSIS
    Serialise the default 2-level timing context to the cross-process JSON
    export schema.

.DESCRIPTION
    The export counterpart of Write-PhaseTimingReport: same no-`-Tree` surface,
    same default-context read, same "return silently when the context was never
    initialised" guard. Lets a shim consumer hand its phase/sub-step tree to a
    parent process (the E2E orchestrator) on the TIMING_TREE_OUTPUT_PATH opt-in
    without threading a -Tree argument, then the parent imports and grafts it
    under the part that shelled out.

    Writes nothing (no throw) when Initialize-PhaseTimings was never called, so
    an outer try/finally can call this unconditionally on both the success and
    failure paths exactly like Write-PhaseTimingReport.

.PARAMETER Path
    Destination file, forwarded verbatim to Export-TimingSpanTree. The parent
    directory must already exist; the caller owns the path (typically a
    per-invocation temp file named by TIMING_TREE_OUTPUT_PATH).

.EXAMPLE
    if ($env:TIMING_TREE_OUTPUT_PATH) {
        Export-PhaseTimingTree -Path $env:TIMING_TREE_OUTPUT_PATH
    }
#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    # Null-guard parity with Write-PhaseTimingReport: a run that never
    # initialised timings (or bailed before doing so) emits no artifact rather
    # than failing the caller's finally.
    if ($null -eq $script:DefaultPhaseTimingTree) {
        return
    }

    Export-TimingSpanTree -Tree $script:DefaultPhaseTimingTree -Path $Path
}
