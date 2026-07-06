<#
.NOTES
    Module-internal. Dot-sourced by the psm1 before the Public\Timing\
    verbs. Not exported.
#>

# ---------------------------------------------------------------------------
# Add-TimingSpanNodeElapsed
#   Accumulate -ElapsedMs into a node and advance its terminal status. The
#   one implementation of the accumulate + sticky-status rule, shared by
#   Measure-TimingSpan (stopwatch path) and Add-TimingSpanDuration
#   (measure-less path) so the semantics cannot drift between them.
#
#   Status transitions (mirroring the 2-level Add-SubStepDuration contract):
#     NotStarted / Running -> OK      (successful call)
#     any                  -> Failed  (-Failed; sticky)
#     Failed               -> Failed  (a later success does NOT clear it, so
#                                      the report still surfaces the bad run)
# ---------------------------------------------------------------------------

function Add-TimingSpanNodeElapsed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Node,

        # Milliseconds to add to the node's running total.
        [Parameter(Mandatory)] [int64] $ElapsedMs,

        # Set when the measured work threw. Makes the status stickily Failed.
        [switch] $Failed
    )

    # ElapsedMs is $null on first contact, so the cast handles both the
    # initial and subsequent calls uniformly.
    $current = if ($null -eq $Node.ElapsedMs) { 0L } else { [int64]$Node.ElapsedMs }
    $Node.ElapsedMs = $current + $ElapsedMs

    if ($Failed) {
        $Node.Status = 'Failed'
    }
    elseif ($Node.Status -ne 'Failed') {
        $Node.Status = 'OK'
    }
}
