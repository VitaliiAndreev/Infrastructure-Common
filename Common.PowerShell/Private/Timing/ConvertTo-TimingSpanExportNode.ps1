<#
.NOTES
    Module-internal. Dot-sourced by the psm1 before the Public\Timing\
    verbs. Not exported. Recursion behind Export-TimingSpanTree.
#>

# ---------------------------------------------------------------------------
# ConvertTo-TimingSpanExportNode
#   Recursively map an in-memory span node to the serialisable, JSON-facing
#   shape (lowercase keys, explicit children[]) that Export-TimingSpanTree
#   writes. Kept separate from the public verb so the node-to-JSON mapping
#   has exactly one implementation, mirroring the import direction.
#
#   The in-memory node uses PascalCase properties; the on-disk schema uses
#   camelCase so it reads as ordinary JSON to any consumer (a later bash
#   emitter, a viewer). Mapping the names here - rather than serialising the
#   node object directly - decouples the wire format from the in-memory type
#   so either can change without silently reshaping the other.
# ---------------------------------------------------------------------------

function ConvertTo-TimingSpanExportNode {
    [CmdletBinding()]
    param(
        # An in-memory node ({ Order; Name; Status; ElapsedMs; Source;
        # Children }) as minted by Resolve-TimingSpanChildNode.
        [Parameter(Mandatory)] $Node
    )

    # @(...) forces an array even for zero/one child so the field always
    # serialises as a JSON array ([] / [ {...} ]), never collapses to a bare
    # object or is dropped - the import side always expects a list.
    [pscustomobject]@{
        order     = $Node.Order
        name      = $Node.Name
        status    = $Node.Status
        elapsedMs = $Node.ElapsedMs
        source    = $Node.Source
        children  = @(
            foreach ($child in $Node.Children) {
                ConvertTo-TimingSpanExportNode -Node $child
            }
        )
    }
}
