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
        progress      = [PSCustomObject]@{
            currentPhase          = 'Planned'
            lastCompletedChunkId  = $null
            completedChunkCount   = 0
            failedChunkCount      = 0
            pendingChunkCount     = if ($Payload.chunkPlan -and $Payload.chunkPlan.summary) { [int]$Payload.chunkPlan.summary.pendingChunkCount } else { 0 }
            mergedAssetCount      = 0
            validatedMergedAssetCount = 0
            failedMergeValidationCount = 0
            passThroughFileCount  = if ($Payload.chunkPlan -and $Payload.chunkPlan.summary) { [int]$Payload.chunkPlan.summary.passThroughFileCount } else { 0 }
        }
        mergeValidation = @()
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
