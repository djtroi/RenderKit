function Resume-BackupProjectJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [string]$Reason = 'User requested backup resume.'
    )

    $job = Get-RenderKitJob -JobId $JobId
    if ($job -and [string]$job.status -in @('Failed', 'RetryScheduled')) {
        Reset-RenderKitJobForRetry -JobId $JobId | Out-Null
    }

    Request-BackupJobControlAction `
        -JobId $JobId `
        -Action Resume `
        -Reason $Reason
}

Register-RenderKitFunction -Name 'Resume-BackupProjectJob'
