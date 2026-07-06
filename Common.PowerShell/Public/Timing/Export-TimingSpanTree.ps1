function Export-TimingSpanTree {
<#
.SYNOPSIS
    Serialise a timing tree to the versioned nested-JSON export schema.

.DESCRIPTION
    The child half of the cross-process handoff. Writes the context's whole
    span tree to -Path as a self-describing JSON document so another process
    (the E2E orchestrator) can import it and graft it under the part that
    invoked this one.

    Document shape (schema 'e2e-timing/v1'):
      {
        "schema": "e2e-timing/v1",
        "root": { "order": 0, "name": "...", "status": "...",
                  "elapsedMs": <int|null>, "source": <string|null>,
                  "children": [ ...same node shape, arbitrary depth... ] }
      }

    The nested tree is the artifact of record (explicit children[], first-
    class status, duration-only elapsedMs) - not a timestamp trace - so a
    cross-process merge is a subtree graft rather than a clock rebase, and
    the console report renders straight off it. Numbers are emitted by
    ConvertTo-Json, which is invariant-culture, so a comma-decimal locale
    cannot corrupt the artifact.

.PARAMETER Tree
    The context returned by New-TimingSpanTree whose Root is serialised.

.PARAMETER Path
    Destination file. The parent directory must already exist; the caller
    owns the path (typically a per-invocation temp file or a run's
    diagnostics folder).

.EXAMPLE
    Export-TimingSpanTree -Tree $tree -Path $env:TIMING_TREE_OUTPUT_PATH
#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Tree,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    # The wire schema tag. Bumped only if the on-disk shape changes in a way
    # importers must branch on; kept as a named constant so the one authority
    # for the current version is obvious.
    $schemaVersion = 'e2e-timing/v1'

    $document = [pscustomobject]@{
        schema = $schemaVersion
        root   = ConvertTo-TimingSpanExportNode -Node $Tree.Root
    }

    # -Depth must exceed the deepest span nesting; 64 is far beyond any real
    # phase/part/substep/graft chain, so ConvertTo-Json never truncates.
    $json = $document | ConvertTo-Json -Depth 64

    # utf8 (BOM-less on PowerShell 7 Core) keeps the artifact plain ASCII per
    # house style and portable to the bash side of the feature.
    Set-Content -LiteralPath $Path -Value $json -Encoding utf8
}
