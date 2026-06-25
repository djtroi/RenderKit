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
            encodedChunkCount = 0
            mergedAssetCount  = 0
            skipped           = $true
        }
    }

    $resumeState.progress.currentPhase = 'EncodingComplete'
    $resumeState.progress.completedChunkCount = [int]$encodingResult.encodedChunkCount
    $resumeState.progress.pendingChunkCount = [Math]::Max(
        0,
        [int]$resumeState.progress.pendingChunkCount - [int]$encodingResult.encodedChunkCount
    )
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
        encodingPlan      = [PSCustomObject]@{
            profile      = $encodingPlan.profile.name
            commandCount = $encodingPlan.summary.commandCount
            mergeCount   = $encodingPlan.summary.mergeCount
            ffmpeg       = $encodingPlan.ffmpeg
        }
        resumeStatePath   = Get-BackupResumeStatePath -JobId ([string]$Job.id)
    }
}
