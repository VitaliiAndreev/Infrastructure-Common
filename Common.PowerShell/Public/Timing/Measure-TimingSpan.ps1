function Measure-TimingSpan {
<#
.SYNOPSIS
    Time -Action as a span under the context's current node.

.DESCRIPTION
    The primary timing verb. Finds-or-creates a child named -Name under the
    current node, pushes it (so anything -Action itself times nests beneath),
    runs -Action under a stopwatch, accumulates the elapsed into the node,
    sets the terminal status, and pops - on both the success and failure
    paths.

    The timer only observes: any exception -Action throws propagates
    unchanged (exactly like Invoke-WithPhaseTimer), so wrapping existing
    control flow never alters it. The failing node still records its partial
    elapsed and is marked Failed before the rethrow, so a report emitted from
    a finally shows where the run got to.

    Accumulation is by name-within-parent: calling Measure-TimingSpan with
    the same -Name under the same parent again resolves the same node and adds
    to its running total (the per-VM-loop semantics of the 2-level framework,
    now at any depth). Failed is sticky - a later success against a node that
    already failed does not clear the flag.

    Output of -Action streams to the caller, so Measure-TimingSpan is
    transparent to a wrapped scriptblock that produces a value.

.PARAMETER Tree
    The context returned by New-TimingSpanTree.

.PARAMETER Name
    Span name; unique within the current node's children.

.PARAMETER Action
    The work to time. Runs as-is; exceptions propagate.

.PARAMETER Source
    Optional provenance tag applied to the node on first creation.

.EXAMPLE
    Measure-TimingSpan -Tree $tree -Name 'Phase 1' -Action {
        Measure-TimingSpan -Tree $tree -Name 'boot VM' -Action { Start-Vm }
    }
    # 'boot VM' nests under 'Phase 1' because the outer Action runs while
    # 'Phase 1' is the current node.
#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Tree,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory)] [scriptblock] $Action,

        [string] $Source
    )

    $current = $Tree.Stack.Peek()
    $node = Resolve-TimingSpanChildNode `
        -Context $Tree -Parent $current -Name $Name -Source $Source

    # Mark Running for a mid-run report, but never overwrite a sticky Failed
    # from an earlier iteration of the same span - clearing it here would let
    # a later success hide the bad run.
    if ($node.Status -ne 'Failed') {
        $node.Status = 'Running'
    }
    $Tree.Stack.Push($node)

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $Action
        $sw.Stop()
        Add-TimingSpanNodeElapsed -Node $node -ElapsedMs $sw.ElapsedMilliseconds
    }
    catch {
        # Capture the partial duration and flag Failed before re-throwing so
        # the report reflects the failing span; the exception is not swallowed.
        $sw.Stop()
        Add-TimingSpanNodeElapsed -Node $node -ElapsedMs $sw.ElapsedMilliseconds -Failed
        throw
    }
    finally {
        # Pop on every path so the stack is balanced whether -Action returned
        # or threw; the parent node becomes current again.
        $Tree.Stack.Pop() | Out-Null
    }
}
