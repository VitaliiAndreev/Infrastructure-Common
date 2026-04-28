<#
.SYNOPSIS
    Shared PowerShell utilities for infrastructure repos.

.DESCRIPTION
    Provides cross-cutting utilities that are not specific to any single
    infrastructure concern (secrets, provisioning, users, etc.).

    Current functions:
    - Assert-RequiredProperties: validates object fields are present and
      non-empty; throws a descriptive error if not.
    - Get-GitHubAppToken: exchanges a GitHub App private key for a
      short-lived installation access token (JWT -> bearer token).
    - Get-PendingDeployment: returns the oldest non-terminal deployment for
      a given repo/environment, or $null if none exists.
    - Invoke-GitHubApi: general-purpose GitHub REST API caller; handles
      authentication, User-Agent, and JSON body serialization.
    - Invoke-ModuleInstall: installs a PSGallery module if absent or below a
      minimum version, then imports it.
    - Invoke-SshClientCommand: runs a shell command on a remote host via an SSH.NET
      SshClient and returns a normalised result object (Output, Error,
      ExitStatus).
    - Set-DeploymentStatus: posts a status update to an existing GitHub
      deployment (in_progress, success, failure, etc.).

    Each public function lives in its own file under Public\ and is
    dot-sourced below so diffs stay focused on a single function per commit.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Public\Assert-RequiredProperties.ps1"
. "$PSScriptRoot\Public\Get-GitHubAppToken.ps1"
. "$PSScriptRoot\Public\Get-PendingDeployment.ps1"
. "$PSScriptRoot\Public\Invoke-GitHubApi.ps1"
. "$PSScriptRoot\Public\Invoke-ModuleInstall.ps1"
. "$PSScriptRoot\Public\Invoke-SshClientCommand.ps1"
. "$PSScriptRoot\Public\Set-DeploymentStatus.ps1"

Export-ModuleMember -Function `
    Assert-RequiredProperties, `
    Get-GitHubAppToken, `
    Get-PendingDeployment, `
    Invoke-GitHubApi, `
    Invoke-ModuleInstall, `
    Invoke-SshClientCommand, `
    Set-DeploymentStatus
