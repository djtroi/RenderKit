[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),

    [string]$CacheRoot = (Join-Path `
        -Path ([System.IO.Path]::GetTempPath()) `
        -ChildPath 'RenderKit-MediaInfo-Cache')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$componentVersion = '26.01'
$nuGetPackageVersion = '26.1.0'
$bundleRoot = Join-Path `
    -Path ([System.IO.Path]::GetFullPath($RepositoryRoot)) `
    -ChildPath 'src/Resources/ThirdParty/MediaInfo'
$CacheRoot = [System.IO.Path]::GetFullPath($CacheRoot)

$downloads = [ordered]@{
    WindowsX64 = @{
        FileName = 'MediaInfo_DLL_26.01_Windows_x64_WithoutInstaller.zip'
        Uri = 'https://mediaarea.net/download/binary/libmediainfo0/26.01/MediaInfo_DLL_26.01_Windows_x64_WithoutInstaller.zip'
        Sha256 = '3E6FBB6595F7B7D18402C8399BFEEFE9618C0CCA1A8ABED7A8EFA5CD82C2387C'
    }
    WindowsArm64 = @{
        FileName = 'MediaInfo_DLL_26.01_Windows_ARM64_WithoutInstaller.zip'
        Uri = 'https://mediaarea.net/download/binary/libmediainfo0/26.01/MediaInfo_DLL_26.01_Windows_ARM64_WithoutInstaller.zip'
        Sha256 = 'A0B6BF0CA258A16C2CC4429626C0DC7FAFA81B4AD09317AE808A21AB96B144FA'
    }
    MacUniversal = @{
        FileName = 'MediaInfo_DLL_26.01_Mac_x86_64+arm64.tar.bz2'
        Uri = 'https://mediaarea.net/download/binary/libmediainfo0/26.01/MediaInfo_DLL_26.01_Mac_x86_64%2Barm64.tar.bz2'
        Sha256 = 'BBDA90E8C5C1301863051C58F5853E1F5BB0F520D0E2AE08F6FFF8DAADB267F3'
    }
    CoreNative = @{
        FileName = 'mediainfo.core.native.26.1.0.nupkg'
        Uri = 'https://api.nuget.org/v3-flatcontainer/mediainfo.core.native/26.1.0/mediainfo.core.native.26.1.0.nupkg'
        Sha256 = '80A1E28EA53C7070361C15C3AD3E623B3EF24324E1C511A2AC811C5CE96A9151'
    }
    ZenLibLicense = @{
        FileName = 'ZenLib-License-0.4.41.txt'
        Uri = 'https://raw.githubusercontent.com/MediaArea/ZenLib/v0.4.41/License.txt'
        Sha256 = '054F4C5881D8906DF8B1255FDBB2EAA78F7422829CFA1C67EB1C9E252493BDDE'
    }
}

$expectedFiles = @{
    WindowsX64 = @{
        RelativePath = 'MediaInfo.dll'
        Sha256 = '35E040DDBC0BBEC2495AF938C084D98A3418F5928569EBD4C50237BC2CA98EEB'
    }
    WindowsArm64 = @{
        RelativePath = 'MediaInfo.dll'
        Sha256 = 'DA833DFA3CD166D2352E9202566BF9E0FEE96F34ED59291C587E30A003386CDB'
    }
    MacUniversal = @{
        RelativePath = 'MediaInfoLib/libmediainfo.0.dylib'
        Sha256 = 'FFF0091A571F98FD87C7946F8A43EFFC47585C75065E738291447FFEDDBC7E19'
    }
    LinuxX64 = @{
        RelativePath = 'runtimes/ubuntu.18.04-x64/native/libmediainfo.so'
        Sha256 = '601383FEA0509948A01235D3D8F5958A1E7603846FA545766C8C455C448802A6'
    }
    LinuxX64Zen = @{
        RelativePath = 'runtimes/ubuntu.18.04-x64/native/libzen.so.0'
        Sha256 = '3E3511C93C35B6EBFC5723432CFE34B4D975B13608B5884AF9C94EEF57148F26'
    }
    MediaInfoLicense = @{
        RelativePath = 'Developers/License.html'
        Sha256 = 'DA6D89C8E74013FA1BE6065EF6B04C7198292100EAE1C81703D6B80A3F81ABEE'
    }
}

function Assert-RenderKitFileHash {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$ExpectedSha256
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file '$Path' was not found."
    }

    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne $ExpectedSha256) {
        throw "SHA-256 mismatch for '$Path'. Expected $ExpectedSha256, got $actual."
    }
}

function Get-RenderKitVerifiedDownload {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Definition
    )

    New-Item -ItemType Directory -Path $CacheRoot -Force | Out-Null
    $destination = Join-Path -Path $CacheRoot -ChildPath $Definition.FileName
    if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
        Invoke-WebRequest `
            -Uri $Definition.Uri `
            -OutFile $destination `
            -UseBasicParsing
    }

    Assert-RenderKitFileHash `
        -Path $destination `
        -ExpectedSha256 $Definition.Sha256
    return $destination
}

function Expand-RenderKitZipArchive {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    [System.IO.Compression.ZipFile]::ExtractToDirectory($Path, $DestinationPath)
}

function Expand-RenderKitZipEntry {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$EntryName,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = @(
            $archive.Entries |
                Where-Object { $_.FullName -eq $EntryName } |
                Select-Object -First 1
        )
        if (-not $entry) {
            throw "Archive '$Path' does not contain '$EntryName'."
        }

        New-Item `
            -ItemType Directory `
            -Path (Split-Path -Parent $DestinationPath) `
            -Force |
            Out-Null
        $inputStream = $entry.Open()
        try {
            $outputStream = [System.IO.File]::Create($DestinationPath)
            try {
                $inputStream.CopyTo($outputStream)
            }
            finally {
                $outputStream.Dispose()
            }
        }
        finally {
            $inputStream.Dispose()
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Expand-RenderKitTarBzipArchive {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    $tar = Get-Command -Name tar -CommandType Application -ErrorAction Stop
    New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    & $tar.Source -xjf $Path -C $DestinationPath
    if ($LASTEXITCODE -ne 0) {
        throw "tar failed to extract '$Path' with exit code $LASTEXITCODE."
    }
}

function Copy-RenderKitVerifiedAsset {
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$DestinationPath,

        [Parameter(Mandatory)]
        [string]$ExpectedSha256
    )

    Assert-RenderKitFileHash `
        -Path $SourcePath `
        -ExpectedSha256 $ExpectedSha256
    New-Item `
        -ItemType Directory `
        -Path (Split-Path -Parent $DestinationPath) `
        -Force |
        Out-Null
    Copy-Item `
        -LiteralPath $SourcePath `
        -Destination $DestinationPath `
        -Force
    Assert-RenderKitFileHash `
        -Path $DestinationPath `
        -ExpectedSha256 $ExpectedSha256
}

$workRoot = Join-Path `
    -Path ([System.IO.Path]::GetTempPath()) `
    -ChildPath ('RenderKit-MediaInfo-Sync-{0}' -f ([guid]::NewGuid().ToString('N')))
$workRoot = [System.IO.Path]::GetFullPath($workRoot)

try {
    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null

    $archives = @{}
    foreach ($key in $downloads.Keys) {
        $archives[$key] = Get-RenderKitVerifiedDownload `
            -Definition $downloads[$key]
    }

    $windowsX64Root = Join-Path $workRoot 'windows-x64'
    $windowsArm64Root = Join-Path $workRoot 'windows-arm64'
    $macRoot = Join-Path $workRoot 'mac-universal'
    $coreNativeRoot = Join-Path $workRoot 'core-native'
    Expand-RenderKitZipArchive `
        -Path $archives.WindowsX64 `
        -DestinationPath $windowsX64Root
    Expand-RenderKitZipArchive `
        -Path $archives.WindowsArm64 `
        -DestinationPath $windowsArm64Root
    Expand-RenderKitTarBzipArchive `
        -Path $archives.MacUniversal `
        -DestinationPath $macRoot
    foreach ($linuxAsset in @(
        $expectedFiles.LinuxX64,
        $expectedFiles.LinuxX64Zen
    )) {
        Expand-RenderKitZipEntry `
            -Path $archives.CoreNative `
            -EntryName $linuxAsset.RelativePath `
            -DestinationPath (Join-Path `
                -Path $coreNativeRoot `
                -ChildPath $linuxAsset.RelativePath)
    }

    $mediaInfoLicense = Join-Path `
        -Path $windowsX64Root `
        -ChildPath $expectedFiles.MediaInfoLicense.RelativePath
    Assert-RenderKitFileHash `
        -Path $mediaInfoLicense `
        -ExpectedSha256 $expectedFiles.MediaInfoLicense.Sha256

    if ($PSCmdlet.ShouldProcess(
            $bundleRoot,
            "Install verified MediaInfo $componentVersion native assets")) {
        $assetCopies = @(
            @{
                Source = Join-Path $windowsX64Root $expectedFiles.WindowsX64.RelativePath
                Destination = Join-Path $bundleRoot 'win-x64/native/MediaInfo.dll'
                Sha256 = $expectedFiles.WindowsX64.Sha256
            },
            @{
                Source = Join-Path $windowsArm64Root $expectedFiles.WindowsArm64.RelativePath
                Destination = Join-Path $bundleRoot 'win-arm64/native/MediaInfo.dll'
                Sha256 = $expectedFiles.WindowsArm64.Sha256
            },
            @{
                Source = Join-Path $macRoot $expectedFiles.MacUniversal.RelativePath
                Destination = Join-Path $bundleRoot 'osx-x64/native/libmediainfo.dylib'
                Sha256 = $expectedFiles.MacUniversal.Sha256
            },
            @{
                Source = Join-Path $macRoot $expectedFiles.MacUniversal.RelativePath
                Destination = Join-Path $bundleRoot 'osx-arm64/native/libmediainfo.dylib'
                Sha256 = $expectedFiles.MacUniversal.Sha256
            },
            @{
                Source = Join-Path $coreNativeRoot $expectedFiles.LinuxX64.RelativePath
                Destination = Join-Path $bundleRoot 'linux-x64/native/libmediainfo.so'
                Sha256 = $expectedFiles.LinuxX64.Sha256
            },
            @{
                Source = Join-Path $coreNativeRoot $expectedFiles.LinuxX64Zen.RelativePath
                Destination = Join-Path $bundleRoot 'linux-x64/native/libzen.so.0'
                Sha256 = $expectedFiles.LinuxX64Zen.Sha256
            }
        )

        foreach ($copy in $assetCopies) {
            Copy-RenderKitVerifiedAsset `
                -SourcePath $copy.Source `
                -DestinationPath $copy.Destination `
                -ExpectedSha256 $copy.Sha256
        }

        foreach ($rid in @('win-x64', 'win-arm64', 'osx-x64', 'osx-arm64', 'linux-x64')) {
            $licenseRoot = Join-Path $bundleRoot "$rid/licenses"
            Copy-RenderKitVerifiedAsset `
                -SourcePath $mediaInfoLicense `
                -DestinationPath (Join-Path $licenseRoot 'MediaInfoLib-License.html') `
                -ExpectedSha256 $expectedFiles.MediaInfoLicense.Sha256

            if ($rid -eq 'linux-x64') {
                Copy-RenderKitVerifiedAsset `
                    -SourcePath $archives.ZenLibLicense `
                    -DestinationPath (Join-Path $licenseRoot 'ZenLib-License.txt') `
                    -ExpectedSha256 $downloads.ZenLibLicense.Sha256
            }
        }

        foreach ($placeholder in @(
            'win-x64/native/.gitkeep',
            'win-x64/licenses/.gitkeep',
            'win-arm64/native/.gitkeep',
            'win-arm64/licenses/.gitkeep',
            'osx-x64/native/.gitkeep',
            'osx-x64/licenses/.gitkeep',
            'osx-arm64/native/.gitkeep',
            'osx-arm64/licenses/.gitkeep',
            'linux-x64/native/.gitkeep',
            'linux-x64/licenses/.gitkeep'
        )) {
            $placeholderPath = Join-Path $bundleRoot $placeholder
            if (Test-Path -LiteralPath $placeholderPath -PathType Leaf) {
                Remove-Item -LiteralPath $placeholderPath -Force
            }
        }
    }

    [PSCustomObject]@{
        Component = 'MediaInfoLib'
        ComponentVersion = $componentVersion
        NuGetPackageVersion = $nuGetPackageVersion
        BundleRoot = $bundleRoot
        BundledRuntimeIdentifiers = @(
            'win-x64',
            'win-arm64',
            'osx-x64',
            'osx-arm64',
            'linux-x64'
        )
        ExternalFallbackRuntimeIdentifiers = @('linux-arm64')
    }
}
finally {
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $comparison = if (
        [System.Environment]::OSVersion.Platform -eq
        [System.PlatformID]::Win32NT
    ) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }

    if ((Test-Path -LiteralPath $workRoot -PathType Container) -and
        $workRoot.StartsWith($tempRoot, $comparison) -and
        (Split-Path -Leaf $workRoot) -like 'RenderKit-MediaInfo-Sync-*') {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
    }
}
