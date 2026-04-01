function Remove-ProjectArtifact{
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

    $candidateFiles = @(
        Get-ChildItem -Path $ProjectPath -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $ruleExtensions -contains $_.Extension.ToLowerInvariant() }
    )
    $candidateFolders = @(
        Get-ChildItem -Path $ProjectPath -Recurse -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $ruleFolders -contains $_.Name } |
            Sort-Object -Property FullName -Descending
    )

    $removedFolderPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $removedFolderCount = 0
    $removedFileCount = 0
    $removedFileBytes = [int64]0
    $failedCount = 0

    foreach ($folder in $candidateFolders) {
        if ($DryRun) {
            Write-Verbose "[DRY] Remove folder $($folder.FullName)"
            $removedFolderCount++
            [void]$removedFolderPaths.Add($folder.FullName)
            continue
        }

        try {
            Remove-Item -Path $folder.FullName -Recurse -Force -ErrorAction Stop
            $removedFolderCount++
            [void]$removedFolderPaths.Add($folder.FullName)
        }
        catch {
            $failedCount++
            Write-RenderKitLog -Level Warning -Message "Failed to remove folder '$($folder.FullName)': $($_.Exception.Message)"
        }
    }

    foreach ($file in $candidateFiles) {
        $isInsideRemovedFolder = $false
        foreach ($removedFolderPath in $removedFolderPaths) {
            if ($file.FullName.StartsWith("$removedFolderPath\", [System.StringComparison]::OrdinalIgnoreCase)) {
                $isInsideRemovedFolder = $true
                break
            }
        }

        if ($isInsideRemovedFolder) {
            continue
        }

        if ($DryRun) {
            Write-Verbose "[DRY] Remove file $($file.FullName)"
            $removedFileCount++
            $removedFileBytes += [int64]$file.Length
            continue
        }

        try {
            Remove-Item -Path $file.FullName -Force -ErrorAction Stop
            $removedFileCount++
            $removedFileBytes += [int64]$file.Length
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
