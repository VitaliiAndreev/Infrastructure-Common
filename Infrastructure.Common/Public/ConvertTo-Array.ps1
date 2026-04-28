# ---------------------------------------------------------------------------
# ConvertTo-Array
#   Ensures the input is always a PowerShell array, regardless of how many
#   items the caller received.
#
#   PowerShell automatically unrolls single-item collections when they are
#   returned from functions or the pipeline. This means a caller expecting
#   an array may receive a bare PSCustomObject instead, causing .Count and
#   index access ([0]) to fail with PropertyNotFoundException.
#
#   Wrapping with @() fixes this, but using a named function makes the
#   intent explicit and avoids the trap of writing @() inside an
#   if-expression, which yields $null (Pester 5 quirk).
#
#   Typical usage:
#       $items = ConvertTo-Array (Invoke-GitHubApi ...)
#       if ($items.Count -gt 0) { ... }
# ---------------------------------------------------------------------------

function ConvertTo-Array {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        # The value to ensure is an array. Accepts $null, a scalar, or a
        # collection of any size.
        [Parameter(Mandatory)]
        [AllowNull()]
        $InputObject
    )

    # $null is treated as "no items" (matches what callers expect when an API
    # returns nothing). @($null) would give a one-element array containing
    # $null, which is wrong in that context.
    if ($null -eq $InputObject) { return , @() }

    # The unary comma wraps the result in an outer array before writing to the
    # output stream. PowerShell unrolls that outer layer on assignment, leaving
    # the caller with @($InputObject) rather than $InputObject unrolled to a
    # scalar (which would happen with a bare @($InputObject) return).
    , @($InputObject)
}
