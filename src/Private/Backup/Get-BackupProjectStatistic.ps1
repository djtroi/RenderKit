function Get-BackupProjectStatistic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath
    )

    $files = @(
        Get-ChildItem -Path $ProjectPath -Recurse -File -Force -ErrorAction SilentlyContinue
    )
    $directories = @(
        Get-ChildItem -Path $ProjectPath -Recurse -Directory -Force -ErrorAction SilentlyContinue
    )

    $totalBytes = [int64](($files | Measure-Object -Property Length -Sum).Sum)
    if ($totalBytes -lt 0) {
        $totalBytes = [int64]0
    }

    return [PSCustomObject]@{
        FileCount      = [int]$files.Count
        DirectoryCount = [int]$directories.Count
        TotalBytes     = $totalBytes
    }
}
