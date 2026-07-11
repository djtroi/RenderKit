function Get-BackupJobValue {
    [CmdletBinding()]
    param(
        [object]$InputObject,
        [Parameter(Mandatory)]
        [string]$Name,
        [object]$DefaultValue = $null
    )

    if ($null -eq $InputObject) {
        return $DefaultValue
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return $InputObject[$Name]
        }

        return $DefaultValue
    }
    if (Test-RenderKitObjectProperty -InputObject $InputObject -Name $Name) {
        return $InputObject.$Name
    }

    return $DefaultValue
}

function ConvertTo-BackupJobNullableDouble {
    [CmdletBinding()]
    param(
        [object]$Value
    )

    if ($null -eq $Value) {
        return $null
    }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    try {
        return [double]$Value
    }
    catch {
        return $null
    }
}

function ConvertTo-BackupJobEtaText {
    [CmdletBinding()]
    param(
        [object]$Seconds
    )

    $value = ConvertTo-BackupJobNullableDouble -Value $Seconds
    if ($null -eq $value) {
        return $null
    }

    $duration = [TimeSpan]::FromSeconds([Math]::Max(0, [double]$value))
    if ($duration.TotalHours -ge 1) {
        return ('{0:00}:{1:00}:{2:00}' -f [int]$duration.TotalHours, $duration.Minutes, $duration.Seconds)
    }

    return ('{0:00}:{1:00}' -f [int]$duration.TotalMinutes, $duration.Seconds)
}

function Test-BackupJobTerminalStatus {
    [CmdletBinding()]
    param(
        [string]$Status
    )

    return [bool]($Status -in @('Succeeded', 'Failed', 'Cancelled'))
}

function Read-BackupJobControlSnapshot {
    [CmdletBinding()]
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or
        -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return [PSCustomObject]@{
            state = 'Unreadable'
            error = $_.Exception.Message
        }
    }
}

function ConvertTo-BackupJobCliSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Job,
        [switch]$IncludeLogs,
        [ValidateRange(1, 1000)]
        [int]$Tail = 50
    )

    $status = New-RenderKitJobStatusSnapshot `
        -Job $Job `
        -IncludeLogs:$IncludeLogs `
        -Tail $Tail
    $payload = $Job.payload
    $project = Get-BackupJobValue -InputObject $payload -Name 'project'
    $archive = Get-BackupJobValue -InputObject $payload -Name 'archive'
    $progressSnapshot = $status.progressSnapshot
    $progress = $status.progress
    $stage = Get-BackupJobValue -InputObject $progressSnapshot -Name 'stage'
    $overall = Get-BackupJobValue -InputObject $progressSnapshot -Name 'overall'
    $current = Get-BackupJobValue -InputObject $progressSnapshot -Name 'current'
    $paths = $status.paths
    $control = Read-BackupJobControlSnapshot `
        -Path ([string](Get-BackupJobValue -InputObject $paths -Name 'controlStatePath'))

    $percent = ConvertTo-BackupJobNullableDouble `
        -Value (Get-BackupJobValue -InputObject $overall -Name 'percent')
    if ($null -eq $percent) {
        $percent = ConvertTo-BackupJobNullableDouble `
            -Value (Get-BackupJobValue -InputObject $progress -Name 'percent')
    }

    $etaSeconds = Get-BackupJobValue -InputObject $overall -Name 'etaSeconds'
    if ($null -eq $etaSeconds) {
        $etaSeconds = Get-BackupJobValue -InputObject $current -Name 'etaSeconds'
    }
    $speedText = [string](Get-BackupJobValue -InputObject $overall -Name 'speedText')
    if ([string]::IsNullOrWhiteSpace($speedText)) {
        $speedText = [string](Get-BackupJobValue -InputObject $current -Name 'speedText')
    }

    $stageName = [string](Get-BackupJobValue -InputObject $stage -Name 'name')
    if ([string]::IsNullOrWhiteSpace($stageName)) {
        $stageName = [string](Get-BackupJobValue -InputObject $progress -Name 'phase')
    }
    $stageDisplayName = [string](Get-BackupJobValue -InputObject $stage -Name 'displayName')
    if ([string]::IsNullOrWhiteSpace($stageDisplayName)) {
        $stageDisplayName = $stageName
    }
    $message = [string](Get-BackupJobValue -InputObject $stage -Name 'message')
    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = [string](Get-BackupJobValue -InputObject $progress -Name 'message')
    }

    $snapshot = [PSCustomObject]@{
        JobId             = [string]$status.id
        JobType           = [string]$status.jobType
        Status            = [string]$status.status
        QueueName         = [string]$status.queueName
        Priority          = [int]$status.priority
        Attempts          = [int]$status.attempts
        MaxAttempts       = [int]$status.maxAttempts
        ProjectName       = [string](Get-BackupJobValue -InputObject $project -Name 'name')
        ProjectId         = [string](Get-BackupJobValue -InputObject $project -Name 'id')
        RootPath          = [string](Get-BackupJobValue -InputObject $project -Name 'rootPath')
        ArchivePath       = [string](Get-BackupJobValue -InputObject $archive -Name 'path')
        ArchiveFormat     = [string](Get-BackupJobValue -InputObject $archive -Name 'format')
        ProgressPercent   = $percent
        StageName         = $stageName
        StageDisplayName  = $stageDisplayName
        Message           = $message
        Current           = Get-BackupJobValue -InputObject $overall -Name 'current'
        Total             = Get-BackupJobValue -InputObject $overall -Name 'total'
        EtaSeconds        = $etaSeconds
        Eta               = ConvertTo-BackupJobEtaText -Seconds $etaSeconds
        Speed             = if ([string]::IsNullOrWhiteSpace($speedText)) { $null } else { $speedText }
        CurrentChunkId    = [string](Get-BackupJobValue -InputObject $current -Name 'chunkId')
        CurrentAssetId    = [string](Get-BackupJobValue -InputObject $current -Name 'assetId')
        CurrentRelativePath = [string](Get-BackupJobValue -InputObject $current -Name 'relativePath')
        ControlState      = [string](Get-BackupJobValue -InputObject $control -Name 'state')
        RequestedAction   = [string](Get-BackupJobValue -InputObject $control -Name 'requestedAction')
        ControlReason     = [string](Get-BackupJobValue -InputObject $control -Name 'reason')
        WorkerId          = [string](Get-BackupJobValue -InputObject $status.worker -Name 'id')
        LeaseExpired      = [bool](Get-BackupJobValue -InputObject $status.worker -Name 'leaseExpired' -DefaultValue $false)
        CreatedAtUtc      = [string]$status.createdAtUtc
        StartedAtUtc      = [string]$status.startedAtUtc
        UpdatedAtUtc      = [string]$status.updatedAtUtc
        CompletedAtUtc    = [string]$status.completedAtUtc
        LastError         = $status.lastError
        Result            = $status.result
        Paths             = $paths
        Logs              = @($status.logs)
    }
    $snapshot.PSObject.TypeNames.Insert(0, 'RenderKit.BackupJobStatus')

    return $snapshot
}

function Write-BackupJobProgressBar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Snapshot,
        [int]$Id = 1
    )

    $percent = ConvertTo-BackupJobNullableDouble -Value $Snapshot.ProgressPercent
    if ($null -eq $percent) {
        $percent = 0
    }
    $percent = [Math]::Max(0, [Math]::Min(100, [int][Math]::Round([double]$percent)))
    $activity = "Backup job $($Snapshot.JobId)"
    $statusParts = @(
        [string]$Snapshot.Status,
        [string]$Snapshot.StageDisplayName
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if (-not [string]::IsNullOrWhiteSpace([string]$Snapshot.Eta)) {
        $statusParts += "ETA $($Snapshot.Eta)"
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Snapshot.Speed)) {
        $statusParts += [string]$Snapshot.Speed
    }

    $currentOperation = [string]$Snapshot.Message
    if (-not [string]::IsNullOrWhiteSpace([string]$Snapshot.CurrentRelativePath)) {
        $currentOperation = [string]$Snapshot.CurrentRelativePath
    }

    Write-Progress `
        -Id $Id `
        -Activity $activity `
        -Status ($statusParts -join ' | ') `
        -PercentComplete $percent `
        -CurrentOperation $currentOperation

    if (Test-BackupJobTerminalStatus -Status ([string]$Snapshot.Status)) {
        Write-Progress -Id $Id -Activity $activity -Completed
    }
}

function Get-BackupJobSnapshotList {
    [CmdletBinding()]
    param(
        [string]$JobId,
        [ValidateSet('Queued', 'Running', 'RetryScheduled', 'Succeeded', 'Failed', 'Cancelled')]
        [string]$Status,
        [string]$QueueName = 'backup',
        [switch]$IncludeLogs,
        [ValidateRange(1, 1000)]
        [int]$Tail = 50
    )

    $jobs = if (-not [string]::IsNullOrWhiteSpace($JobId)) {
        $job = Get-RenderKitJob -JobId $JobId
        if (-not $job) {
            throw "Backup job '$JobId' was not found."
        }
        if ([string]$job.jobType -ne 'BackupProject') {
            throw "RenderKit job '$JobId' is '$($job.jobType)', not 'BackupProject'."
        }
        @($job)
    }
    else {
        $listParameters = @{
            JobType   = 'BackupProject'
            QueueName = $QueueName
        }
        if (-not [string]::IsNullOrWhiteSpace($Status)) {
            $listParameters.Status = $Status
        }

        @(Get-RenderKitJobList @listParameters)
    }

    return @($jobs | ForEach-Object {
            ConvertTo-BackupJobCliSnapshot `
                -Job $_ `
                -IncludeLogs:$IncludeLogs `
                -Tail $Tail
        })
}

function Get-BackupJob {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('Id')]
        [string]$JobId,
        [ValidateSet('Queued', 'Running', 'RetryScheduled', 'Succeeded', 'Failed', 'Cancelled')]
        [string]$Status,
        [string]$QueueName = 'backup',
        [switch]$IncludeLogs,
        [ValidateRange(1, 1000)]
        [int]$Tail = 50,
        [switch]$Watch,
        [ValidateRange(1, 3600)]
        [int]$PollIntervalSeconds = 2,
        [switch]$NoProgressBar
    )

    if (-not $Watch) {
        $snapshotParameters = @{
            JobId       = $JobId
            QueueName   = $QueueName
            IncludeLogs = [bool]$IncludeLogs
            Tail        = $Tail
        }
        if (-not [string]::IsNullOrWhiteSpace($Status)) {
            $snapshotParameters.Status = $Status
        }

        return Get-BackupJobSnapshotList @snapshotParameters
    }

    $lastSnapshots = @()
    do {
        $snapshotParameters = @{
            JobId       = $JobId
            QueueName   = $QueueName
            IncludeLogs = [bool]$IncludeLogs
            Tail        = $Tail
        }
        if (-not [string]::IsNullOrWhiteSpace($Status)) {
            $snapshotParameters.Status = $Status
        }

        $lastSnapshots = @(Get-BackupJobSnapshotList @snapshotParameters)

        if (-not $NoProgressBar) {
            $progressId = 1
            foreach ($snapshot in $lastSnapshots) {
                Write-BackupJobProgressBar -Snapshot $snapshot -Id $progressId
                $progressId++
            }
        }

        $activeSnapshots = @($lastSnapshots | Where-Object {
                -not (Test-BackupJobTerminalStatus -Status ([string]$_.Status))
            })
        if ($activeSnapshots.Count -eq 0) {
            return $lastSnapshots
        }

        Start-Sleep -Seconds $PollIntervalSeconds
    } while ($true)
}

Register-RenderKitFunction -Name 'Get-BackupJob'
