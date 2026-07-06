<#
.NOTES
    Module-internal. Dot-sourced by the psm1 before the Public\Timing\ verbs.
    Not exported. The single authority for the status -> fixed-width tag map
    shared by both console renderers (Write-TimingSpanReport and the 2-level
    compat Write-PhaseTimingReport) so the tags stay identical and the same
    width across both.
#>

# ---------------------------------------------------------------------------
# Get-TimingSpanStatusTag
#   Map a node's lifecycle Status to its fixed-width display tag. Every tag is
#   padded to the same width so the duration column aligns whether a span
#   passed, failed, is still running, or never started. NotStarted is the
#   skeleton "declared but never run" state, surfaced as SKIPPED.
# ---------------------------------------------------------------------------

function Get-TimingSpanStatusTag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Status
    )

    $tags = @{
        'NotStarted' = '[SKIPPED]'
        'Running'    = '[RUNNING]'
        'OK'         = '[OK]     '
        'Failed'     = '[FAILED] '
    }

    return $tags[$Status]
}
