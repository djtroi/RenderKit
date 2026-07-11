function Stop-BackupProjectJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [string]$Reason = 'User requested backup cancellation.'
    )

    Request-BackupJobControlAction `
        -JobId $JobId `
        -Action Cancel `
        -Reason $Reason
}

Register-RenderKitFunction -Name 'Stop-BackupProjectJob'
