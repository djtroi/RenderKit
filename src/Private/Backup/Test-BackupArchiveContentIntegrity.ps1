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
        throw "Project path '$ProjectPath' does not exist."
    }
    if (-not (Test-Path -Path $ArchivePath -PathType Leaf)) {
        throw "Archive path '$ArchivePath' does not exist."
    }

    $extractRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("renderkit-archive-verify-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null

    try {
        Expand-Archive -Path $ArchivePath -DestinationPath $extractRoot -Force

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

        $sourcePaths = @($effectiveSourceIndex.Keys | Sort-Object)
        $archivePaths = @($archiveIndex.Keys | Sort-Object)

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
