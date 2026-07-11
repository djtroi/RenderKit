[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$DownloadRoot = (
        Join-Path `
            -Path ([System.IO.Path]::GetTempPath()) `
            -ChildPath 'RenderKit-MKVToolNix'
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$bundleRoot = Join-Path `
    -Path $RepositoryRoot `
    -ChildPath 'src/Resources/ThirdParty/MKVToolNix'
$manifestPath = Join-Path $bundleRoot 'manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw |
    ConvertFrom-Json
$runtime = @(
    $manifest.runtimeIdentifiers |
        Where-Object { [string]$_.rid -eq 'win-x64' } |
        Select-Object -First 1
)
if (-not $runtime -or -not [bool]$runtime.bundled) {
    throw 'The MKVToolNix manifest has no bundled win-x64 runtime.'
}

New-Item -ItemType Directory -Path $DownloadRoot -Force | Out-Null
$archivePath = Join-Path `
    -Path $DownloadRoot `
    -ChildPath 'mkvtoolnix-64-bit-99.0.zip'
$sourcePath = Join-Path `
    -Path $DownloadRoot `
    -ChildPath 'mkvtoolnix-99.0.tar.xz'
if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
    Invoke-WebRequest `
        -Uri ([string]$manifest.archiveUrl) `
        -OutFile $archivePath `
        -UseBasicParsing
}
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    Invoke-WebRequest `
        -Uri ([string]$manifest.sourceUrl) `
        -OutFile $sourcePath `
        -UseBasicParsing
}

foreach ($check in @(
    [PSCustomObject]@{
        Path = $archivePath
        Expected = [string]$manifest.archiveSha256
        Name = 'archive'
    },
    [PSCustomObject]@{
        Path = $sourcePath
        Expected = [string]$manifest.sourceSha256
        Name = 'source archive'
    }
)) {
    $actual = (
        Get-FileHash -LiteralPath $check.Path -Algorithm SHA256
    ).Hash
    if ($actual -ne $check.Expected) {
        throw "MKVToolNix $($check.Name) SHA-256 mismatch."
    }
}

$extractRoot = Join-Path $DownloadRoot 'extracted'
if (Test-Path -LiteralPath $extractRoot) {
    Remove-Item -LiteralPath $extractRoot -Recurse -Force
}
Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot
$payloadRoot = Join-Path $extractRoot 'mkvtoolnix'

$copyDefinitions = @(
    [PSCustomObject]@{
        Source = Join-Path $payloadRoot 'mkvpropedit.exe'
        Destination = [string]$runtime.propEditRelativePath
        Expected = [string]$runtime.propEditSha256
    },
    [PSCustomObject]@{
        Source = Join-Path $payloadRoot 'mkvextract.exe'
        Destination = [string]$runtime.extractRelativePath
        Expected = [string]$runtime.extractSha256
    },
    [PSCustomObject]@{
        Source = $sourcePath
        Destination = [string]$manifest.sourceRelativePath
        Expected = [string]$manifest.sourceSha256
    }
)
foreach ($license in @($manifest.licenseFiles)) {
    $sourceName = [System.IO.Path]::GetFileName(
        [string]$license.relativePath
    )
    $licenseSource = if ($sourceName -in @(
            'COPYING.txt',
            'README.txt'
        )) {
        Join-Path (Join-Path $payloadRoot 'doc') $sourceName
    }
    else {
        Join-Path `
            -Path (Join-Path $payloadRoot 'doc/licenses') `
            -ChildPath $sourceName
    }
    $copyDefinitions += [PSCustomObject]@{
        Source = $licenseSource
        Destination = [string]$license.relativePath
        Expected = [string]$license.sha256
    }
}

foreach ($definition in $copyDefinitions) {
    if (-not (Test-Path -LiteralPath $definition.Source -PathType Leaf)) {
        throw "MKVToolNix payload is missing '$($definition.Source)'."
    }
    $actual = (
        Get-FileHash `
            -LiteralPath $definition.Source `
            -Algorithm SHA256
    ).Hash
    if ($actual -ne $definition.Expected) {
        throw "MKVToolNix extracted payload hash mismatch for '$($definition.Destination)'."
    }
    $destinationPath = Join-Path $bundleRoot $definition.Destination
    New-Item `
        -ItemType Directory `
        -Path (Split-Path -Parent $destinationPath) `
        -Force |
        Out-Null
    Copy-Item `
        -LiteralPath $definition.Source `
        -Destination $destinationPath `
        -Force
}

Remove-Item -LiteralPath $extractRoot -Recurse -Force

[PSCustomObject]@{
    Version = [string]$manifest.componentVersion
    BundleRoot = $bundleRoot
    Files = $copyDefinitions.Count
    ArchiveSha256 = [string]$manifest.archiveSha256
    SourceSha256 = [string]$manifest.sourceSha256
}
