function Add-TimingSpanDuration {
<#
.SYNOPSIS
    Accumulate a pre-measured elapsed value as a span under the current node.

.DESCRIPTION
    The measure-less counterpart to Measure-TimingSpan, for callers that
    already have an elapsed value and only need to feed it into the tree (the
    same role Add-SubStepDuration plays in the 2-level framework - e.g. a
    reconciler that reports per-provider elapsed through a callback rather
    than running its work inside a stopwatch here).

    Finds-or-creates a child named -Name under the context's current node and
    adds -ElapsedMs to its running total. Unlike Measure-TimingSpan it does
    not push the node (there is no scriptblock to nest under it), so the span
    is a leaf contribution to the current node's children.

    Accumulation is by name-within-parent and Failed is sticky, identical to
    Measure-TimingSpan.

.PARAMETER Tree
    The context returned by New-TimingSpanTree.

.PARAMETER Name
    Span name; unique within the current node's children.

.PARAMETER ElapsedMs
    Milliseconds to add to the span's running total.

.PARAMETER Failed
    Mark the span Failed (sticky) - use when the pre-measured work threw.

.PARAMETER Source
    Optional provenance tag applied to the node on first creation.

.EXAMPLE
    Add-TimingSpanDuration -Tree $tree -Name 'provider: files' -ElapsedMs 1200
#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Tree,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory)] [int64] $ElapsedMs,

        [switch] $Failed,

        [string] $Source
    )

    $current = $Tree.Stack.Peek()
    $node = Resolve-TimingSpanChildNode `
        -Context $Tree -Parent $current -Name $Name -Source $Source

    Add-TimingSpanNodeElapsed -Node $node -ElapsedMs $ElapsedMs -Failed:$Failed
}
