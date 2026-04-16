function Invoke-Publish {
    # Installs RequiredModules declared in the manifest, then publishes the
    # module to PSGallery. The API key is read from $env:API_KEY rather than
    # accepted as a parameter to keep it out of process listings.
    #
    # Test-ModuleManifest (called internally by Publish-Module) validates
    # RequiredModules against locally installed modules - it does not query
    # PSGallery. Installing them first ensures validation passes in clean
    # environments such as CI runners.
    param(
        [Parameter(Mandatory)]
        [string] $ModulePath
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $psd1 = Get-ChildItem $ModulePath -Filter '*.psd1' | Select-Object -First 1
    $manifest = Import-PowerShellDataFile $psd1.FullName
    foreach ($req in $manifest.RequiredModules) {
        $name = if ($req -is [hashtable]) { $req.ModuleName } else { $req }
        Write-Host "Installing dependency: $name ..."
        Install-Module $name -Repository PSGallery -Force -Scope CurrentUser -AllowClobber
    }

    Publish-Module -Path $ModulePath -NuGetApiKey $env:API_KEY -Repository PSGallery
}
