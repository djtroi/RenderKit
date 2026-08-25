function Remove-EmptyFolder{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        "PSUseShouldProcessForStateChangingFunctions",
        "",
        Justification = "internal function. The public function already has a DryRun feature"
    )]
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

        $catalog = Get-RenderKitBackupCleanupCatalog -ProjectPath $path
        $safeProjectPath = [string]$catalog.RootPath
        $folders = @(
            @($catalog.Directories) |
                Sort-Object { $_.FullName.Length } -Descending
        )

        foreach ($folder in $folders) {
            if (-not (Test-RenderKitBackupCleanupTarget `
                    -ProjectPath $safeProjectPath `
                    -TargetPath $folder.FullName)) {
                $failedCount++
                continue
            }

            $isEmpty = $false
            try {
                $currentFolder = Get-Item `
                    -LiteralPath $folder.FullName `
                    -Force `
                    -ErrorAction Stop
                if (Test-RenderKitBackupCleanupReparsePoint -Item $currentFolder) {
                    continue
                }
                $isEmpty = ($currentFolder.GetFileSystemInfos().Count -eq 0)
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
                [System.IO.Directory]::Delete($folder.FullName, $false)
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
