function Remove-EmptyFolders{
    param(
        [string]$path,
        [switch]$DryRun
    )

    Get-ChildItem $path -Recurse -Directory | 
        Sort-Object FullName -Descending |
        Where-Object { $_.GetFileSystemInfos().Count -eq 0} |
        ForEach-Object {
            if ($DryRun){
                Write-Verbose "[DRY] Remove empty Folder $($_.FullName)"
            }
            else {
                Remove-Item $_.FullName -Force
            }
        }
}