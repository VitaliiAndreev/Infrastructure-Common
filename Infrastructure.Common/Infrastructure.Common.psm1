<#
.SYNOPSIS
    Shared PowerShell utilities for infrastructure repos.

.DESCRIPTION
    Provides cross-cutting utilities that are not specific to any single
    infrastructure concern (secrets, provisioning, users, etc.).

    Current functions:
    - Assert-RequiredProperties: validates object fields are present and
      non-empty; throws a descriptive error if not.
    - Invoke-ModuleInstall: installs a PSGallery module if absent or below a
      minimum version, then imports it.
    - Invoke-SshClientCommand: runs a shell command on a remote host via an SSH.NET
      SshClient and returns a normalised result object (Output, Error,
      ExitStatus).

    Each public function lives in its own file under Public\ and is
    dot-sourced below so diffs stay focused on a single function per commit.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Public\Assert-RequiredProperties.ps1"
. "$PSScriptRoot\Public\Invoke-GitHubApi.ps1"
. "$PSScriptRoot\Public\Invoke-ModuleInstall.ps1"
. "$PSScriptRoot\Public\Invoke-SshClientCommand.ps1"

Export-ModuleMember -Function Assert-RequiredProperties, Invoke-ModuleInstall, Invoke-SshClientCommand
