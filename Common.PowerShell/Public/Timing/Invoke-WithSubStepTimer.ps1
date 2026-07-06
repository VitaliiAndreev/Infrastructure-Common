<#
.NOTES
    Compatibility shim - the stopwatch wrapper over Add-SubStepDuration, kept
    identical to the pre-generalisation verb. The actual list mutation lives
    in Add-SubStepDuration so the find-or-create + sticky-status logic has one
    implementation whether the caller measured the work itself or delegated
    here.
#>

function Invoke-WithSubStepTimer {
<#
.SYNOPSIS
    Time -Action and accumulate it under a sub-step of a named phase.

.DESCRIPTION
    The common-case 2-level verb: run -Action under a stopwatch and add its
    wall-clock time to the (Parent, Name) sub-step on the default context.
    Mirrors Invoke-WithPhaseTimer's contract on the sub-step side - the
    action runs as-is, any exception propagates, and the elapsed is recorded
    even on failure (with the sub-step marked stickily Failed).

    Multi-call accumulation is the headline behaviour: post-provisioning
    runs per VM, so the same sub-step is timed once per VM and each call
    adds to the running total.

.PARAMETER Parent
    Parent top-level phase name; must already be declared.

.PARAMETER Name
    Sub-step display name; lazily created on first contact.

.PARAMETER Action
    The work to time. Runs as-is; exceptions propagate.
#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Parent,

        [Parameter(Mandatory)] [string] $Name,

        [Parameter(Mandatory)] [scriptblock] $Action
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $Action
        $sw.Stop()
        Add-SubStepDuration `
            -Parent    $Parent `
            -Name      $Name `
            -ElapsedMs $sw.ElapsedMilliseconds
    }
    catch {
        # Capture the partial duration before re-throwing - the report still
        # needs to show how long the failing sub-step ran. The -Failed switch
        # makes the status stickily Failed even if a later VM's iteration of
        # the same sub-step succeeds.
        $sw.Stop()
        Add-SubStepDuration `
            -Parent    $Parent `
            -Name      $Name `
            -ElapsedMs $sw.ElapsedMilliseconds `
            -Failed
        throw
    }
}
