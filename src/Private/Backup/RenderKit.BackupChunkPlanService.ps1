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

        $assets.Add([PSCustomObject]@{
            id              = $assetId
            relativePath    = [string]$file.relativePath
            path            = [string]$file.path
            mediaType       = [string]$file.mediaType
            sizeBytes       = [int64]$file.sizeBytes
            durationSeconds = $durationSeconds
            chunkable       = $canChunk
            chunkCount      = if ($canChunk) { [int][Math]::Ceiling($durationSeconds / $ChunkDurationSeconds) } else { 0 }
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

        $chunkCount = [int][Math]::Ceiling($durationSeconds / $ChunkDurationSeconds)
        for ($index = 0; $index -lt $chunkCount; $index++) {
            $startSeconds = [double]($index * $ChunkDurationSeconds)
            $remainingSeconds = [Math]::Max(0, $durationSeconds - $startSeconds)
            $currentDuration = [Math]::Min([double]$ChunkDurationSeconds, [double]$remainingSeconds)
            if ($currentDuration -le 0) {
                continue
            }

            $chunkId = "chunk-{0}-{1:000000}" -f (ConvertTo-BackupStableId -Value ([string]$file.relativePath)), $index
            $chunks.Add([PSCustomObject]@{
                id              = $chunkId
                resumeKey       = $chunkId
                assetId         = $assetId
                relativePath    = [string]$file.relativePath
                index           = $index
                startSeconds    = [Math]::Round($startSeconds, 3)
                durationSeconds = [Math]::Round($currentDuration, 3)
                endSeconds      = [Math]::Round(($startSeconds + $currentDuration), 3)
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
            })
        }
    }

    $chunkArray = @($chunks.ToArray())
    $assetArray = @($assets.ToArray())
    $passThroughArray = @($passThroughFiles.ToArray())

    return [PSCustomObject]@{
        schemaVersion = '1.0'
        enabled       = [bool]$Enabled
        strategy      = if ($Enabled) { 'TimeRange' } else { 'Disabled' }
        durationSeconds = if ($Enabled) { $ChunkDurationSeconds } else { 0 }
        resumeMode    = if ($Enabled) { 'ChunkManifest' } else { 'WholeArchive' }
        state         = 'Planned'
        summary       = [PSCustomObject]@{
            assetCount           = @($assetArray).Count
            chunkableAssetCount  = @($assetArray | Where-Object { [bool]$_.chunkable }).Count
            chunkCount           = @($chunkArray).Count
            passThroughFileCount = @($passThroughArray).Count
            pendingChunkCount    = @($chunkArray | Where-Object { $_.state -eq 'Pending' }).Count
            completedChunkCount  = 0
        }
        assets        = @($assetArray)
        chunks        = @($chunkArray)
        passThrough   = @($passThroughArray)
    }
}
