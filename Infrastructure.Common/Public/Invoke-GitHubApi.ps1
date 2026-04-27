# ---------------------------------------------------------------------------
# Invoke-GitHubApi
#   General-purpose GitHub REST API caller. Handles authentication,
#   User-Agent, and JSON serialization in one place so callers only
#   need to supply a token, a URI, and an optional body.
#
#   -Token accepts both PATs and GitHub App installation tokens; both
#   are bearer tokens and are interchangeable at the HTTP level.
#
#   Returns the raw Invoke-RestMethod response. Callers extract the
#   fields they need (.token, .runners, .id, etc.).
# ---------------------------------------------------------------------------

function Invoke-GitHubApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Token,

        [Parameter(Mandatory)]
        [string] $Uri,

        [Parameter()]
        [string] $Method = 'Get',

        [Parameter()]
        [hashtable] $Body
    )

    $params = @{
        Uri         = $Uri
        Method      = $Method
        Headers     = @{
            'Authorization' = "Bearer $Token"
            'User-Agent'    = 'Infrastructure'
            'Content-Type'  = 'application/json'
        }
        ErrorAction = 'Stop'
    }

    if ($PSBoundParameters.ContainsKey('Body')) {
        $params['Body'] = $Body | ConvertTo-Json -Depth 10 -Compress
    }

    Invoke-RestMethod @params
}
