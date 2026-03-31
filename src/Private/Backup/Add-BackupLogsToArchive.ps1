function Add-BackupLogsToArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ArchivePath,
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    Write-RenderKitLog -Level Debug -Message "Add-BackupLogsToArchive started: ArchivePath='$ArchivePath', ProjectRoot='$ProjectRoot'."

    if (-not (Test-Path -Path $ArchivePath -PathType Leaf)) {
        Write-RenderKitLog -Level Error -Message "Archive '$ArchivePath' was not found."
        throw "Archive '$ArchivePath' was not found."
    }
    if (-not (Test-Path -Path $ProjectRoot -PathType Container)) {
        Write-RenderKitLog -Level Warning -Message "Project root '$ProjectRoot' not found. Skipping log injection."
        return [PSCustomObject]@{
            AddedCount  = 0
            AddedEntries = @()
        }
    }

    $renderKitRoot = Join-Path $ProjectRoot ".renderkit"
    if (-not (Test-Path -Path $renderKitRoot -PathType Container)) {
        Write-RenderKitLog -Level Warning -Message "RenderKit metadata folder not found at '$renderKitRoot'. Skipping log injection."
        return [PSCustomObject]@{
            AddedCount  = 0
            AddedEntries = @()
        }
    }

    $logFiles = @(
        Get-ChildItem -Path $renderKitRoot -Recurse -File -Filter "*.log" -ErrorAction SilentlyContinue
    )
    if ($logFiles.Count -eq 0) {
        Write-RenderKitLog -Level Info -Message "No log files found under '$renderKitRoot'."
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

    Write-RenderKitLog -Level Debug -Message "Injected $($addedEntries.Count) log file(s) into archive '$ArchivePath'."

    return [PSCustomObject]@{
        AddedCount   = $addedEntries.Count
        AddedEntries = @($addedEntries.ToArray())
    }
}
