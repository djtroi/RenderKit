function Clear-RenderKitOldLogs{
    if (!($script:RenderKitLogContext)) { return }

    $limit = (Get-Date).AddDays(-$script:RenderKitLogContext.RetentionDays)

    Get-ChildItem -Path $script:RenderKitLogContext.LogsPath -Filter "renderkit-*.log" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt $limit } | 
    ForEach-Object {
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
    } 
}