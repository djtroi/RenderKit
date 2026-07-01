[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PackagePath,

    [string]$ExpectedVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PackagePath = (Resolve-Path -LiteralPath $PackagePath).ProviderPath
$package = Get-Item -LiteralPath $PackagePath
$testRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('RenderKit-PackageTest-{0}' -f ([guid]::NewGuid().ToString('N')))
$extractRoot = Join-Path -Path $testRoot -ChildPath 'extracted'
$archive = $null

try {
    New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $archive = [System.IO.Compression.ZipFile]::OpenRead($PackagePath)
    $entryNames = @($archive.Entries | ForEach-Object { $_.FullName })

    foreach ($requiredEntry in @(
        'RenderKit.psd1',
        'RenderKit.psm1',
        'THIRD_PARTY_NOTICES.md',
        'src/Resources/ThirdParty/MediaInfo/manifest.json'
    )) {
        if ($entryNames -notcontains $requiredEntry) {
            throw "Package '$PackagePath' does not contain required entry '$requiredEntry'."
        }
    }

    $gitKeepEntries = @($entryNames | Where-Object { $_ -like '*.gitkeep' })
    if ($gitKeepEntries.Count -gt 0) {
        throw "Package '$PackagePath' contains placeholder entries: $($gitKeepEntries -join ', ')."
    }

    $mediaInfoEntries = @(
        $entryNames |
            Where-Object {
                $_ -like 'src/Resources/ThirdParty/MediaInfo/*' -and
                $_ -notlike '*/licenses/*' -and
                $_ -notlike '*/README.md' -and
                $_ -notlike '*/manifest.json'
            }
    )
    if ($mediaInfoEntries.Count -gt 0 -and
        $entryNames -notcontains 'THIRD_PARTY_NOTICES.md') {
        throw 'Package contains MediaInfo assets but does not contain THIRD_PARTY_NOTICES.md.'
    }

    foreach ($entry in $archive.Entries) {
        if ([string]::IsNullOrEmpty($entry.Name)) {
            continue
        }

        $entryStream = $entry.Open()
        try {
            $buffer = New-Object byte[] 81920
            while ($entryStream.Read($buffer, 0, $buffer.Length) -gt 0) {
            }
        }
        finally {
            $entryStream.Dispose()
        }
    }

    $archive.Dispose()
    $archive = $null

    [System.IO.Compression.ZipFile]::ExtractToDirectory($PackagePath, $extractRoot)

    $mediaInfoRoot = Join-Path `
        -Path $extractRoot `
        -ChildPath 'src/Resources/ThirdParty/MediaInfo'
    $mediaInfoManifest = Get-Content `
        -LiteralPath (Join-Path $mediaInfoRoot 'manifest.json') `
        -Raw |
        ConvertFrom-Json
    foreach ($runtime in @($mediaInfoManifest.runtimeIdentifiers)) {
        if (-not [bool]$runtime.bundledNative) {
            continue
        }

        $nativePath = Join-Path `
            -Path $mediaInfoRoot `
            -ChildPath ([string]$runtime.nativeLibraryRelativePath)
        if (-not (Test-Path -LiteralPath $nativePath -PathType Leaf)) {
            throw "Package is missing MediaInfo native asset for '$($runtime.rid)': $nativePath"
        }

        $nativeHash = (Get-FileHash -LiteralPath $nativePath -Algorithm SHA256).Hash
        if ($nativeHash -ne [string]$runtime.nativeLibrarySha256) {
            throw "Package MediaInfo native asset hash mismatch for '$($runtime.rid)'."
        }

        foreach ($dependencyPath in @(
            $runtime.nativeDependencyRelativePaths |
                ForEach-Object { [string]$_ }
        )) {
            $dependency = Join-Path $mediaInfoRoot $dependencyPath
            if (-not (Test-Path -LiteralPath $dependency -PathType Leaf)) {
                throw "Package is missing MediaInfo dependency for '$($runtime.rid)': $dependency"
            }
            $expectedDependencyHash = [string](
                $runtime.nativeDependencySha256.PSObject.Properties[$dependencyPath].Value
            )
            $dependencyHash = (
                Get-FileHash -LiteralPath $dependency -Algorithm SHA256
            ).Hash
            if ($dependencyHash -ne $expectedDependencyHash) {
                throw "Package MediaInfo dependency hash mismatch for '$($runtime.rid)': $dependencyPath"
            }
        }

        $licenseRoot = Join-Path `
            -Path $mediaInfoRoot `
            -ChildPath ([string]$runtime.licenseDirectoryRelativePath)
        $licenseFiles = @(
            Get-ChildItem `
                -LiteralPath $licenseRoot `
                -File `
                -ErrorAction SilentlyContinue
        )
        if ($licenseFiles.Count -eq 0) {
            throw "Package is missing MediaInfo license files for '$($runtime.rid)'."
        }
    }

    $manifestPath = Join-Path -Path $extractRoot -ChildPath 'RenderKit.psd1'
    $manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop

    if ($ExpectedVersion -and $manifest.Version.ToString() -ne $ExpectedVersion) {
        throw "Expected module version '$ExpectedVersion', but package contains '$($manifest.Version)'."
    }

    Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
    Import-Module $manifestPath -Force -ErrorAction Stop

    $importedModule = Get-Module -Name RenderKit
    if (-not $importedModule) {
        throw 'RenderKit was not loaded from the extracted package.'
    }

    $expectedFunctions = @($manifest.ExportedFunctions.Keys)
    $actualFunctions = @(Get-Command -Module RenderKit -CommandType Function | Select-Object -ExpandProperty Name)
    $missingFunctions = @($expectedFunctions | Where-Object { $actualFunctions -notcontains $_ })

    if ($missingFunctions.Count -gt 0) {
        throw "Package import is missing exported functions: $($missingFunctions -join ', ')."
    }

    [PSCustomObject]@{
        PackagePath    = $package.FullName
        PackageBytes   = $package.Length
        PackageSha256  = (Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash
        EntryCount     = $entryNames.Count
        ModuleVersion  = $manifest.Version.ToString()
        ExportedCount  = $expectedFunctions.Count
        Validation     = 'Passed'
    }
}
finally {
    if ($null -ne $archive) {
        $archive.Dispose()
    }

    Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
