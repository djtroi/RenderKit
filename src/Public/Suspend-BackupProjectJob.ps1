function Suspend-BackupProjectJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [string]$Reason = 'User requested backup pause.'
    )

    Request-BackupJobControlAction `
        -JobId $JobId `
        -Action Pause `
        -Reason $Reason
}

Register-RenderKitFunction -Name 'Suspend-BackupProjectJob'
