[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$PackagePath
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$bundleRoot = Join-Path `
    -Path $repositoryRoot `
    -ChildPath 'src/Resources/ThirdParty/TagLibSharp'
$packageUri =
    'https://api.nuget.org/v3-flatcontainer/taglibsharp/2.3.0/taglibsharp.2.3.0.nupkg'
$packageSha256 =
    '3C3F5B55988F69E0BC84DC760FEB8351FEF4D5C09A322D88462E683D334DFBFC'
$licenseUri =
    'https://raw.githubusercontent.com/mono/taglib-sharp/TaglibSharp-2.3.0.0/COPYING'
$licenseSha256 =
    '6095E9FFA777DD22839F7801AA845B31C9ED07F3D6BF8A26DC5D2DEC8CCC0EF3'
$assemblyHashes = @{
    'lib/net462/TagLibSharp.dll' =
        'B1833A41AB1E933F7B006E5DB15300B7223BFCCC2C3B6689D49A9171DD27DE1D'
    'lib/netstandard2.0/TagLibSharp.dll' =
        'DAD93B152D55CF6A58B2037BCF9DD34B45D87761FE5ED61A232B3D4641D2A5D3'
}

function Assert-RenderKitTagLibSharpHash {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$ExpectedSha256
    )

    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne $ExpectedSha256) {
        throw "SHA-256 mismatch for '$Path'. Expected $ExpectedSha256, got $actual."
    }
}

$temporaryRoot = Join-Path `
    -Path ([System.IO.Path]::GetTempPath()) `
    -ChildPath ('RenderKit-TagLibSharp-{0}' -f [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    $package = if ([string]::IsNullOrWhiteSpace($PackagePath)) {
        $downloadPath = Join-Path $temporaryRoot 'taglibsharp.2.3.0.nupkg'
        Invoke-WebRequest `
            -Uri $packageUri `
            -OutFile $downloadPath `
            -UseBasicParsing
        $downloadPath
    }
    else {
        (Resolve-Path -LiteralPath $PackagePath -ErrorAction Stop).ProviderPath
    }
    Assert-RenderKitTagLibSharpHash `
        -Path $package `
        -ExpectedSha256 $packageSha256

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $extractRoot = Join-Path $temporaryRoot 'package'
    [System.IO.Compression.ZipFile]::ExtractToDirectory($package, $extractRoot)
    foreach ($entry in $assemblyHashes.GetEnumerator()) {
        $source = Join-Path $extractRoot ($entry.Key -replace '/', '\')
        Assert-RenderKitTagLibSharpHash `
            -Path $source `
            -ExpectedSha256 $entry.Value
    }

    $licensePath = Join-Path $temporaryRoot 'COPYING'
    Invoke-WebRequest `
        -Uri $licenseUri `
        -OutFile $licensePath `
        -UseBasicParsing
    Assert-RenderKitTagLibSharpHash `
        -Path $licensePath `
        -ExpectedSha256 $licenseSha256

    if ($PSCmdlet.ShouldProcess($bundleRoot, 'Stage TagLibSharp assemblies')) {
        foreach ($directory in @(
            'net462',
            'netstandard2.0',
            'licenses'
        )) {
            New-Item `
                -ItemType Directory `
                -Path (Join-Path $bundleRoot $directory) `
                -Force |
                Out-Null
        }
        Copy-Item `
            -LiteralPath (Join-Path $extractRoot 'lib/net462/TagLibSharp.dll') `
            -Destination (Join-Path $bundleRoot 'net462/TagLibSharp.dll') `
            -Force
        Copy-Item `
            -LiteralPath (
                Join-Path $extractRoot 'lib/netstandard2.0/TagLibSharp.dll'
            ) `
            -Destination (
                Join-Path $bundleRoot 'netstandard2.0/TagLibSharp.dll'
            ) `
            -Force
        Copy-Item `
            -LiteralPath $licensePath `
            -Destination (Join-Path $bundleRoot 'licenses/COPYING') `
            -Force
    }
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
