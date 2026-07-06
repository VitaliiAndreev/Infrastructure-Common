<#
.NOTES
    Compatibility shim - the 2-level console report, re-expressed to read the
    default context's tree (root.Children = phases; each phase's Children =
    sub-steps) instead of the old flat $script:PhaseTimings list. Its output
    is byte-for-byte the pre-generalisation report (fixed banner, no
    percent column, top-level-only total) so provision.ps1's console
    behaviour and its Pester snapshot do not regress. The arbitrary-depth,
    percent-aware, merge-aware renderer is Write-TimingSpanReport; this verb
    is the legacy presentation only.
#>

function Write-PhaseTimingReport {
<#
.SYNOPSIS
    Emit the legacy 2-level provisioning timing report from the default context.

.DESCRIPTION
    Lists every declared phase with its status tag and (if it ran) elapsed
    time, sub-steps rendered indented two spaces under their parent. Designed
    to be called from an outer try/finally so the report appears on both the
    success and failure paths.

    The total line sums TOP-LEVEL phases only: sub-step time is already inside
    a parent phase's measured wall-clock, so adding it would double-count.
    Single colour (DarkGreen) so the block reads as one summary unit rather
    than competing with the per-row [OK]/[FAILED] text markers.
#>

    [CmdletBinding()]
    param()

    if ($null -eq $script:DefaultPhaseTimingTree) {
        return
    }

    # Flatten the 2-level tree back into the phase, sub-step, sub-step, next
    # phase order the old flat list rendered in - phases by Order, each
    # phase's sub-steps by Order immediately under it. IsSubStep drives the
    # indent and the total's top-level-only rule.
    $root = $script:DefaultPhaseTimingTree.Root
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($phase in ($root.Children | Sort-Object Order)) {
        $rows.Add([pscustomobject]@{ Node = $phase; IsSubStep = $false })
        foreach ($sub in ($phase.Children | Sort-Object Order)) {
            $rows.Add([pscustomobject]@{ Node = $sub; IsSubStep = $true })
        }
    }

    if ($rows.Count -eq 0) {
        return
    }

    # Column widths: account for the sub-step indent so the tag column lines
    # up across mixed top-level and sub-step rows.
    $subStepIndent = '  '
    $nameWidth = 0
    foreach ($row in $rows) {
        $width = if ($row.IsSubStep) {
            $row.Node.Name.Length + $subStepIndent.Length
        } else {
            $row.Node.Name.Length
        }
        if ($width -gt $nameWidth) { $nameWidth = $width }
    }

    $color   = 'DarkGreen'
    $banner  = '=== Provisioning timing report ==='
    $divider = '-' * $banner.Length

    Write-Host ''
    Write-Host $banner -ForegroundColor $color

    # Total observed wall-clock counts top-level rows only - sub-step time is
    # already inside a parent phase; adding it would double-count.
    $totalMs = 0
    foreach ($row in $rows) {
        $node     = $row.Node
        $tag      = Get-TimingSpanStatusTag -Status $node.Status
        # Shared elapsed-column authority: dash for an un-run row, else F2
        # seconds. Only top-level phases feed the total (see below).
        $duration = Format-TimingSpanElapsed -ElapsedMs $node.ElapsedMs
        if ($null -ne $node.ElapsedMs -and -not $row.IsSubStep) {
            $totalMs += $node.ElapsedMs
        }

        $displayName = if ($row.IsSubStep) {
            $subStepIndent + $node.Name
        } else {
            $node.Name
        }

        $line = '  {0}  {1}  {2}' -f
            $displayName.PadRight($nameWidth), $tag, $duration
        Write-Host $line -ForegroundColor $color
    }

    Write-Host ('  ' + $divider) -ForegroundColor $color
    Write-Host ('  total observed: ' +
        (Format-TimingSpanElapsed -ElapsedMs $totalMs)) -ForegroundColor $color
    Write-Host $banner -ForegroundColor $color
}
