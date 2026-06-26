function Stop-BackupJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('Id')]
        [string]$JobId,
        [string]$Reason = 'User requested backup cancellation.'
    )

    process {
        Stop-BackupProjectJob `
            -JobId $JobId `
            -Reason $Reason
    }
}

Register-RenderKitFunction -Name 'Stop-BackupJob'
