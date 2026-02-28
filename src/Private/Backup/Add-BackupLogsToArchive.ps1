function Add-BackupLogsToArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ArchivePath,
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    if (-not (Test-Path -Path $ArchivePath -PathType Leaf)) {
        throw "Archive '$ArchivePath' was not found."
    }
    if (-not (Test-Path -Path $ProjectRoot -PathType Container)) {
        return [PSCustomObject]@{
            AddedCount  = 0
            AddedEntries = @()
        }
    }

    $renderKitRoot = Join-Path $ProjectRoot ".renderkit"
    if (-not (Test-Path -Path $renderKitRoot -PathType Container)) {
        return [PSCustomObject]@{
            AddedCount  = 0
            AddedEntries = @()
        }
    }

    $logFiles = @(
        Get-ChildItem -Path $renderKitRoot -Recurse -File -Filter "*.log" -ErrorAction SilentlyContinue
    )
    if ($logFiles.Count -eq 0) {
        return [PSCustomObject]@{
            AddedCount  = 0
            AddedEntries = @()
        }
    }

    $addedEntries = New-Object System.Collections.Generic.List[string]
    $zip = [System.IO.Compression.ZipFile]::Open($ArchivePath, [System.IO.Compression.ZipArchiveMode]::Update)
    try {
        foreach ($logFile in $logFiles) {
            $relativeLogPath = $logFile.FullName.Substring($ProjectRoot.Length).TrimStart('\', '/') -replace '\\', '/'
            $entryName = "__renderkit_logs/$relativeLogPath"
            $existing = $zip.GetEntry($entryName)
            if ($existing) {
                $existing.Delete()
            }

            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip,
                $logFile.FullName,
                $entryName,
                [System.IO.Compression.CompressionLevel]::Optimal
            )
            $addedEntries.Add($entryName)
        }
    }
    finally {
        $zip.Dispose()
    }

    return [PSCustomObject]@{
        AddedCount   = $addedEntries.Count
        AddedEntries = @($addedEntries.ToArray())
    }
}
