function Get-BackupFfmpegCommand {
    [CmdletBinding()]
    param()

    return Get-Command -Name ffmpeg -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
}

function ConvertTo-BackupInvariantNumber {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [double]$Value
    )

    return $Value.ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-BackupEncodingProfile {
    [CmdletBinding()]
    param(
        [ValidateSet('Fastest', 'Balanced', 'Smallest', 'Lossless')]
        [string]$CompressionPreset = 'Balanced'
    )

    switch ($CompressionPreset) {
        'Fastest' {
            return [PSCustomObject]@{
                name       = 'Fastest'
                container  = 'mp4'
                videoCodec = 'libx265'
                videoArgs  = @('-c:v', 'libx265', '-preset', 'ultrafast', '-crf', '28')
                audioArgs  = @('-c:a', 'aac', '-b:a', '160k')
            }
        }
        'Smallest' {
            return [PSCustomObject]@{
                name       = 'Smallest'
                container  = 'mkv'
                videoCodec = 'libsvtav1'
                videoArgs  = @('-c:v', 'libsvtav1', '-crf', '38', '-preset', '8')
                audioArgs  = @('-c:a', 'libopus', '-b:a', '96k')
            }
        }
        'Lossless' {
            return [PSCustomObject]@{
                name       = 'Lossless'
                container  = 'mkv'
                videoCodec = 'ffv1'
                videoArgs  = @('-c:v', 'ffv1', '-level', '3')
                audioArgs  = @('-c:a', 'flac')
            }
        }
        default {
            return [PSCustomObject]@{
                name       = 'Balanced'
                container  = 'mp4'
                videoCodec = 'libx265'
                videoArgs  = @('-c:v', 'libx265', '-preset', 'medium', '-crf', '24')
                audioArgs  = @('-c:a', 'aac', '-b:a', '128k')
            }
        }
    }
}

function Get-BackupEncodedChunkPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [Parameter(Mandatory)]
        [object]$Chunk,
        [Parameter(Mandatory)]
        [string]$Extension
    )

    $assetRoot = New-RenderKitStorageDirectory -Path (
        Join-Path -Path (
            Join-Path -Path (Get-BackupJobStateRoot -JobId $JobId) -ChildPath 'encoded'
        ) -ChildPath ([string]$Chunk.assetId)
    )

    return Join-Path -Path $assetRoot -ChildPath ("{0}.{1}" -f [string]$Chunk.id, $Extension.TrimStart('.'))
}

function Get-BackupMergedAssetPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [Parameter(Mandatory)]
        [string]$AssetId,
        [Parameter(Mandatory)]
        [string]$Extension
    )

    $mergeRoot = New-RenderKitStorageDirectory -Path (
        Join-Path -Path (Get-BackupJobStateRoot -JobId $JobId) -ChildPath 'merged'
    )

    return Join-Path -Path $mergeRoot -ChildPath ("{0}.{1}" -f $AssetId, $Extension.TrimStart('.'))
}

function New-BackupFfmpegChunkArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Chunk,
        [Parameter(Mandatory)]
        [object]$Profile,
        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    $arguments = New-Object System.Collections.Generic.List[string]
    foreach ($value in @(
            '-hide_banner',
            '-y',
            '-ss',
            (ConvertTo-BackupInvariantNumber -Value ([double]$Chunk.startSeconds)),
            '-t',
            (ConvertTo-BackupInvariantNumber -Value ([double]$Chunk.durationSeconds)),
            '-i',
            [string]$Chunk.path
        )) {
        $arguments.Add([string]$value)
    }
    foreach ($value in @($Profile.videoArgs)) { $arguments.Add([string]$value) }
    foreach ($value in @($Profile.audioArgs)) { $arguments.Add([string]$value) }
    foreach ($value in @('-map', '0', '-progress', 'pipe:1', '-nostats', $OutputPath)) {
        $arguments.Add([string]$value)
    }

    return @($arguments.ToArray())
}

function New-BackupEncodingPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Job,
        [object]$Payload
    )

    if (-not $Payload) {
        $Payload = $Job.payload
    }

    $profile = Get-BackupEncodingProfile -CompressionPreset ([string]$Payload.archive.compressionPreset)
    $ffmpeg = Get-BackupFfmpegCommand
    $commands = New-Object System.Collections.Generic.List[object]
    $merges = New-Object System.Collections.Generic.List[object]
    $chunks = @()
    if ($Payload.chunkPlan -and $Payload.chunkPlan.chunks) {
        $chunks = @($Payload.chunkPlan.chunks)
    }

    foreach ($chunk in @($chunks | Sort-Object assetId, index)) {
        if ([string]::IsNullOrWhiteSpace([string]$chunk.path)) {
            $asset = @($Payload.chunkPlan.assets | Where-Object { [string]$_.id -eq [string]$chunk.assetId } | Select-Object -First 1)
            if ($asset) {
                $chunk | Add-Member -NotePropertyName path -NotePropertyValue ([string]$asset[0].path) -Force
            }
        }

        $outputPath = Get-BackupEncodedChunkPath `
            -JobId ([string]$Job.id) `
            -Chunk $chunk `
            -Extension ([string]$profile.container)
        $commands.Add([PSCustomObject]@{
            id              = "encode-$($chunk.id)"
            type            = 'EncodeChunk'
            chunkId         = [string]$chunk.id
            assetId         = [string]$chunk.assetId
            relativePath    = [string]$chunk.relativePath
            index           = [int]$chunk.index
            startSeconds    = [double]$chunk.startSeconds
            durationSeconds = [double]$chunk.durationSeconds
            inputPath       = [string]$chunk.path
            outputPath      = $outputPath
            executable      = if ($ffmpeg) { [string]$ffmpeg.Source } else { 'ffmpeg' }
            arguments       = @(New-BackupFfmpegChunkArguments `
                    -Chunk $chunk `
                    -Profile $profile `
                    -OutputPath $outputPath)
            state           = 'Planned'
        })
    }

    foreach ($group in @($commands.ToArray() | Group-Object assetId)) {
        $assetId = [string]$group.Name
        if ([string]::IsNullOrWhiteSpace($assetId)) {
            continue
        }

        $mergeOutput = Get-BackupMergedAssetPath `
            -JobId ([string]$Job.id) `
            -AssetId $assetId `
            -Extension ([string]$profile.container)
        $concatListPath = Join-Path `
            -Path (Get-BackupJobStateRoot -JobId ([string]$Job.id)) `
            -ChildPath ("concat-{0}.txt" -f $assetId)

        $merges.Add([PSCustomObject]@{
            id             = "merge-$assetId"
            type           = 'MergeAssetChunks'
            assetId        = $assetId
            chunkIds       = @($group.Group | Sort-Object index | ForEach-Object { [string]$_.chunkId })
            inputPaths     = @($group.Group | Sort-Object index | ForEach-Object { [string]$_.outputPath })
            concatListPath = $concatListPath
            outputPath     = $mergeOutput
            executable     = if ($ffmpeg) { [string]$ffmpeg.Source } else { 'ffmpeg' }
            arguments      = @('-hide_banner', '-y', '-f', 'concat', '-safe', '0', '-i', $concatListPath, '-c', 'copy', $mergeOutput)
            state          = 'Planned'
        })
    }

    return [PSCustomObject]@{
        schemaVersion = '1.0'
        mode          = [string]$Payload.archive.mode
        ffmpeg        = [PSCustomObject]@{
            available = $null -ne $ffmpeg
            path      = if ($ffmpeg) { [string]$ffmpeg.Source } else { $null }
        }
        profile       = $profile
        summary       = [PSCustomObject]@{
            commandCount  = [int]$commands.Count
            mergeCount    = [int]$merges.Count
            requiresFfmpeg = [int]$commands.Count -gt 0
        }
        commands      = @($commands.ToArray())
        merges        = @($merges.ToArray())
    }
}

function ConvertFrom-BackupFfmpegProgressLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Line,
        [Nullable[double]]$DurationSeconds
    )

    $match = [System.Text.RegularExpressions.Regex]::Match($Line, '^(?<key>[^=]+)=(?<value>.*)$')
    if (-not $match.Success) {
        return $null
    }

    $key = $match.Groups['key'].Value
    $value = $match.Groups['value'].Value
    $seconds = $null
    if ($key -in @('out_time_us', 'out_time_ms')) {
        $raw = 0.0
        if ([double]::TryParse(
                $value,
                [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$raw)) {
            $seconds = [Math]::Round(($raw / 1000000.0), 3)
        }
    }
    elseif ($key -eq 'out_time') {
        $time = [TimeSpan]::Zero
        if ([TimeSpan]::TryParse($value, [ref]$time)) {
            $seconds = [Math]::Round($time.TotalSeconds, 3)
        }
    }

    $percent = $null
    if ($null -ne $seconds -and $null -ne $DurationSeconds -and $DurationSeconds -gt 0) {
        $percent = [Math]::Min(100, [Math]::Round(([double]$seconds / [double]$DurationSeconds) * 100, 2))
    }

    return [PSCustomObject]@{
        key            = $key
        value          = $value
        seconds        = $seconds
        percent        = $percent
        isTerminal     = $key -eq 'progress' -and $value -eq 'end'
    }
}

function Write-BackupConcatList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$MergeCommand
    )

    $lines = foreach ($path in @($MergeCommand.inputPaths)) {
        "file '$(([string]$path).Replace("'", "'\\''"))'"
    }

    Set-Content `
        -LiteralPath ([string]$MergeCommand.concatListPath) `
        -Value $lines `
        -Encoding UTF8
}

function Invoke-BackupFfmpegCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Command,
        [string]$JobId
    )

    if ([string]::IsNullOrWhiteSpace([string]$Command.executable) -or
        -not (Test-Path -LiteralPath ([string]$Command.executable) -PathType Leaf)) {
        throw "ffmpeg executable was not found."
    }

    $lines = & ([string]$Command.executable) @($Command.arguments) 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "ffmpeg command '$($Command.id)' failed with exit code $LASTEXITCODE."
    }

    return @($lines)
}

function Invoke-BackupEncodingPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Job,
        [Parameter(Mandatory)]
        [object]$Plan
    )

    $total = [int]$Plan.summary.commandCount
    if ($total -eq 0) {
        Update-RenderKitJobProgress `
            -JobId ([string]$Job.id) `
            -Phase 'EncodingSkipped' `
            -Message 'No chunkable media requires encoding.' `
            -Current 0 `
            -Total 0 `
            -Percent 100 |
            Out-Null
        return [PSCustomObject]@{
            encodedChunkCount = 0
            mergedAssetCount  = 0
            skipped           = $true
        }
    }

    if (-not [bool]$Plan.ffmpeg.available) {
        throw 'ffmpeg was not found. Install ffmpeg or run the backup without TranscodeAndArchive mode.'
    }

    $completed = 0
    foreach ($command in @($Plan.commands | Sort-Object assetId, index)) {
        Update-RenderKitJobProgress `
            -JobId ([string]$Job.id) `
            -Phase 'Encoding' `
            -Message ("Encoding chunk {0}/{1}: {2}" -f ($completed + 1), $total, [string]$command.relativePath) `
            -Current $completed `
            -Total $total |
            Out-Null

        Invoke-BackupFfmpegCommand -Command $command -JobId ([string]$Job.id) |
            ForEach-Object {
                $progress = ConvertFrom-BackupFfmpegProgressLine `
                    -Line ([string]$_) `
                    -DurationSeconds ([double]$command.durationSeconds)
                if ($progress -and $null -ne $progress.percent) {
                    $overall = [Math]::Round(((($completed + ($progress.percent / 100.0)) / $total) * 100), 2)
                    Update-RenderKitJobProgress `
                        -JobId ([string]$Job.id) `
                        -Phase 'Encoding' `
                        -Message ("Encoding chunk {0}/{1}: {2}" -f ($completed + 1), $total, [string]$command.relativePath) `
                        -Current $completed `
                        -Total $total `
                        -Percent $overall |
                        Out-Null
                }
            }

        $completed++
        Update-RenderKitJobProgress `
            -JobId ([string]$Job.id) `
            -Phase 'Encoding' `
            -Message ("Encoded chunk {0}/{1}" -f $completed, $total) `
            -Current $completed `
            -Total $total |
            Out-Null
    }

    foreach ($merge in @($Plan.merges)) {
        Write-BackupConcatList -MergeCommand $merge
        Invoke-BackupFfmpegCommand -Command $merge -JobId ([string]$Job.id) |
            Out-Null
    }

    return [PSCustomObject]@{
        encodedChunkCount = $completed
        mergedAssetCount  = @($Plan.merges).Count
        skipped           = $false
    }
}
