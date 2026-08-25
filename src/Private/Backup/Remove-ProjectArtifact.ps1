function Remove-ProjectArtifact{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        "PSUseShouldProcessForStateChangingFunctions",
        "",
        Justification = "internal function. The public function already has a DryRun feature"
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,
        [Parameter(Mandatory)]
        [hashtable]$rules,
        [switch]$DryRun
    )

    $ruleExtensions = @(
        @($rules.Extensions) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object {
                $ext = $_.Trim().ToLowerInvariant()
                if (-not $ext.StartsWith(".")) { $ext = ".$ext" }
                $ext
            }
    )
    $ruleFolders = @(
        @($rules.Folders) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim() }
    )

    $catalog = Get-RenderKitBackupCleanupCatalog -ProjectPath $ProjectPath
    $safeProjectPath = [string]$catalog.RootPath
    $candidateFiles = @(
        @($catalog.Files) |
            Where-Object { $ruleExtensions -contains $_.Extension.ToLowerInvariant() }
    )
    $candidateFolders = @(
        @($catalog.Directories) |
            Where-Object { $ruleFolders -contains $_.Name } |
            Sort-Object { $_.FullName.Length } -Descending
    )

    $pathComparer = if ($env:OS -eq 'Windows_NT') {
        [System.StringComparer]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparer]::Ordinal
    }
    $removedFolderPaths = New-Object 'System.Collections.Generic.HashSet[string]' $pathComparer
    $removedFolderCount = 0
    $removedFileCount = 0
    $removedFileBytes = [int64]0
    $failedCount = 0

    foreach ($folder in $candidateFolders) {
        $safeFolder = Test-RenderKitBackupCleanupTarget `
            -ProjectPath $safeProjectPath `
            -TargetPath $folder.FullName
        if (-not $safeFolder) {
            $failedCount++
            Write-RenderKitLog -Level Warning -Message "Skipped unsafe cleanup folder '$($folder.FullName)'."
            continue
        }

        if ($DryRun) {
            Write-Verbose "[DRY] Remove folder $($folder.FullName)"
            $removedFolderCount++
            [void]$removedFolderPaths.Add($folder.FullName)
            continue
        }

        try {
            Remove-RenderKitBackupCleanupDirectoryTree `
                -ProjectPath $safeProjectPath `
                -DirectoryPath $folder.FullName
            $removedFolderCount++
            [void]$removedFolderPaths.Add($folder.FullName)
        }
        catch {
            $failedCount++
            Write-RenderKitLog -Level Warning -Message "Failed to remove folder '$($folder.FullName)': $($_.Exception.Message)"
        }
    }

    $comparison = if ($env:OS -eq 'Windows_NT') {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    foreach ($file in $candidateFiles) {
        $isInsideRemovedFolder = $false
        foreach ($removedFolderPath in $removedFolderPaths) {
            $folderPrefix = $removedFolderPath.TrimEnd(
                [char[]]@(
                    [System.IO.Path]::DirectorySeparatorChar,
                    [System.IO.Path]::AltDirectorySeparatorChar
                )
            ) + [System.IO.Path]::DirectorySeparatorChar
            if ($file.FullName.StartsWith($folderPrefix, $comparison)) {
                $isInsideRemovedFolder = $true
                break
            }
        }

        if ($isInsideRemovedFolder) {
            continue
        }

        if (-not (Test-RenderKitBackupCleanupTarget `
                -ProjectPath $safeProjectPath `
                -TargetPath $file.FullName)) {
            $failedCount++
            Write-RenderKitLog -Level Warning -Message "Skipped unsafe cleanup file '$($file.FullName)'."
            continue
        }

        if ($DryRun) {
            Write-Verbose "[DRY] Remove file $($file.FullName)"
            $removedFileCount++
            $removedFileBytes += [int64]$file.Length
            continue
        }

        try {
            $fileLength = [int64]$file.Length
            [System.IO.File]::Delete($file.FullName)
            $removedFileCount++
            $removedFileBytes += $fileLength
        }
        catch {
            $failedCount++
            Write-RenderKitLog -Level Warning -Message "Failed to remove file '$($file.FullName)': $($_.Exception.Message)"
        }
    }

    return [PSCustomObject]@{
        CandidateFileCount   = [int]$candidateFiles.Count
        CandidateFolderCount = [int]$candidateFolders.Count
        RemovedFileCount     = [int]$removedFileCount
        RemovedFolderCount   = [int]$removedFolderCount
        RemovedFileBytes     = [int64]$removedFileBytes
        FailedCount          = [int]$failedCount
        Mode                 = if ($DryRun) { "DryRun" } else { "Execute" }
    }
}
