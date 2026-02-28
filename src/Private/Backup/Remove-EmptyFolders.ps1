function Remove-EmptyFolders{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$path,
        [switch]$DryRun
    )

    $candidateFolders = @(
        Get-ChildItem -Path $path -Recurse -Directory -Force -ErrorAction SilentlyContinue |
            Sort-Object -Property FullName -Descending |
            Where-Object { $_.GetFileSystemInfos().Count -eq 0 }
    )

    $removedCount = 0
    $failedCount = 0

    foreach ($folder in $candidateFolders) {
        if ($DryRun){
            Write-Verbose "[DRY] Remove empty folder $($folder.FullName)"
            $removedCount++
            continue
        }

        try {
            Remove-Item -Path $folder.FullName -Force -ErrorAction Stop
            $removedCount++
        }
        catch {
            $failedCount++
            Write-RenderKitLog -Level Warning -Message "Failed to remove empty folder '$($folder.FullName)': $($_.Exception.Message)"
        }
    }

    return [PSCustomObject]@{
        CandidateCount = [int]$candidateFolders.Count
        RemovedCount   = [int]$removedCount
        FailedCount    = [int]$failedCount
        Mode           = if ($DryRun) { "DryRun" } else { "Execute" }
    }
}
