<#
.NOTES
    Compatibility shim over the N-level timing core (New-/Initialize-/
    Measure-TimingSpan). Declares the single module-scoped default context
    the 2-level verbs share so existing call sites (provision.ps1) keep
    their exact signatures - no -Tree argument to thread. The clean,
    context-explicit API is the TimingSpan verb family; these five verbs
    exist only to preserve the pre-generalisation surface.
#>

# The one default context the 2-level verbs operate on. Declared here (not
# in a separate file) because Initialize-PhaseTimings must run before any
# other 2-level verb, so binding the variable's lifetime to this file keeps
# the "init first" contract structurally visible - the same anchor role the
# old $script:PhaseTimings list played. Read under StrictMode by the sibling
# shims, so it must be declared at load time, before any of them is called.
$script:DefaultPhaseTimingTree = $null

function Initialize-PhaseTimings {
<#
.SYNOPSIS
    Re-declare the default 2-level timing context from a phase list.

.DESCRIPTION
    The 2-level entry point, re-expressed as a thin wrapper over
    New-TimingSpanTree + Initialize-TimingSpanTree. Creates a fresh default
    context (clearing any prior state - safe to call again across nested
    provision runs in one session) and pre-declares each phase, and its
    sub-steps, as a skeleton so branches that never run still render as
    SKIPPED.

    Each -Phases item is either:
      * a plain string                    - a top-level phase (leaf).
      * @{ Name = '...'; SubSteps = @() }  - a phase plus its known
                                            sub-steps, rendered indented
                                            under the parent.

    Pre-declaring is optional: a sub-step first seen through a sub-step
    timer is lazily created. It is preferred for sub-steps that may not run
    (e.g. 'files' when no VM has a files array) so the report shows them as
    SKIPPED rather than omitting them.

.PARAMETER Phases
    Phase declarations, in run order. Strings are bare phases; hashtables
    carry pre-declared sub-steps under SubSteps.
#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]] $Phases
    )

    # Translate the 2-level -Phases shape (SubSteps) into the core skeleton
    # shape (Children) up front, validating with the legacy messages so a
    # typo in provision.ps1 still fails the same way. The core would also
    # reject an empty Name, but with a generic message; keeping the checks
    # here preserves the exact wording the call sites and tests expect.
    $skeleton = foreach ($item in $Phases) {
        if ($item -is [hashtable]) {
            $name     = [string]$item['Name']
            $subSteps = @()
            if ($item.ContainsKey('SubSteps') -and $null -ne $item['SubSteps']) {
                $subSteps = @($item['SubSteps'])
            }
        }
        else {
            $name     = [string]$item
            $subSteps = @()
        }

        if ([string]::IsNullOrWhiteSpace($name)) {
            throw 'Initialize-PhaseTimings: phase entry has no Name.'
        }

        $children = foreach ($subName in $subSteps) {
            $subNameStr = [string]$subName
            if ([string]::IsNullOrWhiteSpace($subNameStr)) {
                throw (
                    "Initialize-PhaseTimings: phase '$name' has an empty " +
                    'sub-step name.')
            }
            $subNameStr
        }

        # A leaf phase declares as a bare string; a phase with sub-steps
        # declares as a hashtable with a Children array (@() forces an array
        # even for a single sub-step so the core's foreach walks it).
        if (@($children).Count -gt 0) {
            @{ Name = $name; Children = @($children) }
        }
        else {
            $name
        }
    }

    # Fresh context each call - this is the "clears prior state on re-init"
    # contract. The root is a pure container; the 2-level report banner is
    # fixed, so the root name is never surfaced (see Write-PhaseTimingReport).
    $script:DefaultPhaseTimingTree =
        New-TimingSpanTree -RootName 'Provisioning'
    Initialize-TimingSpanTree `
        -Tree     $script:DefaultPhaseTimingTree `
        -Skeleton @($skeleton)
}
