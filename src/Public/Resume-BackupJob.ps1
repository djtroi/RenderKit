function Resume-BackupJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('Id')]
        [string]$JobId,
        [string]$Reason = 'User requested backup resume.'
    )

    process {
        Resume-BackupProjectJob `
            -JobId $JobId `
            -Reason $Reason
    }
}

Register-RenderKitFunction -Name 'Resume-BackupJob'
