function Import-TimingSpanTree {
<#
.SYNOPSIS
    Rebuild a span subtree from a child process's JSON export - defensively.

.DESCRIPTION
    The parent half of the cross-process handoff. Reads a file written by
    Export-TimingSpanTree and returns its root node as an in-memory subtree
    (the same List[object]-backed node shape the live framework mints), ready
    for the E2E orchestrator to graft under the part span that invoked the
    child.

    Import is defensive by contract: a missing, empty, malformed, or
    root-less file yields $null with a warning and never throws. A child that
    crashed before finishing its export - or never ran - must not fail the
    parent's own end-of-run report; the caller simply leaves that part timed
    with no children.

    The schema version is not asserted here: an unknown-but-parseable
    document is imported best-effort by field name, so a newer child schema
    degrades to whatever fields this reader understands rather than being
    rejected outright.

.PARAMETER Path
    The JSON file to import (as written by Export-TimingSpanTree).

.OUTPUTS
    The reconstructed root node, or $null if the file is absent or unusable.

.EXAMPLE
    $subtree = Import-TimingSpanTree -Path $childTempPath
    if ($null -ne $subtree) { <graft $subtree.Children under the part span> }
#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Warning "Import-TimingSpanTree: no timing file at '$Path'; returning null."
        return $null
    }

    try {
        $document = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop

        # Read 'root' through PSObject.Properties so a document that parsed but
        # lacks the field returns null cleanly instead of tripping StrictMode.
        $rootProperty = if ($null -ne $document) {
            $document.PSObject.Properties['root']
        } else {
            $null
        }

        if ($null -eq $rootProperty -or $null -eq $rootProperty.Value) {
            Write-Warning "Import-TimingSpanTree: '$Path' has no root node; returning null."
            return $null
        }

        return ConvertFrom-TimingSpanImportNode -Node $rootProperty.Value
    }
    catch {
        # Any parse/shape failure is swallowed to a warning so a half-written
        # or corrupt child export cannot break the parent's report.
        Write-Warning "Import-TimingSpanTree: could not import '$Path': $($_.Exception.Message)"
        return $null
    }
}
