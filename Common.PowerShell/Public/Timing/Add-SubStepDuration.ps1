<#
.NOTES
    Compatibility shim over the timing core's find-or-create + accumulate
    primitives (Resolve-TimingSpanChildNode, Add-TimingSpanNodeElapsed),
    operating on the default context declared in Initialize-PhaseTimings.ps1.
    Resolves the sub-step by (Parent name, sub-step name) rather than by the
    context's current-node stack, so the legacy "any declared phase can be
    the parent" contract holds regardless of call nesting.
#>

function Add-SubStepDuration {
<#
.SYNOPSIS
    Accumulate a pre-measured elapsed under a sub-step of a named phase.

.DESCRIPTION
    The measure-less 2-level primitive, for callers that already timed the
    work themselves (e.g. a reconciler reporting per-provider elapsed via a
    callback). Finds the parent phase node on the default context (throwing
    with the legacy message if it was not declared via
    Initialize-PhaseTimings), lazily creates the sub-step under it on first
    contact, and adds -ElapsedMs to its running total.

    Accumulation is additive across calls for the same (Parent, Name) - the
    per-VM-loop semantics - and Failed is sticky: a later success against a
    sub-step that already failed does not clear the flag, so the report
    still surfaces the bad run.

.PARAMETER Parent
    Name of the parent top-level phase; must already be declared.

.PARAMETER Name
    Sub-step display name; unique within (Parent, *). Lazily created.

.PARAMETER ElapsedMs
    Milliseconds to add to the sub-step's accumulated total.

.PARAMETER Failed
    Mark the sub-step Failed (sticky) - use when the measured work threw.
#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Parent,

        [Parameter(Mandatory)] [string] $Name,

        [Parameter(Mandatory)] [int64] $ElapsedMs,

        [switch] $Failed
    )

    if ($null -eq $script:DefaultPhaseTimingTree) {
        throw ('Add-SubStepDuration: Initialize-PhaseTimings has not ' +
            'been called.')
    }

    # A sub-step without a real parent would render as an orphan row; surface
    # the typo loudly instead. Top-level children of the root only.
    $root = $script:DefaultPhaseTimingTree.Root
    $parentMatches = @($root.Children | Where-Object { $_.Name -eq $Parent })
    if ($parentMatches.Count -eq 0) {
        throw ("Add-SubStepDuration: parent phase '$Parent' was not " +
            'declared via Initialize-PhaseTimings.')
    }

    # Find-or-create the sub-step under the resolved parent (not under the
    # stack top), then accumulate through the shared elapsed/sticky-status
    # primitive so the semantics match Measure-TimingSpan exactly.
    $node = Resolve-TimingSpanChildNode `
        -Context $script:DefaultPhaseTimingTree `
        -Parent  $parentMatches[0] `
        -Name    $Name
    Add-TimingSpanNodeElapsed -Node $node -ElapsedMs $ElapsedMs -Failed:$Failed
}
