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

    Update-RenderKitJobProgress `
        -JobId ([string]$Job.id) `
        -Phase 'PlanningEncoding' `
        -Message 'Planning backup encoding stage.' `
        -Current 0 `
        -Total 1 `
        -Percent 0 |
        Out-Null

    $encodingPlan = New-BackupEncodingPlan -Job $Job -Payload $payload
    $resumeState = New-BackupResumeState -Job $Job -Payload $payload
    $resumeState | Add-Member -NotePropertyName encodingPlan -NotePropertyValue $encodingPlan -Force
    $resumeState.progress.currentPhase = 'EncodingPlanned'
    Save-BackupResumeState `
        -JobId ([string]$Job.id) `
        -State $resumeState |
        Out-Null

    $encodingResult = if ([string]$payload.archive.mode -eq 'TranscodeAndArchive') {
        Invoke-BackupEncodingPlan -Job $Job -Plan $encodingPlan
    }
    else {
        Update-RenderKitJobProgress `
            -JobId ([string]$Job.id) `
            -Phase 'EncodingSkipped' `
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
            proxyAssetCount            = 0
            previewAssetCount          = 0
            scheduler                  = [PSCustomObject]@{
                usedParallel = $false
                skipped      = $true
            }
            skipped                    = $true
        }
    }

    $resumeState.progress.currentPhase = 'EncodingComplete'
    $resumeState.progress.completedChunkCount = [int]$encodingResult.encodedChunkCount
    $resumeState.progress.mergedAssetCount = [int]$encodingResult.mergedAssetCount
    $resumeState.progress.validatedMergedAssetCount = [int]$encodingResult.mergeValidationCount
    $resumeState.progress.failedMergeValidationCount = [int]$encodingResult.mergeValidationFailedCount
    $resumeState.progress.schedulerUsedParallel = [bool]$encodingResult.scheduler.usedParallel
    $resumeState.progress.pendingChunkCount = [Math]::Max(
        0,
        [int]$resumeState.progress.pendingChunkCount - [int]$encodingResult.encodedChunkCount
    )
    $resumeState | Add-Member `
        -NotePropertyName mergeValidation `
        -NotePropertyValue @($encodingResult.mergeValidations) `
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
        proxyAssetCount   = [int]$encodingResult.proxyAssetCount
        previewAssetCount = [int]$encodingResult.previewAssetCount
        scheduler        = $encodingResult.scheduler
        encodingPlan      = [PSCustomObject]@{
            profile      = $encodingPlan.profile.name
            commandCount = $encodingPlan.summary.commandCount
            mergeCount   = $encodingPlan.summary.mergeCount
            mergeValidationCount = $encodingPlan.summary.mergeValidationCount
            proxyCommandCount = $encodingPlan.summary.proxyCommandCount
            previewCommandCount = $encodingPlan.summary.previewCommandCount
            scheduler    = $encodingPlan.scheduler
            ffmpeg       = $encodingPlan.ffmpeg
            ffprobe      = $encodingPlan.ffprobe
        }
        resumeStatePath   = Get-BackupResumeStatePath -JobId ([string]$Job.id)
    }
}
