<#
.NOTES
    Module-internal. Dot-sourced by the psm1 before the Public\Timing\
    verbs. Not exported. Recursion behind Initialize-TimingSpanTree.
#>

# ---------------------------------------------------------------------------
# Add-TimingSpanSkeletonBranch
#   Recursively pre-declare a nested skeleton of nodes under -Parent. Kept
#   separate from the public Initialize-TimingSpanTree verb so the recursion
#   has a single node-agnostic implementation that walks any depth.
#
#   Skeleton entry forms (mirroring Initialize-PhaseTimings' -Phases):
#     * a plain string                       - a leaf child by that name.
#     * @{ Name = '...';                      - a named node with an optional
#          Children = @(...); Source = '...' }   nested subtree and provenance
#                                               tag; Children recurse.
#
#   Pre-declared nodes stay NotStarted (Resolve-TimingSpanChildNode's default)
#   until a Measure / Add call runs them, so a branch that never executes
#   still renders (as SKIPPED) instead of being silently absent.
# ---------------------------------------------------------------------------

function Add-TimingSpanSkeletonBranch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Context,

        [Parameter(Mandatory)] $Parent,

        [Parameter(Mandatory)] [object[]] $Skeleton
    )

    foreach ($item in $Skeleton) {
        if ($item -is [hashtable]) {
            $name   = [string]$item['Name']
            $source = if ($item.ContainsKey('Source')) { [string]$item['Source'] } else { $null }
            $children = if ($item.ContainsKey('Children') -and $null -ne $item['Children']) {
                @($item['Children'])
            } else {
                @()
            }
        }
        else {
            $name     = [string]$item
            $source   = $null
            $children = @()
        }

        if ([string]::IsNullOrWhiteSpace($name)) {
            throw 'Initialize-TimingSpanTree: a skeleton entry has no Name.'
        }

        $node = Resolve-TimingSpanChildNode `
            -Context $Context `
            -Parent  $Parent `
            -Name    $name `
            -Source  $source

        # Descend so nested Children pre-declare under the node just minted,
        # not under the original parent - this is what gives arbitrary depth.
        # Re-wrap in @() before .Count: a single-element Children array is
        # unrolled to a scalar by the if-expression assignment above, and
        # under StrictMode Latest .Count on a scalar throws rather than
        # returning 1.
        if (@($children).Count -gt 0) {
            Add-TimingSpanSkeletonBranch `
                -Context  $Context `
                -Parent   $node `
                -Skeleton $children
        }
    }
}
