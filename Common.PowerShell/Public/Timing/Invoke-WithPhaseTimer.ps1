<#
.NOTES
    Compatibility shim over Measure-TimingSpan, operating on the default
    context declared in Initialize-PhaseTimings.ps1. Preserves the legacy
    contract: the phase must have been pre-declared (unknown names throw
    rather than lazily appearing) so a typo fails loudly at the first phase
    boundary, exactly as before the N-level generalisation.
#>

function Invoke-WithPhaseTimer {
<#
.SYNOPSIS
    Time -Action as the named top-level phase on the default context.

.DESCRIPTION
    Thin wrapper over Measure-TimingSpan. Validates that -Name was declared
    via Initialize-PhaseTimings (top-level only, so a same-named sub-step
    never shadows it), then delegates the stopwatch, status, and
    exception-propagating behaviour to the core verb - which observes but
    never swallows, so the existing control flow is unchanged.

.PARAMETER Name
    Phase name; must match a Name passed to Initialize-PhaseTimings.

.PARAMETER Action
    The work to time. Runs as-is; exceptions propagate.
#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,

        [Parameter(Mandatory)] [scriptblock] $Action
    )

    if ($null -eq $script:DefaultPhaseTimingTree) {
        throw ('Invoke-WithPhaseTimer: Initialize-PhaseTimings has not ' +
            'been called.')
    }

    # Guard the pre-declared contract before delegating: Measure-TimingSpan
    # would lazily mint an unknown phase, but the legacy verb throws so a
    # mistyped phase name is caught. Match top-level children of the root
    # only.
    $root = $script:DefaultPhaseTimingTree.Root
    $known = @($root.Children | Where-Object { $_.Name -eq $Name })
    if ($known.Count -eq 0) {
        throw ("Invoke-WithPhaseTimer: phase '$Name' was not declared " +
            'via Initialize-PhaseTimings.')
    }

    # The default context's stack top is the root at a top-level phase
    # boundary, so Measure resolves the existing pre-declared node (by name
    # under root) rather than creating a sibling - accumulating into it and
    # setting OK/Failed with partial-elapsed-on-throw, as the old verb did.
    Measure-TimingSpan `
        -Tree   $script:DefaultPhaseTimingTree `
        -Name   $Name `
        -Action $Action
}
