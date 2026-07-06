<#
.NOTES
    Module-internal. Dot-sourced by the psm1 before the other Private\Timing\
    helpers and the Public\Timing\ verbs. Not exported.
#>

# ---------------------------------------------------------------------------
# New-TimingSpanNode
#   The single constructor for a span node. Every node in the framework - the
#   root (New-TimingSpanTree), a lazily-minted child (Resolve-TimingSpanChild-
#   Node), and a node rebuilt from a JSON export (ConvertFrom-TimingSpanImport-
#   Node) - is created here, so the node shape and its field defaults have
#   exactly one authority. Adding or renaming a field is a one-file change
#   that cannot silently miss a call site.
#
#   Node shape:
#     { Order; Name; Status; ElapsedMs; Source; Children }
#   Defaults centralise the two rules the call sites otherwise each repeated:
#     * Source is normalised so an empty/absent tag is stored as $null.
#     * Children defaults to a fresh List[object] when the caller has none;
#       the import path passes its already-rebuilt child list through.
# ---------------------------------------------------------------------------

function New-TimingSpanNode {
    [CmdletBinding()]
    param(
        # First-contact declaration order; assigned by the caller that owns
        # the context's monotonic counter (or 0 for the root, or the value
        # read back from an export).
        [Parameter(Mandatory)] [int] $Order,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        # Lifecycle state. Defaults to NotStarted - the state of a node the
        # moment it is minted but before any span runs against it.
        [string] $Status = 'NotStarted',

        # Untyped so the un-run/null distinction survives: $null until timed,
        # an int64 total once a span accumulates into it.
        $ElapsedMs = $null,

        # Optional provenance tag; empty is normalised to $null below.
        [string] $Source,

        # Existing child list to adopt (the import path). Untyped so the
        # List[object] passes through without being enumerated on binding;
        # $null means "give me a fresh empty list".
        $Children = $null
    )

    # Default the child list with a plain statement, NOT an inline `if`
    # expression: a statement-as-expression pipes its output, and an empty
    # List enumerates to nothing, which would silently store $null here.
    if ($null -eq $Children) {
        $Children = [System.Collections.Generic.List[object]]::new()
    }

    [pscustomobject]@{
        Order     = $Order
        Name      = $Name
        Status    = $Status
        ElapsedMs = $ElapsedMs
        Source    = if ([string]::IsNullOrEmpty($Source)) { $null } else { $Source }
        Children  = $Children
    }
}
