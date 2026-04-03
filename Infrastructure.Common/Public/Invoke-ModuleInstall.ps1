function Invoke-ModuleInstall {
    <#
    .SYNOPSIS
        Installs a module from PSGallery if absent or below the required
        minimum version, then imports it.

    .DESCRIPTION
        Centralises the install-if-missing pattern used by all infrastructure
        setup scripts. Extracting it here makes the logic testable and removes
        the need for each consumer repo to duplicate it.

        Note: this function cannot bootstrap itself. Each consumer script
        still needs a short inline guard to install Infrastructure.Common
        before this function is available - but that is a one-time cost
        per script, and all other module installs flow through this function.

    .PARAMETER ModuleName
        The name of the module to install and import.

    .PARAMETER MinimumVersion
        The minimum acceptable version. If the installed version is below
        this, the module is reinstalled. When omitted, any installed version
        is accepted and only a missing module triggers an install.

    .EXAMPLE
        Invoke-ModuleInstall -ModuleName 'Infrastructure.Secrets' `
            -MinimumVersion '1.1.0'

    .EXAMPLE
        Invoke-ModuleInstall -ModuleName 'Posh-SSH'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ModuleName,

        [Parameter()]
        [Version] $MinimumVersion
    )

    $installed = Get-Module -ListAvailable -Name $ModuleName |
        Sort-Object Version -Descending | Select-Object -First 1

    # When MinimumVersion is omitted, install only if the module is absent.
    # When provided, also reinstall if the version is too old.
    $needsInstall = -not $installed -or
        ($MinimumVersion -and $installed.Version -lt $MinimumVersion)

    if ($needsInstall) {
        $versionLabel = if ($MinimumVersion) { " >= $MinimumVersion" } else { '' }
        Write-Host "Installing $ModuleName$versionLabel from PSGallery ..." `
            -ForegroundColor Cyan
        Install-Module $ModuleName -Scope CurrentUser -Force
    }

    Import-Module $ModuleName -Force -ErrorAction Stop
}
