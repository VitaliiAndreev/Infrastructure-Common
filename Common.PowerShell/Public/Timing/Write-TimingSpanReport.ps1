function Write-TimingSpanReport {
<#
.SYNOPSIS
    Render an N-level timing tree as an indented, single-colour console report.

.DESCRIPTION
    The primary human-facing deliverable of the timing framework: a
    depth-indented block listing every span under the given root with its
    status tag, elapsed seconds, and share of its parent, closed by a total
    line for the root. It handles arbitrary depth and the merged
    (multi-source) tree that the 2-level Write-PhaseTimingReport cannot.

    Layout (one row per descendant of the root; the root itself is the total
    line, mirroring Write-PhaseTimingReport where top-level phases are rows
    and the sum is a separate total):

        name          [TAG]      s   ( % of parent)
          child       [TAG]      s   ( % of parent)
        ...
        total observed:  N s

    Design choices carried over from Write-PhaseTimingReport so the two read
    consistently:
      * Single colour (DarkGreen) so the block reads as one summary unit
        rather than competing with the per-row [OK]/[FAILED] text markers.
      * Fixed-width status tags and a name column padded to the widest
        (indent + name) so the duration column aligns across all depths.
      * Invariant-culture F2 seconds so '.' is the decimal separator on every
        host, keeping the output parseable regardless of regional settings.

    Elapsed vs. roll-up. A row prints the node's own ElapsedMs (a dash when it
    never ran, i.e. a NotStarted/SKIPPED node). Percent-of-parent and the
    total line instead use an EFFECTIVE elapsed: the larger of a node's own
    measured elapsed and the sum of its children's effective elapsed. That
    lets the root - a live container with no ElapsedMs of its own - still yield
    a meaningful total (the sum of its top-level spans), keeps per-child
    percents at or below 100% even when a grafted child subtree reports more
    time than the parent's own span, and preserves the "top-level only, no
    double-count" total semantics of the 2-level renderer.

.PARAMETER Tree
    Either a timing context (from New-TimingSpanTree; its .Root is rendered)
    or a bare node (an imported/grafted subtree renders under that node as its
    own root). The root becomes the total line; its descendants become rows.

.EXAMPLE
    Write-TimingSpanReport -Tree $context

.EXAMPLE
    # Render just an imported child subtree.
    $subtree = Import-TimingSpanTree -Path $childJson
    Write-TimingSpanReport -Tree $subtree
#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Tree
    )

    # Accept a context or a bare node: a context carries a Root property, a
    # node does not. Normalising here lets callers pass whichever they hold
    # (the E2E parent passes its context; a graft/merge passes a subtree).
    $root = if ($Tree.PSObject.Properties.Name -contains 'Root') {
        $Tree.Root
    } else {
        $Tree
    }

    if ($null -eq $root) {
        return
    }

    # Effective elapsed drives the percent denominators and the total. It is
    # the LARGER of a node's own measured elapsed and the sum of its children's
    # effective elapsed - never their sum on top of the parent (children run
    # INSIDE the parent, so adding them would double-count), and never less
    # than the children it contains. Taking the max matters at the process
    # boundary: a grafted child subtree (or clock skew) can report more time
    # than the parent's own measured span, and using the parent's smaller
    # figure as the denominator would print a per-child percent above 100%.
    # A container with no measured time of its own (the root, or any pure
    # grouping node) simply rolls up its children.
    function getEffectiveElapsedMs($node) {
        $childSum = [int64] 0
        foreach ($child in $node.Children) {
            $childSum += getEffectiveElapsedMs $child
        }
        if ($null -ne $node.ElapsedMs) {
            return [math]::Max([int64] $node.ElapsedMs, $childSum)
        }
        return $childSum
    }

    # Flatten the descendants into rows (depth + node + the parent's effective
    # elapsed), depth-first in Order so the console block reflects declaration
    # order at every level. The parent's effective is captured here - during
    # the walk that already visits every node - so the percent column needs no
    # separate parent lookup. The root is excluded: it is the total line.
    $rows = [System.Collections.Generic.List[object]]::new()
    function addRows($node, $depth) {
        $parentEffective = getEffectiveElapsedMs $node
        foreach ($child in ($node.Children | Sort-Object Order)) {
            $rows.Add([pscustomobject]@{
                Depth           = $depth
                Node            = $child
                ParentEffective = $parentEffective
            })
            addRows $child ($depth + 1)
        }
    }
    addRows $root 0

    # Per-depth indent (two spaces per level) folded into the name so the tag
    # column stays aligned across mixed depths, matching Write-PhaseTimingReport
    # where a sub-step sits two spaces further in than its parent.
    $indentUnit = '  '
    $displayNames = @{}
    foreach ($row in $rows) {
        $displayNames[$row] = ($indentUnit * $row.Depth) + $row.Node.Name
    }

    # Widest rendered name (indent included) drives the padding so every tag
    # starts in the same column. Fall back to the root name width for an empty
    # tree so the total line's tag still aligns.
    $nameWidth = $root.Name.Length
    foreach ($name in $displayNames.Values) {
        if ($name.Length -gt $nameWidth) {
            $nameWidth = $name.Length
        }
    }

    $color   = 'DarkGreen'
    $banner  = "=== Timing report: $($root.Name) ==="
    $divider = '-' * $banner.Length

    Write-Host ''
    Write-Host $banner -ForegroundColor $color

    foreach ($row in $rows) {
        $node = $row.Node
        $tag  = Get-TimingSpanStatusTag -Status $node.Status
        # Shared elapsed-column authority: dash for an un-run row, else F2
        # seconds. The dash and the seconds field are the same width.
        $duration = Format-TimingSpanElapsed -ElapsedMs $node.ElapsedMs

        # A node that never ran (null ElapsedMs, e.g. a SKIPPED skeleton
        # branch) has no share; blank the percent.
        if ($null -eq $node.ElapsedMs) {
            $percent = ''
        } else {
            # Share of the parent's effective elapsed (captured on the row when
            # the tree was flattened). For a top-level row the parent is the
            # root, whose effective elapsed is the run total.
            if ($row.ParentEffective -gt 0) {
                $share = [int] [math]::Round(
                    ($node.ElapsedMs / [double] $row.ParentEffective) * 100)
                $percent = '({0,3}%)' -f $share
            } else {
                $percent = ''
            }
        }

        $line = '  {0}  {1}  {2}' -f
            $displayNames[$row].PadRight($nameWidth), $tag, $duration
        if ($percent) {
            $line = $line + '  ' + $percent
        }
        Write-Host $line -ForegroundColor $color
    }

    # Total counts the root's effective elapsed only: for a live root that is
    # the sum of its top-level spans (sub-step time is already inside them, so
    # it is never re-added), matching the 2-level report's total semantics.
    Write-Host ('  ' + $divider) -ForegroundColor $color
    Write-Host ('  total observed: ' +
        (Format-TimingSpanElapsed -ElapsedMs (getEffectiveElapsedMs $root))) `
        -ForegroundColor $color
    Write-Host $banner -ForegroundColor $color
}
