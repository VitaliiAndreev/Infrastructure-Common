function Assert-RequiredProperties {
    <#
    .SYNOPSIS
        Validates that an object has all required properties and none are empty.
        Throws a descriptive error if any property is missing or blank.

    .DESCRIPTION
        Used by consumer repos to validate JSON config entries without
        duplicating the PS 5.1-compatible Get-Member + IsNullOrWhiteSpace
        loop.

    .PARAMETER Object
        The PSCustomObject to validate (e.g. a single config entry).

    .PARAMETER Properties
        Array of property names that must be present and non-empty.

    .PARAMETER Context
        String used in error messages to identify the object
        (e.g. "VM 'ubuntu-01-ci'").

    .EXAMPLE
        Assert-RequiredProperties -Object $vm `
            -Properties @('vmName', 'ipAddress') `
            -Context "VM '$($vm.vmName)'"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Object,

        [Parameter(Mandatory)]
        [string[]] $Properties,

        [Parameter(Mandatory)]
        [string] $Context
    )

    # Get-Member -MemberType NoteProperty is the reliable way to enumerate
    # properties created by ConvertFrom-Json in PS 5.1 and PS 7.
    $members = (Get-Member -InputObject $Object -MemberType NoteProperty).Name

    # Collect all errors before throwing so the consumer sees the full picture
    # in one run rather than fixing one property at a time.
    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($property in $Properties) {
        if ($members -notcontains $property) {
            $errors.Add("$Context is missing required property '$property'.")
            continue
        }

        # Cast to [string] before IsNullOrWhiteSpace: numeric properties
        # (e.g. cpuCount) are [int] in PS 5.1 and the method requires [string].
        if ([string]::IsNullOrWhiteSpace([string]($Object.$property))) {
            $errors.Add("$Context has empty required property '$property'.")
        }
    }

    if ($errors.Count -gt 0) {
        throw ($errors -join [Environment]::NewLine)
    }
}
