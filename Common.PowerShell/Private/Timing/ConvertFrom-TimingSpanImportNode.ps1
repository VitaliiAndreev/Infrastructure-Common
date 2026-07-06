<#
.NOTES
    Module-internal. Dot-sourced by the psm1 before the Public\Timing\
    verbs. Not exported. Recursion behind Import-TimingSpanTree.
#>

# ---------------------------------------------------------------------------
# ConvertFrom-TimingSpanImportNode
#   Recursively rebuild an in-memory span node from a ConvertFrom-Json
#   object parsed off the export schema. The inverse of
#   ConvertTo-TimingSpanExportNode, kept private so the JSON-to-node mapping
#   has one implementation.
#
#   Fields are read defensively via PSObject.Properties (not direct property
#   access) so a partially-shaped node from an older or half-written export
#   yields sane defaults instead of throwing under the module's StrictMode.
#   This is what lets Import-TimingSpanTree honour its never-throw contract:
#   a crashed child's export must never fail the parent's own report.
#
#   Children are rebuilt as a List[object] so the reconstructed subtree is
#   the same type the live framework mints - the E2E graft step (D2) can
#   append it under a part span without a type mismatch.
# ---------------------------------------------------------------------------

function ConvertFrom-TimingSpanImportNode {
    [CmdletBinding()]
    param(
        # A single node object as produced by ConvertFrom-Json over the
        # export schema (camelCase keys).
        [Parameter(Mandatory)] $Node
    )

    $properties = $Node.PSObject.Properties

    # Rebuild children first (depth-first) so the node is assembled in one
    # pass. A missing/null children field is a leaf - an empty list, not an
    # error.
    $children = [System.Collections.Generic.List[object]]::new()
    $childrenProperty = $properties['children']
    if ($null -ne $childrenProperty -and $null -ne $childrenProperty.Value) {
        foreach ($child in @($childrenProperty.Value)) {
            $children.Add((ConvertFrom-TimingSpanImportNode -Node $child)) | Out-Null
        }
    }

    $orderProperty   = $properties['order']
    $nameProperty    = $properties['name']
    $statusProperty  = $properties['status']
    $elapsedProperty = $properties['elapsedMs']
    $sourceProperty  = $properties['source']

    # Match the live node shape and property order exactly so a round-trip
    # (export then import) reconstructs an equivalent subtree.
    [pscustomobject]@{
        Order     = if ($null -ne $orderProperty) { [int]$orderProperty.Value } else { 0 }
        Name      = if ($null -ne $nameProperty) { [string]$nameProperty.Value } else { '' }
        Status    = if ($null -ne $statusProperty) { [string]$statusProperty.Value } else { 'NotStarted' }
        # elapsedMs is $null until a span is timed; preserve that distinction
        # rather than coercing an un-run node's null to 0.
        ElapsedMs = if ($null -ne $elapsedProperty -and $null -ne $elapsedProperty.Value) {
            [int64]$elapsedProperty.Value
        } else {
            $null
        }
        Source    = if ($null -ne $sourceProperty -and
                        -not [string]::IsNullOrEmpty([string]$sourceProperty.Value)) {
            [string]$sourceProperty.Value
        } else {
            $null
        }
        Children  = $children
    }
}
