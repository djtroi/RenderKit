function Add-BackupFileToArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ArchivePath,
        [Parameter(Mandatory)]
        [string]$FilePath,
        [string]$EntryPath
    )

    if (-not (Test-Path -Path $ArchivePath -PathType Leaf)) {
        throw "Archive '$ArchivePath' was not found."
    }
    if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
        throw "File '$FilePath' was not found."
    }

    $resolvedFilePath = (Resolve-Path -Path $FilePath -ErrorAction Stop).ProviderPath
    $entryName = $EntryPath
    if ([string]::IsNullOrWhiteSpace($entryName)) {
        $entryName = [System.IO.Path]::GetFileName($resolvedFilePath)
    }
    $entryName = $entryName -replace '\\', '/'

    $zip = [System.IO.Compression.ZipFile]::Open($ArchivePath, [System.IO.Compression.ZipArchiveMode]::Update)
    try {
        $existing = $zip.GetEntry($entryName)
        if ($existing) {
            $existing.Delete()
        }

        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip,
            $resolvedFilePath,
            $entryName,
            [System.IO.Compression.CompressionLevel]::Optimal
        )
    }
    finally {
        $zip.Dispose()
    }

    return [PSCustomObject]@{
        Added     = $true
        EntryPath = $entryName
        FilePath  = $resolvedFilePath
    }
}
