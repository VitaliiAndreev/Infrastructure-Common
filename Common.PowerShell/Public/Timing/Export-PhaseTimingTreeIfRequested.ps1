<#
.NOTES
    Self-guarding opt-in wrapper over Export-PhaseTimingTree. Every child
    emitter (provision.ps1, create-users.ps1, remove-users.ps1,
    register-runners.ps1) used to hand-write the same guard at each export
    site - read the TIMING_TREE_OUTPUT_PATH env var, and only when it is set
    call Export-PhaseTimingTree -Path with it. That idiom hard-coded the
    contract variable name at every call site, so a typo in one consumer
    silently disabled its export with no error. This verb centralises both the
    guard and the env-var name so the opt-in contract is single-sourced (the
    name lives in exactly one place) and each call site becomes one
    intention-revealing call.

    The core Export-TimingSpanTree stays mandatory-`-Tree` and its shim
    Export-PhaseTimingTree stays mandatory-`-Path` on purpose: the env-var read
    lives only here, in the opt-in-aware layer, preserving the
    context-explicit core / opt-in-aware shim split the module was built on
    (see Export-PhaseTimingTree and Write-PhaseTimingReport).
#>

function Export-PhaseTimingTreeIfRequested {
<#
.SYNOPSIS
    Serialise the default 2-level timing context to the cross-process JSON
    export path named by an environment variable, only when it is set.

.DESCRIPTION
    The opt-in front door to Export-PhaseTimingTree. Reads the output-path
    environment variable (default TIMING_TREE_OUTPUT_PATH) and, when it holds a
    non-empty value, delegates to Export-PhaseTimingTree to write the default
    context there; when it is unset or empty, it does nothing. The
    "context was never initialised" case is a further no-op, inherited from
    Export-PhaseTimingTree's own null-guard (parity with Write-PhaseTimingReport).

    Designed to be called unconditionally from a child emitter's outer
    try/finally (and any early-exit path that bypasses it): a parent
    orchestrator sets the env var before shelling out and imports the artifact
    afterwards to graft the child's timings under the part that ran it; an
    operator who never sets it sees unchanged behaviour (no file written).

.PARAMETER EnvVariableName
    Name of the environment variable that carries the destination path.
    Defaults to the neutral cross-process contract name TIMING_TREE_OUTPUT_PATH;
    overridable so a caller with its own opt-in convention can reuse the guard.

.EXAMPLE
    try {
        # ... timed stages ...
    }
    finally {
        Export-PhaseTimingTreeIfRequested
    }
#>

    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $EnvVariableName = 'TIMING_TREE_OUTPUT_PATH'
    )

    # Read the env var by name (not the $env:LITERAL idiom) so -EnvVariableName
    # is honoured. An unset variable returns $null and an explicitly empty one
    # returns '' - both are falsy, so the opt-in stays off unless a real path
    # is present, matching the hand-written `if ($env:TIMING_TREE_OUTPUT_PATH)`
    # guard this replaces.
    $outputPath = [Environment]::GetEnvironmentVariable($EnvVariableName)
    if (-not $outputPath) {
        return
    }

    # Delegate the write (and the "never initialised" null-guard) to the
    # context-reading shim so the default-context read lives in exactly one
    # place.
    Export-PhaseTimingTree -Path $outputPath
}
