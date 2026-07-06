function New-TimingSpanTree {
<#
.SYNOPSIS
    Create a timing context that owns an N-level nested span tree.

.DESCRIPTION
    The entry point of the arbitrary-depth timing framework. Returns a
    context object that carries the root node plus a current-node stack and
    a monotonic Order counter. Every other timing verb (Measure-TimingSpan,
    Add-TimingSpanDuration, Initialize-TimingSpanTree) operates on a context
    passed explicitly.

    A context object, rather than a module-scoped `$script:` global, is what
    lets two trees coexist in one process without clobbering each other - the
    E2E parent's own tree and a child tree imported from another process can
    both be live at once. The 2-level framework's single global state cannot
    express that.

    Node shape (every node, root included):
      { Order; Name; Status; ElapsedMs; Source; Children }
        Order     - first-contact declaration order across all depths.
        Name      - display name; unique within a parent's Children.
        Status    - 'NotStarted' | 'Running' | 'OK' | 'Failed'.
        ElapsedMs - $null until timed, then the accumulated total.
        Source    - optional provenance tag used by the cross-process merge.
        Children  - ordered list of child nodes (arbitrary depth).

    The returned context shape:
      { Root; Stack; NextOrder }
        Root      - the root node (Order 0).
        Stack     - current-node stack; the top is the parent that the next
                    span attaches under. Seeded with Root.
        NextOrder - the next Order value to hand out; advanced on creation.

.PARAMETER RootName
    Display name of the root node (e.g. the run name). The total line of the
    report is this node.

.PARAMETER Source
    Optional provenance tag for the root (e.g. the emitting script's name),
    carried through export/merge.

.EXAMPLE
    $tree = New-TimingSpanTree -RootName 'runner-lifecycle'
    Measure-TimingSpan -Tree $tree -Name 'Setup' -Action { Start-Setup }
#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RootName,

        [string] $Source
    )

    $root = [pscustomobject]@{
        Order     = 0
        Name      = $RootName
        # The root is a live container from the moment it exists; a report
        # emitted mid-run shows it as Running until the run completes.
        Status    = 'Running'
        ElapsedMs = $null
        Source    = if ([string]::IsNullOrEmpty($Source)) { $null } else { $Source }
        Children  = [System.Collections.Generic.List[object]]::new()
    }

    $context = [pscustomobject]@{
        Root      = $root
        Stack     = [System.Collections.Generic.Stack[object]]::new()
        # Root took Order 0, so the first minted child gets 1.
        NextOrder = 1
    }
    # Seed the stack with the root so the first Measure/Add attaches a
    # top-level span under it without the caller managing the stack.
    $context.Stack.Push($root)

    return $context
}
