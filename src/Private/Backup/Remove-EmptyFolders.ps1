function Remove-EmptyFolder{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$path,
        [switch]$DryRun
    )

    $candidateCount = 0
    $removedCount = 0
    $failedCount = 0

    $runAgain = $true
    while ($runAgain) {
        $runAgain = $false
        $removedThisPass = 0

        $folders = @(
            Get-ChildItem -Path $path -Recurse -Directory -Force -ErrorAction SilentlyContinue |
                Sort-Object -Property FullName -Descending
        )

        foreach ($folder in $folders) {
            $isEmpty = $false
            try {
                $isEmpty = ($folder.GetFileSystemInfos().Count -eq 0)
            }
            catch {
                continue
            }

            if (-not $isEmpty) {
                continue
            }

            $candidateCount++

            if ($DryRun){
                Write-Verbose "[DRY] Remove empty folder $($folder.FullName)"
                $removedCount++
                continue
            }

            try {
                Remove-Item -Path $folder.FullName -Force -ErrorAction Stop
                $removedCount++
                $removedThisPass++
            }
            catch {
                $failedCount++
                Write-RenderKitLog -Level Warning -Message "Failed to remove empty folder '$($folder.FullName)': $($_.Exception.Message)"
            }
        }

        if (-not $DryRun -and $removedThisPass -gt 0) {
            $runAgain = $true
        }
    }

    return [PSCustomObject]@{
        CandidateCount = [int]$candidateCount
        RemovedCount   = [int]$removedCount
        FailedCount    = [int]$failedCount
        Mode           = if ($DryRun) { "DryRun" } else { "Execute" }
    }
}
