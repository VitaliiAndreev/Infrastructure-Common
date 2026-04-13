function Invoke-TagFromManifest {
    # Reads the ModuleVersion from the given .psd1 manifest and creates a
    # matching git tag, then pushes it to origin. If the tag already exists
    # (e.g. the psd1 was touched without a version bump, or the workflow
    # re-ran), the step is skipped silently.
    #
    # Pushing the tag triggers the publish workflow, which runs tests and
    # publishes the module to PSGallery.
    param(
        [Parameter(Mandatory)]
        [string] $Psd1
    )

    $version = (Import-PowerShellDataFile $Psd1).ModuleVersion

    # git tag -l returns the tag name if it exists, empty string otherwise.
    if (git tag -l $version) {
        Write-Host "Tag '$version' already exists - nothing to do."
        return
    }

    git tag $version
    git push origin $version
    Write-Host "Created and pushed tag '$version'."
}
