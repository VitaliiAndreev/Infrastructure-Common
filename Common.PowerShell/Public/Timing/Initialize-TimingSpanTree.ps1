function Initialize-TimingSpanTree {
<#
.SYNOPSIS
    Pre-declare a nested skeleton of spans so un-run branches still render.

.DESCRIPTION
    Optional up-front declaration of the tree's shape under the root, the
    N-level generalisation of Initialize-PhaseTimings' -Phases. Pre-declared
    nodes are created NotStarted; a branch that never executes in a given run
    therefore renders as SKIPPED rather than being silently absent, which is
    the point - a conditionally-run branch (e.g. 'files' when no VM has a
    files array) is visibly accounted for.

    Pre-declaration is optional: any span first seen through Measure /
    Add is lazily created anyway. Declare only the branches whose absence
    would be meaningful.

    Skeleton entry forms:
      * a plain string                       - a leaf child by that name.
      * @{ Name = '...';                      - a named node with an optional
           Children = @(...); Source = '...' }   nested subtree; Children
                                                recurse to any depth.

    Nodes are declared under the root at the Order they appear here; a later
    Measure of a pre-declared name resolves the same node, so its Order (and
    thus report position) is stable regardless of run-time execution order.

.PARAMETER Tree
    The context returned by New-TimingSpanTree.

.PARAMETER Skeleton
    The nested declaration array (strings and/or hashtables).

.EXAMPLE
    Initialize-TimingSpanTree -Tree $tree -Skeleton @(
        'Setup',
        @{ Name = 'Phase 1'; Children = @('boot VM', 'wait for SSH') },
        'Teardown'
    )
#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Tree,

        [Parameter(Mandatory)] [object[]] $Skeleton
    )

    # Declare under whatever node is current (the root immediately after
    # New-TimingSpanTree); the recursion handles the nested depth.
    $current = $Tree.Stack.Peek()
    Add-TimingSpanSkeletonBranch -Context $Tree -Parent $current -Skeleton $Skeleton
}
