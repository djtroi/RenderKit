[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ArchiveRoot
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$bundleRoot = Join-Path `
    -Path $repositoryRoot `
    -ChildPath 'src/Resources/ThirdParty/ExifTool'
$version = '13.59'
$downloads = @(
    @{
        Name = "Image-ExifTool-$version.tar.gz"
        Uri = "https://downloads.sourceforge.net/project/exiftool/Image-ExifTool-$version.tar.gz"
        Sha256 = '668EA3ACECECB7235FBD0F4900E72D5F12C9B07E5C778FD36CB1E9B5828FD65A'
    },
    @{
        Name = "exiftool-${version}_32.zip"
        Uri = "https://downloads.sourceforge.net/project/exiftool/exiftool-${version}_32.zip"
        Sha256 = 'FE9A55D28B05C1B0E18877B4881F40D83DB222F90018963473CFF798E8BF05AF'
    },
    @{
        Name = "exiftool-${version}_64.zip"
        Uri = "https://downloads.sourceforge.net/project/exiftool/exiftool-${version}_64.zip"
        Sha256 = '44B512B25AF500724BA579D0A53C8FC5851628B692DD5E5D94AE4A15C2CBA9EC'
    }
)

function Assert-RenderKitExifToolHash {
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

function Get-RenderKitExifToolArchive {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Definition,

        [Parameter(Mandatory)]
        [string]$DownloadDirectory
    )

    $path = if ([string]::IsNullOrWhiteSpace($ArchiveRoot)) {
        Join-Path $DownloadDirectory $Definition.Name
    }
    else {
        Join-Path ([System.IO.Path]::GetFullPath($ArchiveRoot)) $Definition.Name
    }

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        if (-not [string]::IsNullOrWhiteSpace($ArchiveRoot)) {
            throw "Required ExifTool archive not found: '$path'."
        }

        Write-Verbose "Downloading $($Definition.Uri)"
        Invoke-WebRequest `
            -Uri $Definition.Uri `
            -OutFile $path `
            -UseBasicParsing
    }

    Assert-RenderKitExifToolHash `
        -Path $path `
        -ExpectedSha256 $Definition.Sha256
    return [System.IO.Path]::GetFullPath($path)
}

function Expand-RenderKitExifToolTarGzip {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    $tar = Get-Command -Name tar -CommandType Application -ErrorAction Stop
    New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    & $tar.Source -xzf $Path -C $DestinationPath
    if ($LASTEXITCODE -ne 0) {
        throw "tar failed to extract '$Path' with exit code $LASTEXITCODE."
    }
}

function Expand-RenderKitExifToolZipEntry {
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

function Copy-RenderKitExifToolPayload {
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [Parameter(Mandatory)]
        [string]$DestinationRoot
    )

    $winX86Source = Join-Path $SourceRoot "win-x86/exiftool-${version}_32"
    $winX64Source = Join-Path $SourceRoot "win-x64/exiftool-${version}_64"
    $portableSource = Join-Path $SourceRoot "portable/Image-ExifTool-$version"
    foreach ($required in @(
        (Join-Path $winX86Source 'exiftool(-k).exe'),
        (Join-Path $winX86Source 'exiftool_files'),
        (Join-Path $winX64Source 'exiftool(-k).exe'),
        (Join-Path $winX64Source 'exiftool_files'),
        (Join-Path $portableSource 'exiftool'),
        (Join-Path $portableSource 'lib'),
        (Join-Path $portableSource 'README')
    )) {
        if (-not (Test-Path -LiteralPath $required)) {
            throw "Expected ExifTool payload is missing: '$required'."
        }
    }

    foreach ($directory in @('win-x86', 'win-x64', 'portable', 'licenses')) {
        New-Item `
            -ItemType Directory `
            -Path (Join-Path $DestinationRoot $directory) `
            -Force |
            Out-Null
    }

    Copy-Item `
        -LiteralPath (Join-Path $winX86Source 'exiftool_files') `
        -Destination (Join-Path $DestinationRoot 'win-x86') `
        -Recurse
    Copy-Item `
        -LiteralPath (Join-Path $winX86Source 'exiftool(-k).exe') `
        -Destination (Join-Path $DestinationRoot 'win-x86/exiftool.exe')
    Copy-Item `
        -LiteralPath (Join-Path $winX86Source 'README.txt') `
        -Destination (Join-Path $DestinationRoot 'win-x86/README.txt')

    Copy-Item `
        -LiteralPath (Join-Path $winX64Source 'exiftool_files') `
        -Destination (Join-Path $DestinationRoot 'win-x64') `
        -Recurse
    Copy-Item `
        -LiteralPath (Join-Path $winX64Source 'exiftool(-k).exe') `
        -Destination (Join-Path $DestinationRoot 'win-x64/exiftool.exe')
    Copy-Item `
        -LiteralPath (Join-Path $winX64Source 'README.txt') `
        -Destination (Join-Path $DestinationRoot 'win-x64/README.txt')

    Copy-Item `
        -LiteralPath (Join-Path $portableSource 'exiftool') `
        -Destination (Join-Path $DestinationRoot 'portable/exiftool')
    Copy-Item `
        -LiteralPath (Join-Path $portableSource 'lib') `
        -Destination (Join-Path $DestinationRoot 'portable') `
        -Recurse
    Copy-Item `
        -LiteralPath (Join-Path $portableSource 'README') `
        -Destination (Join-Path $DestinationRoot 'licenses/ExifTool-README.txt')

    $perlLicenses = Join-Path `
        -Path $DestinationRoot `
        -ChildPath 'win-x64/exiftool_files/Licenses_Strawberry_Perl.zip'
    Expand-RenderKitExifToolZipEntry `
        -Path $perlLicenses `
        -EntryName 'perl/Artistic' `
        -DestinationPath (Join-Path $DestinationRoot 'licenses/Perl-Artistic.txt')
    Expand-RenderKitExifToolZipEntry `
        -Path $perlLicenses `
        -EntryName 'perl/Copying' `
        -DestinationPath (Join-Path $DestinationRoot 'licenses/Perl-Copying.txt')
}

function Write-RenderKitExifToolHashManifest {
    param(
        [Parameter(Mandatory)]
        [string]$Root
    )

    $hashPath = Join-Path $Root 'files.sha256'
    $lines = @(
        Get-ChildItem -LiteralPath $Root -Recurse -File |
            Where-Object {
                $_.FullName -ne $hashPath -and
                $_.Name -notin @('manifest.json', 'README.md')
            } |
            Sort-Object FullName |
            ForEach-Object {
                $relativePath = $_.FullName.
                    Substring($Root.Length).
                    TrimStart('\', '/').
                    Replace('\', '/')
                $hash = (Get-FileHash `
                    -LiteralPath $_.FullName `
                    -Algorithm SHA256).Hash.ToLowerInvariant()
                '{0}  {1}' -f $hash, $relativePath
            }
    )
    [System.IO.File]::WriteAllLines(
        $hashPath,
        [string[]]$lines,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

$workRoot = Join-Path `
    -Path ([System.IO.Path]::GetTempPath()) `
    -ChildPath ('RenderKit-ExifTool-Sync-{0}' -f ([guid]::NewGuid().ToString('N')))
$workRoot = [System.IO.Path]::GetFullPath($workRoot)
$requestedWhatIf = [bool]$WhatIfPreference

try {
    # Staging is always temporary and must still be materialized for a useful
    # -WhatIf validation. Only the final bundle replacement is conditional.
    $WhatIfPreference = $false
    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
    $downloadRoot = Join-Path $workRoot 'downloads'
    $extractRoot = Join-Path $workRoot 'extract'
    $stagingRoot = Join-Path $workRoot 'staging'
    New-Item `
        -ItemType Directory `
        -Path $downloadRoot, $extractRoot, $stagingRoot `
        -Force |
        Out-Null

    $archives = @{}
    foreach ($download in $downloads) {
        $archives[$download.Name] = Get-RenderKitExifToolArchive `
            -Definition $download `
            -DownloadDirectory $downloadRoot
    }

    Expand-Archive `
        -LiteralPath $archives["exiftool-${version}_32.zip"] `
        -DestinationPath (Join-Path $extractRoot 'win-x86')
    Expand-Archive `
        -LiteralPath $archives["exiftool-${version}_64.zip"] `
        -DestinationPath (Join-Path $extractRoot 'win-x64')
    Expand-RenderKitExifToolTarGzip `
        -Path $archives["Image-ExifTool-$version.tar.gz"] `
        -DestinationPath (Join-Path $extractRoot 'portable')
    Copy-RenderKitExifToolPayload `
        -SourceRoot $extractRoot `
        -DestinationRoot $stagingRoot

    $WhatIfPreference = $requestedWhatIf
    if ($PSCmdlet.ShouldProcess(
            $bundleRoot,
            "Install verified ExifTool $version payload")) {
        $WhatIfPreference = $false
        $resolvedBundleRoot = [System.IO.Path]::GetFullPath($bundleRoot)
        $resolvedRepositoryRoot = [System.IO.Path]::GetFullPath($repositoryRoot)
        if (-not $resolvedBundleRoot.StartsWith(
                $resolvedRepositoryRoot,
                [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to modify bundle outside repository: '$resolvedBundleRoot'."
        }

        foreach ($directory in @('win-x86', 'win-x64', 'portable', 'licenses')) {
            $destination = Join-Path $resolvedBundleRoot $directory
            if (Test-Path -LiteralPath $destination) {
                Remove-Item -LiteralPath $destination -Recurse -Force
            }
            Copy-Item `
                -LiteralPath (Join-Path $stagingRoot $directory) `
                -Destination $resolvedBundleRoot `
                -Recurse
        }
        Write-RenderKitExifToolHashManifest -Root $resolvedBundleRoot
    }
    $WhatIfPreference = $false

    [PSCustomObject]@{
        Component = 'ExifTool'
        ComponentVersion = $version
        BundleRoot = $bundleRoot
        FileCount = @(
            Get-ChildItem -LiteralPath $stagingRoot -Recurse -File
        ).Count
    }
}
finally {
    $WhatIfPreference = $false
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ((Test-Path -LiteralPath $workRoot -PathType Container) -and
        $workRoot.StartsWith(
            $tempRoot,
            [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $workRoot) -like 'RenderKit-ExifTool-Sync-*') {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
    }
    $WhatIfPreference = $requestedWhatIf
}
