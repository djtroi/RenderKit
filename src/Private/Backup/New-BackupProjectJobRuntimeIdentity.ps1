function New-BackupProjectJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Payload,
        [string]$QueueName = 'backup',
        [int]$Priority = 0,
        [string]$CorrelationId,
        [object]$RequestedBy
    )

    if ([string]::IsNullOrWhiteSpace($QueueName)) {
        $QueueName = 'backup'
    }

    # Background callers may provide Windows-specific environment values that
    # are empty on Unix. Normalize the persisted audit identity at the private
    # job boundary so every caller gets portable user/machine metadata without
    # changing the public backup command contract.
    if (-not $RequestedBy) {
        $RequestedBy = [PSCustomObject]@{}
    }
    if ($RequestedBy.PSObject.Properties.Name -notcontains 'user' -or
        [string]::IsNullOrWhiteSpace([string]$RequestedBy.user)) {
        $RequestedBy |
            Add-Member `
                -NotePropertyName user `
                -NotePropertyValue ([System.Environment]::UserName) `
                -Force
    }
    if ($RequestedBy.PSObject.Properties.Name -notcontains 'machine' -or
        [string]::IsNullOrWhiteSpace([string]$RequestedBy.machine)) {
        $RequestedBy |
            Add-Member `
                -NotePropertyName machine `
                -NotePropertyValue ([System.Environment]::MachineName) `
                -Force
    }

    $job = New-RenderKitJob `
        -JobType 'BackupProject' `
        -Payload $Payload `
        -PayloadSchemaVersion ([string]$Payload.schemaVersion) `
        -QueueName $QueueName `
        -Priority $Priority `
        -CorrelationId $CorrelationId `
        -RequestedBy $RequestedBy

    if ($Payload.PSObject.Properties.Name -contains 'resume' -and $Payload.resume) {
        $resumeStatePath = Get-BackupResumeStatePath -JobId ([string]$job.id)
        $progressStatePath = Get-BackupProgressStatePath -JobId ([string]$job.id)
        $controlStatePath = Get-BackupControlStatePath -JobId ([string]$job.id)
        $Payload.resume.jobId = [string]$job.id
        $Payload.resume.statePath = $resumeStatePath
        $Payload.resume.progressStatePath = $progressStatePath
        if ($Payload.PSObject.Properties.Name -contains 'progress' -and $Payload.progress) {
            $Payload.progress.statePath = $progressStatePath
        }
        if ($Payload.PSObject.Properties.Name -contains 'control' -and $Payload.control) {
            $Payload.control.statePath = $controlStatePath
        }
        if ($Payload.PSObject.Properties.Name -contains 'background' -and $Payload.background) {
            $Payload.background.queueName = $QueueName
            $Payload.background.worker.stateRoot = Get-RenderKitWorkerStateRoot
            $Payload.background.worker.logRoot = Get-RenderKitWorkerLogRoot
        }
        if ($Payload.chunkPlan -and $Payload.chunkPlan.index) {
            $Payload.chunkPlan.index.jobId = [string]$job.id
            $Payload.chunkPlan.index.statePath = Get-BackupChunkIndexPath -JobId ([string]$job.id)
            Save-BackupChunkIndex `
                -JobId ([string]$job.id) `
                -ChunkIndex $Payload.chunkPlan.index |
                Out-Null
        }
        $job.payload = $Payload

        Save-BackupResumeState `
            -JobId ([string]$job.id) `
            -State (New-BackupResumeState -Job $job -Payload $Payload) |
            Out-Null
        Save-BackupControlState `
            -JobId ([string]$job.id) `
            -State (New-BackupControlState -JobId ([string]$job.id) -StatePath $controlStatePath) |
            Out-Null
    }

    return Add-RenderKitJob -Job $job
}
