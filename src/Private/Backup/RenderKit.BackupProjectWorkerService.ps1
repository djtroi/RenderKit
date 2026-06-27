function Invoke-BackupProjectJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Job
    )

    $payload = $Job.payload
    if (-not $payload) {
        throw "BackupProject job '$($Job.id)' does not contain a payload."
    }

    Update-BackupJobProgressSnapshot `
        -Job $Job `
        -StageName 'PlanningEncoding' `
        -StageDisplayName 'Planning encoding' `
        -Message 'Planning backup encoding stage.' `
        -Current 0 `
        -Total 1 `
        -Percent 0 |
        Out-Null

    Invoke-BackupFailureAbortSimulationIfRequested `
        -Job $Job `
        -Payload $payload `
        -StageName 'PlanningEncoding' |
        Out-Null

    $encodingPlan = New-BackupEncodingPlan -Job $Job -Payload $payload
    $resumeState = New-BackupResumeState -Job $Job -Payload $payload
    $resumeState | Add-Member -NotePropertyName encodingPlan -NotePropertyValue $encodingPlan -Force
    $resumeState.progress.currentPhase = 'EncodingPlanned'
    Save-BackupResumeState `
        -JobId ([string]$Job.id) `
        -State $resumeState |
        Out-Null

    $encodingResult = if ([string]$payload.archive.mode -in @('TranscodeAndArchive', 'ProxyOnly')) {
        Invoke-BackupEncodingPlan -Job $Job -Plan $encodingPlan
    }
    else {
        Update-BackupJobProgressSnapshot `
            -Job $Job `
            -StageName 'EncodingSkipped' `
            -StageDisplayName 'Encoding skipped' `
            -Message "Encoding skipped for archive mode '$($payload.archive.mode)'." `
            -Current 0 `
            -Total 0 `
            -Percent 100 |
            Out-Null
        [PSCustomObject]@{
            encodedChunkCount          = 0
            mergedAssetCount           = 0
            mergeValidationCount       = 0
            mergeValidationFailedCount = 0
            mergeValidations           = @()
            qualityValidationCount     = 0
            qualityValidationFailedCount = 0
            qualityValidations         = @()
            qualityValidation          = [PSCustomObject]@{
                state  = 'Skipped'
                passed = $true
            }
            proxyAssetCount            = 0
            previewAssetCount          = 0
            scheduler                  = [PSCustomObject]@{
                usedParallel = $false
                skipped      = $true
            }
            skipped                    = $true
        }
    }

    if ([string]$payload.archive.mode -eq 'ProxyOnly') {
        $encodingResult.proxyAssetCount = [int]$encodingResult.mergedAssetCount
    }

    $resumeState.progress.currentPhase = 'EncodingComplete'
    $resumeState.progress.completedChunkCount = [int]$encodingResult.encodedChunkCount
    $resumeState.progress.mergedAssetCount = [int]$encodingResult.mergedAssetCount
    $resumeState.progress.validatedMergedAssetCount = [int]$encodingResult.mergeValidationCount
    $resumeState.progress.failedMergeValidationCount = [int]$encodingResult.mergeValidationFailedCount
    $resumeState.progress.qualityValidationCount = [int]$encodingResult.qualityValidationCount
    $resumeState.progress.failedQualityValidationCount = [int]$encodingResult.qualityValidationFailedCount
    $resumeState.progress.schedulerUsedParallel = [bool]$encodingResult.scheduler.usedParallel
    $progressStatePath = Get-BackupProgressStatePath -JobId ([string]$Job.id)
    $resumeState.progress.statePath = $progressStatePath
    if (Test-Path -LiteralPath $progressStatePath -PathType Leaf) {
        $resumeState.progressSnapshot = Get-Content `
            -LiteralPath $progressStatePath `
            -Raw |
            ConvertFrom-Json
        $resumeState.progress.currentStageName = [string]$resumeState.progressSnapshot.stage.name
        $resumeState.progress.currentStageDisplayName = [string]$resumeState.progressSnapshot.stage.displayName
        $resumeState.progress.overallPercent = $resumeState.progressSnapshot.overall.percent
        $resumeState.progress.etaSeconds = $resumeState.progressSnapshot.overall.etaSeconds
        $resumeState.progress.speedText = $resumeState.progressSnapshot.overall.speedText
        $resumeState.progress.currentCommandId = $resumeState.progressSnapshot.current.commandId
        $resumeState.progress.currentChunkId = $resumeState.progressSnapshot.current.chunkId
        $resumeState.progress.currentAssetId = $resumeState.progressSnapshot.current.assetId
        $resumeState.progress.currentRelativePath = $resumeState.progressSnapshot.current.relativePath
        $resumeState.progress.currentStagePercent = $resumeState.progressSnapshot.current.percent
    }
    $resumeState.progress.pendingChunkCount = [Math]::Max(
        0,
        [int]$resumeState.progress.pendingChunkCount - [int]$encodingResult.encodedChunkCount
    )
    $resumeState | Add-Member `
        -NotePropertyName mergeValidation `
        -NotePropertyValue @($encodingResult.mergeValidations) `
        -Force
    $resumeState | Add-Member `
        -NotePropertyName qualityValidation `
        -NotePropertyValue $encodingResult.qualityValidation `
        -Force
    $resumeState | Add-Member `
        -NotePropertyName schedulerResult `
        -NotePropertyValue $encodingResult.scheduler `
        -Force
    $resumeState.updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    Save-BackupResumeState `
        -JobId ([string]$Job.id) `
        -State $resumeState |
        Out-Null

    return [PSCustomObject]@{
        phase             = 'Encoding'
        skipped           = [bool]$encodingResult.skipped
        encodedChunkCount = [int]$encodingResult.encodedChunkCount
        mergedAssetCount  = [int]$encodingResult.mergedAssetCount
        mergeValidationCount = [int]$encodingResult.mergeValidationCount
        mergeValidationFailedCount = [int]$encodingResult.mergeValidationFailedCount
        mergeValidations = @($encodingResult.mergeValidations)
        qualityValidationCount = [int]$encodingResult.qualityValidationCount
        qualityValidationFailedCount = [int]$encodingResult.qualityValidationFailedCount
        qualityValidations = @($encodingResult.qualityValidations)
        qualityValidation = $encodingResult.qualityValidation
        proxyAssetCount   = [int]$encodingResult.proxyAssetCount
        previewAssetCount = [int]$encodingResult.previewAssetCount
        scheduler        = $encodingResult.scheduler
        encodingPlan      = [PSCustomObject]@{
            profile      = $encodingPlan.profile.name
            commandCount = $encodingPlan.summary.commandCount
            mergeCount   = $encodingPlan.summary.mergeCount
            mergeValidationCount = $encodingPlan.summary.mergeValidationCount
            qualitySampleCount = $encodingPlan.summary.qualitySampleCount
            qualityDecodeCommandCount = $encodingPlan.summary.qualityDecodeCommandCount
            qualityMetricCommandCount = $encodingPlan.summary.qualityMetricCommandCount
            proxyCommandCount = $encodingPlan.summary.proxyCommandCount
            previewCommandCount = $encodingPlan.summary.previewCommandCount
            scheduler    = $encodingPlan.scheduler
            ffmpeg       = $encodingPlan.ffmpeg
            ffprobe      = $encodingPlan.ffprobe
        }
        resumeStatePath   = Get-BackupResumeStatePath -JobId ([string]$Job.id)
    }
}
