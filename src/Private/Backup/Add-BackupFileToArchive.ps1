function Add-BackupFileToArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ArchivePath,
        [Parameter(Mandatory)]
        [string]$FilePath,
        [string]$EntryPath
    )

    Write-RenderKitLog -Level Debug -Message "Add-BackupFileToArchive started: ArchivePath='$ArchivePath', FilePath='$FilePath', EntryPath='$EntryPath'."

    if (-not (Test-Path -Path $ArchivePath -PathType Leaf)) {
        Write-RenderKitLog -Level Error -Message "Archive '$ArchivePath' was not found."
        throw "Archive '$ArchivePath' was not found."
    }
    if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
        Write-RenderKitLog -Level Error -Message "File '$FilePath' was not found."
        throw "File '$FilePath' was not found."
    }

    $resolvedFilePath = (Resolve-Path -Path $FilePath -ErrorAction Stop).ProviderPath
    $entryName = $EntryPath
    if ([string]::IsNullOrWhiteSpace($entryName)) {
        $entryName = [System.IO.Path]::GetFileName($resolvedFilePath)
    }
    $entryName = $entryName -replace '\\', '/'

    Write-RenderKitLog -Level Debug -Message "Adding '$resolvedFilePath' to archive '$ArchivePath' as '$entryName'."

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

    Write-RenderKitLog -Level Info -Message "Added '$resolvedFilePath' to archive '$ArchivePath' as '$entryName'."

    return [PSCustomObject]@{
        Added     = $true
        EntryPath = $entryName
        FilePath  = $resolvedFilePath
    }
}
