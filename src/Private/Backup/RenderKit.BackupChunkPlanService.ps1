function ConvertTo-BackupStableId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value,
        [ValidateRange(8, 64)]
        [int]$Length = 16
    )

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        $hash = $sha.ComputeHash($bytes)
        $hex = -join ($hash | ForEach-Object { $_.ToString('x2') })
        return $hex.Substring(0, [Math]::Min($Length, $hex.Length))
    }
    finally {
        $sha.Dispose()
    }
}

function Get-BackupMediaKeyframeSecond {
    [CmdletBinding()]
    param(
        [object]$File
    )

    if (-not $File -or -not $File.metadata) {
        return @()
    }
    if (-not ($File.metadata.PSObject.Properties.Name -contains 'keyframes') -or
        -not $File.metadata.keyframes) {
        return @()
    }

    return @($File.metadata.keyframes |
        ForEach-Object { [double]$_ } |
        Where-Object { $_ -ge 0 } |
        Sort-Object -Unique)
}

function Select-BackupChunkBoundary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [double]$TargetSeconds,
        [Parameter(Mandatory)]
        [double]$DurationSeconds,
        [double[]]$KeyframeSeconds,
        [ValidateRange(0, 60)]
        [double]$ToleranceSeconds = 2.0
    )

    $safeTarget = [Math]::Min([Math]::Max(0, $TargetSeconds), $DurationSeconds)
    $keyframes = @($KeyframeSeconds | Where-Object {
        $_ -gt 0 -and $_ -lt $DurationSeconds
    })

    if ($keyframes.Count -gt 0) {
        $candidate = @($keyframes |
            Where-Object { [Math]::Abs($_ - $safeTarget) -le $ToleranceSeconds } |
            Sort-Object @{ Expression = { [Math]::Abs($_ - $safeTarget) } }, { $_ } |
            Select-Object -First 1)

        if ($candidate.Count -gt 0) {
            return [PSCustomObject]@{
                seconds          = [double]$candidate[0]
                targetSeconds    = $safeTarget
                source           = 'Keyframe'
                keyframeAligned  = $true
                driftSeconds     = [Math]::Round(([double]$candidate[0] - $safeTarget), 3)
            }
        }
    }

    return [PSCustomObject]@{
        seconds          = $safeTarget
        targetSeconds    = $safeTarget
        source           = if ($keyframes.Count -gt 0) { 'TargetNoKeyframeWithinTolerance' } else { 'EstimatedTimeRange' }
        keyframeAligned  = $false
        driftSeconds     = 0.0
    }
}

function New-BackupChunkBoundaryPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$File,
        [ValidateRange(10, 86400)]
        [int]$ChunkDurationSeconds = 600
    )

    $durationSeconds = [double]$File.metadata.durationSeconds
    $keyframes = @(Get-BackupMediaKeyframeSecond -File $File)
    $toleranceSeconds = [Math]::Min(
        5.0,
        [Math]::Max(0.25, [double]$ChunkDurationSeconds * 0.1)
    )

    $boundaries = New-Object System.Collections.Generic.List[object]
    $boundaries.Add([PSCustomObject]@{
        seconds         = 0.0
        targetSeconds   = 0.0
        source          = 'Start'
        keyframeAligned = $true
        driftSeconds    = 0.0
    })

    for ($target = [double]$ChunkDurationSeconds; $target -lt $durationSeconds; $target += [double]$ChunkDurationSeconds) {
        $boundary = Select-BackupChunkBoundary `
            -TargetSeconds $target `
            -DurationSeconds $durationSeconds `
            -KeyframeSeconds $keyframes `
            -ToleranceSeconds $toleranceSeconds

        $previous = [double]$boundaries[$boundaries.Count - 1].seconds
        if ([double]$boundary.seconds -le ($previous + 0.001)) {
            continue
        }

        $boundaries.Add($boundary)
    }

    $boundaries.Add([PSCustomObject]@{
        seconds         = $durationSeconds
        targetSeconds   = $durationSeconds
        source          = 'End'
        keyframeAligned = $true
        driftSeconds    = 0.0
    })

    return [PSCustomObject]@{
        schemaVersion = '1.0'
        mode          = if ($keyframes.Count -gt 0) { 'KeyframeAwareTimeRange' } else { 'EstimatedTimeRange' }
        targetDurationSeconds = [int]$ChunkDurationSeconds
        keyframeToleranceSeconds = [Math]::Round($toleranceSeconds, 3)
        keyframeCount = [int]$keyframes.Count
        audioSync     = [PSCustomObject]@{
            strategy              = 'PreserveTimeline'
            timestampMode         = 'ResetPerChunkThenReconcileOnMerge'
            maxDriftMilliseconds  = 50
            actionOnDrift         = 'FailChunkAndRetry'
        }
        gop          = [PSCustomObject]@{
            strategy              = if ($keyframes.Count -gt 0) { 'SnapBoundariesToKeyframes' } else { 'ReencodeWithBoundaryKeyframes' }
            fallback              = 'UseEstimatedTimeRangeWhenNoKeyframeFitsTolerance'
            maxBoundaryDriftSeconds = [Math]::Round($toleranceSeconds, 3)
        }
        boundaries   = @($boundaries.ToArray())
    }
}

function New-BackupChunkPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$MediaAnalysis,
        [ValidateRange(10, 86400)]
        [int]$ChunkDurationSeconds = 600,
        [switch]$Enabled
    )

    $assets = New-Object System.Collections.Generic.List[object]
    $chunks = New-Object System.Collections.Generic.List[object]
    $indexEntries = New-Object System.Collections.Generic.List[object]
    $passThroughFiles = New-Object System.Collections.Generic.List[object]

    foreach ($file in @($MediaAnalysis.files | Sort-Object relativePath)) {
        $assetId = "asset-{0}" -f (ConvertTo-BackupStableId -Value ([string]$file.relativePath))
        $durationSeconds = if ($file.metadata -and $null -ne $file.metadata.durationSeconds) {
            [double]$file.metadata.durationSeconds
        }
        else {
            $null
        }
        $canChunk = [bool]$Enabled -and [bool]$file.isChunkable -and $null -ne $durationSeconds -and $durationSeconds -gt 0

        $boundaryPlan = if ($canChunk) {
            New-BackupChunkBoundaryPlan `
                -File $file `
                -ChunkDurationSeconds $ChunkDurationSeconds
        }
        else {
            $null
        }

        $assets.Add([PSCustomObject]@{
            id              = $assetId
            relativePath    = [string]$file.relativePath
            path            = [string]$file.path
            mediaType       = [string]$file.mediaType
            sizeBytes       = [int64]$file.sizeBytes
            durationSeconds = $durationSeconds
            chunkable       = $canChunk
            chunkCount      = if ($boundaryPlan) { [Math]::Max(0, @($boundaryPlan.boundaries).Count - 1) } else { 0 }
            segmentation    = if ($boundaryPlan) {
                [PSCustomObject]@{
                    mode          = $boundaryPlan.mode
                    keyframeCount = $boundaryPlan.keyframeCount
                    gopStrategy   = $boundaryPlan.gop.strategy
                    audioSync     = $boundaryPlan.audioSync.strategy
                }
            }
            else {
                $null
            }
            state           = 'Planned'
        })

        if (-not $canChunk) {
            $passThroughFiles.Add([PSCustomObject]@{
                assetId      = $assetId
                relativePath = [string]$file.relativePath
                mediaType    = [string]$file.mediaType
                state        = 'Planned'
            })
            continue
        }

        $boundaries = @($boundaryPlan.boundaries)
        $chunkCount = [Math]::Max(0, $boundaries.Count - 1)
        for ($index = 0; $index -lt $chunkCount; $index++) {
            $startBoundary = $boundaries[$index]
            $endBoundary = $boundaries[$index + 1]
            $startSeconds = [double]$startBoundary.seconds
            $endSeconds = [double]$endBoundary.seconds
            $currentDuration = [Math]::Max(0, $endSeconds - $startSeconds)
            if ($currentDuration -le 0) {
                continue
            }

            $chunkId = "chunk-{0}-{1:000000}" -f (ConvertTo-BackupStableId -Value ([string]$file.relativePath)), $index
            $resumeKey = $chunkId
            $chunk = [PSCustomObject]@{
                id              = $chunkId
                resumeKey       = $resumeKey
                assetId         = $assetId
                relativePath    = [string]$file.relativePath
                index           = $index
                startSeconds    = [Math]::Round($startSeconds, 3)
                durationSeconds = [Math]::Round($currentDuration, 3)
                endSeconds      = [Math]::Round($endSeconds, 3)
                segment         = [PSCustomObject]@{
                    mode                  = $boundaryPlan.mode
                    boundaryMode          = if ([bool]$startBoundary.keyframeAligned) { 'KeyframeAlignedStart' } else { 'EstimatedStart' }
                    targetStartSeconds    = [Math]::Round([double]$startBoundary.targetSeconds, 3)
                    actualStartSeconds    = [Math]::Round($startSeconds, 3)
                    targetEndSeconds      = [Math]::Round([double]$endBoundary.targetSeconds, 3)
                    actualEndSeconds      = [Math]::Round($endSeconds, 3)
                    startBoundarySource   = [string]$startBoundary.source
                    endBoundarySource     = [string]$endBoundary.source
                    startKeyframeAligned  = [bool]$startBoundary.keyframeAligned
                    endKeyframeAligned    = [bool]$endBoundary.keyframeAligned
                    boundaryDriftSeconds  = [Math]::Round([double]$startBoundary.driftSeconds, 3)
                    preRollSeconds        = [Math]::Max(0, [Math]::Round(([double]$startBoundary.targetSeconds - $startSeconds), 3))
                }
                gop             = $boundaryPlan.gop
                audioSync       = [PSCustomObject]@{
                    strategy              = $boundaryPlan.audioSync.strategy
                    timestampMode         = $boundaryPlan.audioSync.timestampMode
                    expectedStartSeconds  = [Math]::Round($startSeconds, 3)
                    expectedDurationSeconds = [Math]::Round($currentDuration, 3)
                    maxDriftMilliseconds  = [int]$boundaryPlan.audioSync.maxDriftMilliseconds
                    actionOnDrift         = [string]$boundaryPlan.audioSync.actionOnDrift
                }
                state           = 'Pending'
                attempts        = 0
                output          = [PSCustomObject]@{
                    path      = $null
                    sizeBytes = $null
                    hash      = $null
                }
                verification    = [PSCustomObject]@{
                    decodeProbe = 'Pending'
                    checksum    = 'Pending'
                }
            }
            $chunks.Add($chunk)
            $indexEntries.Add([PSCustomObject]@{
                chunkId       = $chunkId
                resumeKey     = $resumeKey
                assetId       = $assetId
                relativePath  = [string]$file.relativePath
                index         = $index
                startSeconds  = $chunk.startSeconds
                endSeconds    = $chunk.endSeconds
                state         = 'Pending'
                attempts      = 0
                outputPath    = $null
                completedAtUtc = $null
            })
        }
    }

    $chunkArray = @($chunks.ToArray())
    $assetArray = @($assets.ToArray())
    $passThroughArray = @($passThroughFiles.ToArray())

    return [PSCustomObject]@{
        schemaVersion = '1.1'
        enabled       = [bool]$Enabled
        strategy      = if ($Enabled) { 'KeyframeAwareTimeRange' } else { 'Disabled' }
        durationSeconds = if ($Enabled) { $ChunkDurationSeconds } else { 0 }
        resumeMode    = if ($Enabled) { 'ChunkManifest' } else { 'WholeArchive' }
        state         = 'Planned'
        segmentation  = [PSCustomObject]@{
            boundaryStrategy = if ($Enabled) { 'KeyframeAwareWithEstimatedFallback' } else { 'Disabled' }
            gopStrategy      = 'SnapBoundariesToKeyframesOrReencodeBoundary'
            audioSyncStrategy = 'PreserveTimelineWithDriftGuard'
            resumeStrategy   = if ($Enabled) { 'ChunkIndex' } else { 'WholeArchive' }
        }
        summary       = [PSCustomObject]@{
            assetCount           = @($assetArray).Count
            chunkableAssetCount  = @($assetArray | Where-Object { [bool]$_.chunkable }).Count
            chunkCount           = @($chunkArray).Count
            passThroughFileCount = @($passThroughArray).Count
            pendingChunkCount    = @($chunkArray | Where-Object { $_.state -eq 'Pending' }).Count
            completedChunkCount  = 0
        }
        index         = [PSCustomObject]@{
            schemaVersion = '1.0'
            id            = "chunk-index-{0}" -f ([guid]::NewGuid().ToString('N'))
            jobId         = $null
            statePath     = $null
            createdAtUtc  = (Get-Date).ToUniversalTime().ToString('o')
            entries       = @($indexEntries.ToArray())
        }
        assets        = @($assetArray)
        chunks        = @($chunkArray)
        passThrough   = @($passThroughArray)
    }
}
