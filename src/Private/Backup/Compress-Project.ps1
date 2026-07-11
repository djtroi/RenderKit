function Compress-Project{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,
        [Parameter(Mandatory)]
        [string]$DestinationPath,
        [object]$DeduplicationPlan
    )

    Write-RenderKitLog -Level Debug -Message "Compress-Project started: ProjectPath='$ProjectPath', DestinationPath='$DestinationPath'."

    $resolvedProjectPath = (Resolve-Path -Path $ProjectPath -ErrorAction Stop).ProviderPath
    if (-not (Test-Path -Path $resolvedProjectPath -PathType Container)) {
        Write-RenderKitLog -Level Error -Message "Project path '$ProjectPath' is not a directory."
        throw "Project path '$ProjectPath' is not a directory."
    }

    $destinationDirectory = Split-Path -Path $DestinationPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($destinationDirectory) -and -not (Test-Path -Path $destinationDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }

    if (Test-Path -Path $DestinationPath -PathType Leaf) {
        Remove-Item -Path $DestinationPath -Force
    }

    $basePath = Split-Path -Path $resolvedProjectPath -Parent
    if ([string]::IsNullOrWhiteSpace($basePath)) {
        Write-RenderKitLog -Level Error -Message "Could not resolve base path for '$resolvedProjectPath'."
        throw "Could not resolve base path for '$resolvedProjectPath'."
    }

    $directories = @(
        Get-ChildItem -Path $resolvedProjectPath -Recurse -Directory -Force -ErrorAction SilentlyContinue
    )
    $files = @(
        Get-ChildItem -Path $resolvedProjectPath -Recurse -File -Force -ErrorAction SilentlyContinue
    )

    $dedupExcludedPathSet = Get-BackupDeduplicationExcludedPathSet -DeduplicationPlan $DeduplicationPlan
    $filesToArchive = New-Object System.Collections.Generic.List[object]
    $deduplicatedFileCount = 0
    $deduplicatedBytes = [int64]0
    foreach ($file in $files) {
        $projectRelativePath = $file.FullName.Substring($resolvedProjectPath.Length).TrimStart('\', '/') -replace '\\', '/'
        if ($dedupExcludedPathSet.ContainsKey($projectRelativePath)) {
            $deduplicatedFileCount++
            $deduplicatedBytes += [int64]$file.Length
            continue
        }

        $filesToArchive.Add($file)
    }

    Write-RenderKitLog -Level Debug -Message "Compress-Project collected items: Directories=$($directories.Count), Files=$($files.Count), ArchivedFiles=$($filesToArchive.Count), DeduplicatedFiles=$deduplicatedFileCount."

    $zip = [System.IO.Compression.ZipFile]::Open($DestinationPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $projectRootEntryName = $resolvedProjectPath.Substring($basePath.Length).TrimStart('\', '/') -replace '\\', '/'
        if (-not $projectRootEntryName.EndsWith('/')) {
            $projectRootEntryName = "$projectRootEntryName/"
        }
        [void]$zip.CreateEntry($projectRootEntryName)

        foreach ($directory in $directories) {
            $entryName = $directory.FullName.Substring($basePath.Length).TrimStart('\', '/') -replace '\\', '/'
            if (-not $entryName.EndsWith('/')) {
                $entryName = "$entryName/"
            }

            [void]$zip.CreateEntry($entryName)
        }

        foreach ($file in @($filesToArchive.ToArray())) {
            $entryName = $file.FullName.Substring($basePath.Length).TrimStart('\', '/') -replace '\\', '/'
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip,
                $file.FullName,
                $entryName,
                [System.IO.Compression.CompressionLevel]::Optimal
            )
        }
    }
    finally {
        $zip.Dispose()
    }

    $archiveItem = Get-Item -Path $DestinationPath -ErrorAction Stop
    $hash = Get-FileHash -Path $DestinationPath -Algorithm SHA256 -ErrorAction Stop

    Write-RenderKitLog -Level Info -Message "Compressed '$resolvedProjectPath' to '$($archiveItem.FullName)' ($([int64]$archiveItem.Length) bytes)."

    return [PSCustomObject]@{
        Path          = $archiveItem.FullName
        SizeBytes     = [int64]$archiveItem.Length
        HashAlgorithm = "SHA256"
        Hash          = $hash.Hash
        SourceFileCount = [int]$files.Count
        ArchivedFileCount = [int]$filesToArchive.Count
        DeduplicatedFileCount = [int]$deduplicatedFileCount
        DeduplicatedBytes = [int64]$deduplicatedBytes
    }
}
