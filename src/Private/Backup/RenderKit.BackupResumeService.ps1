function Get-BackupJobStateRoot {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [string]$JobId
    )

    if ([string]::IsNullOrWhiteSpace($JobId)) {
        throw 'Backup job id must not be empty.'
    }

    $root = Get-RenderKitStorageRoot -Kind State -Ensure
    return New-RenderKitStorageDirectory -Path (
        Join-Path -Path (Join-Path -Path $root -ChildPath 'BackupJobs') -ChildPath $JobId
    )
}

function Get-BackupResumeStatePath {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [string]$JobId
    )

    return Join-Path -Path (Get-BackupJobStateRoot -JobId $JobId) -ChildPath 'resume.json'
}

function Get-BackupChunkIndexPath {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [string]$JobId
    )

    return Join-Path -Path (Get-BackupJobStateRoot -JobId $JobId) -ChildPath 'chunk-index.json'
}

function Get-BackupProgressStatePath {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [string]$JobId
    )

    return Join-Path -Path (Get-BackupJobStateRoot -JobId $JobId) -ChildPath 'progress.json'
}

function Get-BackupControlStatePath {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [string]$JobId
    )

    return Join-Path -Path (Get-BackupJobStateRoot -JobId $JobId) -ChildPath 'control.json'
}

function New-BackupControlState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [string]$StatePath
    )

    if ([string]::IsNullOrWhiteSpace($StatePath)) {
        $StatePath = Get-BackupControlStatePath -JobId $JobId
    }

    return [PSCustomObject]@{
        schemaVersion = '1.0'
        jobId         = $JobId
        statePath     = $StatePath
        state         = 'Running'
        requestedAction = 'None'
        reason       = $null
        requestedAtUtc = $null
        requestedBy  = $null
        updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        process      = [PSCustomObject]@{
            pauseMode = 'ProcessSuspendWhenSupported'
            orderlyStop = 'StopActiveProcessThenKeepCompletedChunks'
            resumeMode = 'SkipCompletedChunksFromChunkIndex'
        }
        retry        = [PSCustomObject]@{
            maxAttemptsPerChunk = 3
            retryDelaySeconds   = 1
        }
    }
}

function Read-BackupControlState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId
    )

    $path = Get-BackupControlStatePath -JobId $JobId
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return New-BackupControlState -JobId $JobId -StatePath $path
    }

    try {
        return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return New-BackupControlState -JobId $JobId -StatePath $path
    }
}

function Save-BackupControlState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [Parameter(Mandatory)]
        [object]$State
    )

    $path = Get-BackupControlStatePath -JobId $JobId
    $State | Add-Member -NotePropertyName statePath -NotePropertyValue $path -Force
    $State | Add-Member -NotePropertyName updatedAtUtc -NotePropertyValue ((Get-Date).ToUniversalTime().ToString('o')) -Force
    Write-RenderKitJsonFileAtomic `
        -Value $State `
        -Path $path `
        -Depth 50 |
        Out-Null

    return $path
}

function Request-BackupJobControlAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [Parameter(Mandatory)]
        [ValidateSet('Pause', 'Resume', 'Cancel', 'None')]
        [string]$Action,
        [string]$Reason,
        [object]$RequestedBy
    )

    $job = Get-RenderKitJob -JobId $JobId
    if (-not $job) {
        throw "RenderKit job '$JobId' was not found."
    }
    if ($Action -in @('Pause', 'Resume') -and [string]$job.status -in @('Succeeded', 'Cancelled')) {
        throw "RenderKit job '$JobId' cannot be controlled from '$($job.status)'."
    }

    $state = Read-BackupControlState -JobId $JobId
    $now = (Get-Date).ToUniversalTime().ToString('o')
    $state.requestedAction = $Action
    $state.reason = $Reason
    $state.requestedAtUtc = $now
    $state.requestedBy = $RequestedBy
    switch ($Action) {
        'Pause' { $state.state = 'PauseRequested' }
        'Resume' { $state.state = 'ResumeRequested' }
        'Cancel' { $state.state = 'CancelRequested' }
        default { $state.state = 'Running' }
    }

    Save-BackupControlState -JobId $JobId -State $state | Out-Null
    if ($Action -eq 'Cancel') {
        Request-RenderKitJobCancellation `
            -JobId $JobId `
            -Reason $Reason `
            -RequestedBy $RequestedBy |
            Out-Null
    }

    return Read-BackupControlState -JobId $JobId
}

function New-BackupResumeState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Job,
        [Parameter(Mandatory)]
        [object]$Payload
    )

    return [PSCustomObject]@{
        schemaVersion = '1.0'
        jobId         = [string]$Job.id
        jobType       = [string]$Job.jobType
        status        = [string]$Job.status
        createdAtUtc  = (Get-Date).ToUniversalTime().ToString('o')
        updatedAtUtc  = (Get-Date).ToUniversalTime().ToString('o')
        project       = $Payload.project
        archive       = $Payload.archive
        mediaAnalysis = $Payload.mediaAnalysis
        chunkPlan     = $Payload.chunkPlan
        chunkIndex    = if ($Payload.chunkPlan -and $Payload.chunkPlan.index) { $Payload.chunkPlan.index } else { $null }
        control       = if ($Payload.control) { $Payload.control } else { $null }
        progress      = [PSCustomObject]@{
            schemaVersion         = '1.0'
            statePath             = if ($Payload.resume -and $Payload.resume.progressStatePath) { [string]$Payload.resume.progressStatePath } else { $null }
            currentPhase          = 'Planned'
            currentStageName      = 'Planned'
            currentStageDisplayName = 'Planned'
            currentCommandId      = $null
            currentChunkId        = $null
            currentAssetId        = $null
            currentRelativePath   = $null
            currentStagePercent   = 0.0
            overallPercent        = 0.0
            etaSeconds            = $null
            speed                 = $null
            speedText             = $null
            lastCompletedChunkId  = $null
            completedChunkCount   = 0
            failedChunkCount      = 0
            pendingChunkCount     = if ($Payload.chunkPlan -and $Payload.chunkPlan.summary) { [int]$Payload.chunkPlan.summary.pendingChunkCount } else { 0 }
            mergedAssetCount      = 0
            validatedMergedAssetCount = 0
            failedMergeValidationCount = 0
            qualityValidationCount = 0
            failedQualityValidationCount = 0
            schedulerUsedParallel = $false
            passThroughFileCount  = if ($Payload.chunkPlan -and $Payload.chunkPlan.summary) { [int]$Payload.chunkPlan.summary.passThroughFileCount } else { 0 }
        }
        mergeValidation = @()
        qualityValidation = $null
        schedulerResult = $null
        progressSnapshot = $null
    }
}

function Save-BackupChunkIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [Parameter(Mandatory)]
        [object]$ChunkIndex
    )

    $path = Get-BackupChunkIndexPath -JobId $JobId
    Write-RenderKitJsonFileAtomic `
        -Value $ChunkIndex `
        -Path $path `
        -Depth 50 |
        Out-Null

    return $path
}

function Save-BackupResumeState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [Parameter(Mandatory)]
        [object]$State
    )

    $path = Get-BackupResumeStatePath -JobId $JobId
    Write-RenderKitJsonFileAtomic `
        -Value $State `
        -Path $path `
        -Depth 50 |
        Out-Null

    return $path
}

function Save-BackupProgressState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [Parameter(Mandatory)]
        [object]$State
    )

    $path = Get-BackupProgressStatePath -JobId $JobId
    Write-RenderKitJsonFileAtomic `
        -Value $State `
        -Path $path `
        -Depth 50 |
        Out-Null

    return $path
}

function Update-BackupChunkIndexEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [Parameter(Mandatory)]
        [string]$ChunkId,
        [ValidateSet('Pending', 'Running', 'Completed', 'Failed', 'RetryScheduled', 'Skipped')]
        [string]$State,
        [string]$OutputPath,
        [Nullable[int]]$Attempts,
        [string]$ErrorMessage
    )

    $path = Get-BackupChunkIndexPath -JobId $JobId
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }

    $index = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    foreach ($entry in @($index.entries)) {
        if ([string]$entry.chunkId -ne $ChunkId) {
            continue
        }

        $entry.state = $State
        if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
            $entry.outputPath = $OutputPath
        }
        if ($null -ne $Attempts) {
            $entry.attempts = [int]$Attempts
        }
        if ($State -eq 'Completed') {
            $entry.completedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            $entry.error = $null
        }
        elseif (-not [string]::IsNullOrWhiteSpace($ErrorMessage)) {
            $entry.error = [PSCustomObject]@{
                message       = $ErrorMessage
                occurredAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            }
        }
        break
    }

    Save-BackupChunkIndex -JobId $JobId -ChunkIndex $index | Out-Null
    return $index
}

function Get-BackupCompletedChunkIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId
    )

    $path = Get-BackupChunkIndexPath -JobId $JobId
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return @{}
    }

    $index = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $completed = @{}
    foreach ($entry in @($index.entries)) {
        if ([string]$entry.state -eq 'Completed' -and
            -not [string]::IsNullOrWhiteSpace([string]$entry.outputPath) -and
            (Test-Path -LiteralPath ([string]$entry.outputPath) -PathType Leaf)) {
            $completed[[string]$entry.chunkId] = $entry
        }
    }

    return $completed
}
