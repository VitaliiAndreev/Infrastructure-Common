<#
.NOTES
    Module-internal. Dot-sourced by the psm1 before the Public\Timing\ verbs.
    Not exported. The single authority for the elapsed column shared by both
    console renderers (Write-TimingSpanReport and the 2-level compat
    Write-PhaseTimingReport) so the column's width and number format cannot
    drift between them.
#>

# ---------------------------------------------------------------------------
# Format-TimingSpanElapsed
#   Render the fixed-width elapsed cell for one span row. A node that never
#   ran (null ElapsedMs, e.g. a SKIPPED skeleton branch) shows a dash
#   placeholder; a node that ran shows F2 seconds under invariant culture so
#   '.' is the decimal separator on every host and rows stay parseable and
#   column-aligned regardless of regional settings.
#
#   The dash placeholder and the '{0,8:F2} s' field are the same 10-character
#   width, so the two branches line up under the same column.
# ---------------------------------------------------------------------------

function Format-TimingSpanElapsed {
    [CmdletBinding()]
    param(
        # Milliseconds, or $null for a span that never ran. Untyped so the
        # null / int64 distinction survives binding.
        $ElapsedMs
    )

    if ($null -eq $ElapsedMs) {
        return '     -    '
    }

    return [string]::Format(
        [cultureinfo]::InvariantCulture,
        '{0,8:F2} s',
        ($ElapsedMs / 1000.0))
}
