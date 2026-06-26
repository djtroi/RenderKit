function Pause-BackupJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('Id')]
        [string]$JobId,
        [string]$Reason = 'User requested backup pause.'
    )

    process {
        Suspend-BackupProjectJob `
            -JobId $JobId `
            -Reason $Reason
    }
}

Register-RenderKitFunction -Name 'Pause-BackupJob'
