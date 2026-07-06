<#
.NOTES
    Module-internal. Dot-sourced by the psm1 before the Public\Timing\
    verbs so New-/Measure-/Add-/Initialize-TimingSpanTree can rely on it
    at call time. Not exported.
#>

# ---------------------------------------------------------------------------
# Resolve-TimingSpanChildNode
#   Find-or-create the child of -Parent named -Name and return it. This is
#   the single place a node is minted, so node-shape and Order assignment
#   have exactly one implementation regardless of which public verb
#   (Measure / Add / Initialize) triggered the creation.
#
#   Accumulation is by name-within-parent: a repeated span of the same name
#   under the same parent resolves to the SAME node (so its elapsed sums and
#   the tree keeps one row), preserving the 2-level framework's semantics at
#   arbitrary depth.
#
#   Order is a single monotonic counter on the context, incremented only on
#   genuine creation, so it reflects first-contact declaration order across
#   mixed depths in one flat sort - the property the report renderer relies
#   on.
# ---------------------------------------------------------------------------

function Resolve-TimingSpanChildNode {
    [CmdletBinding()]
    param(
        # The timing context returned by New-TimingSpanTree. Owns the shared
        # Order counter mutated here on creation.
        [Parameter(Mandatory)] $Context,

        # The node under which the child is resolved. Its Children list is
        # searched, and appended to on a miss.
        [Parameter(Mandatory)] $Parent,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        # Optional provenance tag (e.g. 'provision.ps1'), consumed later by
        # the cross-process merge step. Backfilled onto an existing node that
        # was created without one (e.g. pre-declared via a skeleton).
        [string] $Source
    )

    $existing = @($Parent.Children | Where-Object { $_.Name -eq $Name })
    if ($existing.Count -gt 0) {
        $node = $existing[0]
        if (-not [string]::IsNullOrEmpty($Source) -and
            [string]::IsNullOrEmpty($node.Source)) {
            $node.Source = $Source
        }
        return $node
    }

    # Mint through the single node factory; the Order is drawn from the
    # context's monotonic counter, which then advances.
    $node = New-TimingSpanNode -Order $Context.NextOrder -Name $Name -Source $Source
    $Context.NextOrder = $Context.NextOrder + 1
    $Parent.Children.Add($node) | Out-Null
    return $node
}
