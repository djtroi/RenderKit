function Test-BackupArchiveContentIntegrity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,
        [Parameter(Mandatory)]
        [string]$ArchivePath,
        [hashtable]$SourceIndex,
        [ValidateSet("SHA256", "SHA1", "MD5")]
        [string]$Algorithm = "SHA256"
    )

    if (-not (Test-Path -Path $ProjectPath -PathType Container)) {
        Write-RenderKitLog -Level Error -Message "Project path '$ProjectPath' does not exist."
        throw "Project path '$ProjectPath' does not exist."
    }
    if (-not (Test-Path -Path $ArchivePath -PathType Leaf)) {
        Write-RenderKitLog -Level Error -Message "Archive path '$ArchivePath' does not exist."
        throw "Archive path '$ArchivePath' does not exist."
    }

    Write-RenderKitLog -Level Debug -Message "Test-BackupArchiveContentIntegrity started: ProjectPath='$ProjectPath', ArchivePath='$ArchivePath', Algorithm='$Algorithm', SourceIndexProvided=$($null -ne $SourceIndex -and $SourceIndex.Count -gt 0)."

    $extractRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("renderkit-archive-verify-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null

    try {
        $extractRootPath = [System.IO.Path]::GetFullPath($extractRoot)
        $extractRootPrefix = $extractRootPath.TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        ) + [System.IO.Path]::DirectorySeparatorChar
        $archive = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
        try {
            foreach ($entry in $archive.Entries) {
                $relativePath = $entry.FullName.Replace(
                    '/',
                    [System.IO.Path]::DirectorySeparatorChar)
                $destinationPath = [System.IO.Path]::GetFullPath(
                    (Join-Path $extractRootPath $relativePath))
                if (-not $destinationPath.StartsWith(
                        $extractRootPrefix,
                        [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw (
                        "Archive entry escapes the verification directory: " +
                        $entry.FullName)
                }

                if ([string]::IsNullOrEmpty($entry.Name)) {
                    New-Item `
                        -ItemType Directory `
                        -Path $destinationPath `
                        -Force |
                        Out-Null
                    continue
                }

                $destinationDirectory = Split-Path `
                    -Path $destinationPath `
                    -Parent
                New-Item `
                    -ItemType Directory `
                    -Path $destinationDirectory `
                    -Force |
                    Out-Null
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile(
                    $entry,
                    $destinationPath,
                    $true)
            }
        }
        finally {
            $archive.Dispose()
        }

        $projectLeafName = Split-Path -Path $ProjectPath -Leaf
        $candidateRoot = Join-Path $extractRoot $projectLeafName
        $archiveProjectRoot = if (Test-Path -Path $candidateRoot -PathType Container) {
            $candidateRoot
        }
        else {
            $topLevelDirectories = @(
                Get-ChildItem -Path $extractRoot -Directory -Force -ErrorAction SilentlyContinue
            )
            $topLevelFiles = @(
                Get-ChildItem -Path $extractRoot -File -Force -ErrorAction SilentlyContinue
            )

            if ($topLevelDirectories.Count -eq 1 -and $topLevelFiles.Count -eq 0) {
                $topLevelDirectories[0].FullName
            }
            else {
                $extractRoot
            }
        }

        $effectiveSourceIndex = $SourceIndex
        if ($null -eq $effectiveSourceIndex -or $effectiveSourceIndex.Count -eq 0) {
            $effectiveSourceIndex = Get-BackupFileHashIndex `
                -RootPath $ProjectPath `
                -BasePath $ProjectPath `
                -Algorithm $Algorithm
        }

        $archiveIndex = Get-BackupFileHashIndex `
            -RootPath $archiveProjectRoot `
            -BasePath $archiveProjectRoot `
            -Algorithm $Algorithm

        # RenderKit logs remain active while the backup is running and are
        # injected into a dedicated archive section after this comparison.
        # Exclude only those mutable internal log files from the content hash
        # comparison; all other project files remain integrity-checked.
        $sourcePaths = @(
            $effectiveSourceIndex.Keys |
                Where-Object { $_ -notmatch '(^|/)\.renderkit/.*\.log$' } |
                Sort-Object
        )
        $archivePaths = @(
            $archiveIndex.Keys |
                Where-Object { $_ -notmatch '(^|/)\.renderkit/.*\.log$' } |
                Sort-Object
        )

        $missingInArchive = @($sourcePaths | Where-Object { -not $archiveIndex.ContainsKey($_) })
        $extraInArchive = @($archivePaths | Where-Object { -not $effectiveSourceIndex.ContainsKey($_) })

        $hashMismatches = New-Object System.Collections.Generic.List[object]
        foreach ($path in $sourcePaths) {
            if (-not $archiveIndex.ContainsKey($path)) {
                continue
            }

            $sourceEntry = $effectiveSourceIndex[$path]
            $archiveEntry = $archiveIndex[$path]

            if ($sourceEntry.Length -ne $archiveEntry.Length -or
                -not $sourceEntry.Hash.Equals($archiveEntry.Hash, [System.StringComparison]::OrdinalIgnoreCase)) {
                $hashMismatches.Add([PSCustomObject]@{
                        RelativePath = $path
                        SourceLength = [int64]$sourceEntry.Length
                        ArchiveLength = [int64]$archiveEntry.Length
                        SourceHash   = [string]$sourceEntry.Hash
                        ArchiveHash  = [string]$archiveEntry.Hash
                    })
            }
        }

        $isMatch = ($missingInArchive.Count -eq 0 -and $extraInArchive.Count -eq 0 -and $hashMismatches.Count -eq 0)
        Write-RenderKitLog -Level Debug -Message (
            "Archive integrity computed: SourceFiles={0}, ArchiveFiles={1}, Missing={2}, Extra={3}, HashMismatches={4}." -f
            $sourcePaths.Count,
            $archivePaths.Count,
            $missingInArchive.Count,
            $extraInArchive.Count,
            $hashMismatches.Count
        )
        return [PSCustomObject]@{
            IsMatch                = $isMatch
            Algorithm              = $Algorithm
            SourceFileCount        = $sourcePaths.Count
            ArchiveFileCount       = $archivePaths.Count
            MissingInArchiveCount  = $missingInArchive.Count
            ExtraInArchiveCount    = $extraInArchive.Count
            HashMismatchCount      = $hashMismatches.Count
            MissingInArchive       = @($missingInArchive)
            ExtraInArchive         = @($extraInArchive)
            HashMismatches         = @($hashMismatches.ToArray())
        }
    }
    finally {
        if (Test-Path -Path $extractRoot -PathType Container) {
            Remove-Item -Path $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
