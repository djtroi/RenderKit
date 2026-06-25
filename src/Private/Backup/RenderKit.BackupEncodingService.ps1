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

function Resolve-BackupVideoCodec {
    [CmdletBinding()]
    param(
        [ValidateSet('Auto', 'H264', 'H265', 'AV1')]
        [string]$VideoCodec = 'Auto',
        [ValidateSet('Fastest', 'Balanced', 'Smallest', 'Lossless')]
        [string]$CompressionPreset = 'Balanced'
    )

    if ($VideoCodec -ne 'Auto') {
        return $VideoCodec
    }

    switch ($CompressionPreset) {
        'Fastest' { return 'H264' }
        'Smallest' { return 'AV1' }
        default { return 'H265' }
    }
}

function Get-BackupCpuEncoderName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('H264', 'H265', 'AV1')]
        [string]$VideoCodec
    )

    switch ($VideoCodec) {
        'H264' { return 'libx264' }
        'H265' { return 'libx265' }
        'AV1' { return 'libsvtav1' }
    }
}

function Get-BackupHardwareEncoderName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('H264', 'H265', 'AV1')]
        [string]$VideoCodec,
        [Parameter(Mandatory)]
        [ValidateSet('Nvidia', 'IntelQuickSync', 'AMD')]
        [string]$EncoderDevice
    )

    $map = @{
        Nvidia = @{
            H264 = 'h264_nvenc'
            H265 = 'hevc_nvenc'
            AV1  = 'av1_nvenc'
        }
        IntelQuickSync = @{
            H264 = 'h264_qsv'
            H265 = 'hevc_qsv'
            AV1  = 'av1_qsv'
        }
        AMD = @{
            H264 = 'h264_amf'
            H265 = 'hevc_amf'
            AV1  = 'av1_amf'
        }
    }

    return [string]$map[$EncoderDevice][$VideoCodec]
}

function Get-BackupQualityValue {
    [CmdletBinding()]
    param(
        [ValidateSet('Draft', 'Balanced', 'High', 'Smallest', 'Lossless')]
        [string]$QualityPreset = 'Balanced',
        [Parameter(Mandatory)]
        [ValidateSet('H264', 'H265', 'AV1')]
        [string]$VideoCodec
    )

    if ($QualityPreset -eq 'Lossless') {
        return 0
    }

    switch ($VideoCodec) {
        'AV1' {
            switch ($QualityPreset) {
                'Draft' { return 40 }
                'High' { return 26 }
                'Smallest' { return 42 }
                default { return 34 }
            }
        }
        default {
            switch ($QualityPreset) {
                'Draft' { return 30 }
                'High' { return 20 }
                'Smallest' { return 32 }
                default { return 24 }
            }
        }
    }
}

function Resolve-BackupAudioProfile {
    [CmdletBinding()]
    param(
        [ValidateSet('Auto', 'AAC_128', 'AAC_192', 'Opus_96', 'Opus_128', 'Copy', 'Lossless')]
        [string]$AudioProfile = 'Auto',
        [ValidateSet('H264', 'H265', 'AV1')]
        [string]$VideoCodec = 'H265',
        [ValidateSet('Draft', 'Balanced', 'High', 'Smallest', 'Lossless')]
        [string]$QualityPreset = 'Balanced'
    )

    if ($AudioProfile -ne 'Auto') {
        return $AudioProfile
    }
    if ($QualityPreset -eq 'Lossless') {
        return 'Lossless'
    }
    if ($VideoCodec -eq 'AV1') {
        return 'Opus_96'
    }
    if ($QualityPreset -eq 'High') {
        return 'AAC_192'
    }
    return 'AAC_128'
}

function Get-BackupAudioArgs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('AAC_128', 'AAC_192', 'Opus_96', 'Opus_128', 'Copy', 'Lossless')]
        [string]$AudioProfile
    )

    switch ($AudioProfile) {
        'AAC_192' { return @('-c:a', 'aac', '-b:a', '192k') }
        'Opus_96' { return @('-c:a', 'libopus', '-b:a', '96k') }
        'Opus_128' { return @('-c:a', 'libopus', '-b:a', '128k') }
        'Copy' { return @('-c:a', 'copy') }
        'Lossless' { return @('-c:a', 'flac') }
        default { return @('-c:a', 'aac', '-b:a', '128k') }
    }
}

function Get-BackupEncodingProfile {
    [CmdletBinding()]
    param(
        [ValidateSet('Fastest', 'Balanced', 'Smallest', 'Lossless')]
        [string]$CompressionPreset = 'Balanced',
        [ValidateSet('Auto', 'H264', 'H265', 'AV1')]
        [string]$VideoCodec = 'Auto',
        [ValidateSet('Auto', 'CPU', 'Nvidia', 'IntelQuickSync', 'AMD')]
        [string]$EncoderDevice = 'Auto',
        [ValidateSet('Draft', 'Balanced', 'High', 'Smallest', 'Lossless')]
        [string]$QualityPreset = 'Balanced',
        [ValidateSet('Auto', 'AAC_128', 'AAC_192', 'Opus_96', 'Opus_128', 'Copy', 'Lossless')]
        [string]$AudioProfile = 'Auto'
    )

    $resolvedCodec = Resolve-BackupVideoCodec `
        -VideoCodec $VideoCodec `
        -CompressionPreset $CompressionPreset
    $resolvedDevice = if ($EncoderDevice -eq 'Auto') { 'CPU' } else { $EncoderDevice }
    $resolvedAudioProfile = Resolve-BackupAudioProfile `
        -AudioProfile $AudioProfile `
        -VideoCodec $resolvedCodec `
        -QualityPreset $QualityPreset
    $qualityValue = Get-BackupQualityValue `
        -QualityPreset $QualityPreset `
        -VideoCodec $resolvedCodec

    $encoderName = if ($resolvedDevice -eq 'CPU') {
        Get-BackupCpuEncoderName -VideoCodec $resolvedCodec
    }
    else {
        Get-BackupHardwareEncoderName `
            -VideoCodec $resolvedCodec `
            -EncoderDevice $resolvedDevice
    }

    $container = if ($resolvedCodec -eq 'AV1' -or $resolvedAudioProfile -like 'Opus*' -or $resolvedAudioProfile -eq 'Lossless') {
        'mkv'
    }
    else {
        'mp4'
    }

    $videoArgs = if ($resolvedDevice -eq 'CPU') {
        switch ($resolvedCodec) {
            'H264' {
                if ($QualityPreset -eq 'Lossless') {
                    @('-c:v', $encoderName, '-preset', 'medium', '-crf', '0')
                }
                else {
                    @('-c:v', $encoderName, '-preset', 'medium', '-crf', [string]$qualityValue)
                }
            }
            'H265' {
                @('-c:v', $encoderName, '-preset', 'medium', '-crf', [string]$qualityValue)
            }
            'AV1' {
                @('-c:v', $encoderName, '-crf', [string]$qualityValue, '-preset', '8')
            }
        }
    }
    else {
        @('-c:v', $encoderName, '-cq:v', [string]$qualityValue)
    }

    return [PSCustomObject]@{
        name            = "{0}-{1}-{2}" -f $resolvedCodec, $resolvedDevice, $QualityPreset
        container       = $container
        videoCodec      = $resolvedCodec
        encoderDevice   = $resolvedDevice
        encoderName     = $encoderName
        qualityPreset   = $QualityPreset
        qualityValue    = $qualityValue
        audioProfile    = $resolvedAudioProfile
        videoArgs       = @($videoArgs)
        audioArgs       = @(Get-BackupAudioArgs -AudioProfile $resolvedAudioProfile)
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

function Get-BackupProxyAssetPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [Parameter(Mandatory)]
        [string]$AssetId
    )

    $proxyRoot = New-RenderKitStorageDirectory -Path (
        Join-Path -Path (Get-BackupJobStateRoot -JobId $JobId) -ChildPath 'proxies'
    )

    return Join-Path -Path $proxyRoot -ChildPath ("{0}.proxy.mp4" -f $AssetId)
}

function Get-BackupPreviewAssetPattern {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [Parameter(Mandatory)]
        [string]$AssetId,
        [string]$Format = 'jpg'
    )

    $previewRoot = New-RenderKitStorageDirectory -Path (
        Join-Path -Path (
            Join-Path -Path (Get-BackupJobStateRoot -JobId $JobId) -ChildPath 'previews'
        ) -ChildPath $AssetId
    )

    return Join-Path -Path $previewRoot -ChildPath ("frame-%05d.{0}" -f $Format.TrimStart('.'))
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

    $encoding = if ($Payload.PSObject.Properties.Name -contains 'encoding' -and $Payload.encoding) {
        $Payload.encoding
    }
    else {
        [PSCustomObject]@{
            videoCodec    = 'Auto'
            encoderDevice = 'Auto'
            qualityPreset = 'Balanced'
            audioProfile  = 'Auto'
            proxy         = [PSCustomObject]@{ enabled = $false }
            preview       = [PSCustomObject]@{ enabled = $false }
        }
    }

    $profile = Get-BackupEncodingProfile `
        -CompressionPreset ([string]$Payload.archive.compressionPreset) `
        -VideoCodec ([string]$encoding.videoCodec) `
        -EncoderDevice ([string]$encoding.encoderDevice) `
        -QualityPreset ([string]$encoding.qualityPreset) `
        -AudioProfile ([string]$encoding.audioProfile)
    $ffmpeg = Get-BackupFfmpegCommand
    $commands = New-Object System.Collections.Generic.List[object]
    $merges = New-Object System.Collections.Generic.List[object]
    $proxyCommands = New-Object System.Collections.Generic.List[object]
    $previewCommands = New-Object System.Collections.Generic.List[object]
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

    foreach ($merge in @($merges.ToArray())) {
        if ($encoding.proxy -and [bool]$encoding.proxy.enabled) {
            $proxyHeight = if ($encoding.proxy.height) { [int]$encoding.proxy.height } else { 720 }
            $proxyOutputPath = Get-BackupProxyAssetPath `
                -JobId ([string]$Job.id) `
                -AssetId ([string]$merge.assetId)
            $proxyCommands.Add([PSCustomObject]@{
                id         = "proxy-$($merge.assetId)"
                type       = 'CreateProxy'
                assetId    = [string]$merge.assetId
                inputPath  = [string]$merge.outputPath
                outputPath = $proxyOutputPath
                executable = if ($ffmpeg) { [string]$ffmpeg.Source } else { 'ffmpeg' }
                arguments  = @(
                    '-hide_banner', '-y',
                    '-i', [string]$merge.outputPath,
                    '-vf', ("scale=-2:{0}" -f $proxyHeight),
                    '-c:v', 'libx264',
                    '-preset', 'veryfast',
                    '-crf', '30',
                    '-an',
                    $proxyOutputPath
                )
                state      = 'Planned'
            })
        }

        if ($encoding.preview -and [bool]$encoding.preview.enabled) {
            $previewFormat = if ($encoding.preview.format) { [string]$encoding.preview.format } else { 'jpg' }
            $previewInterval = if ($encoding.preview.intervalSeconds) { [int]$encoding.preview.intervalSeconds } else { 60 }
            $previewWidth = if ($encoding.preview.width) { [int]$encoding.preview.width } else { 1280 }
            $previewPattern = Get-BackupPreviewAssetPattern `
                -JobId ([string]$Job.id) `
                -AssetId ([string]$merge.assetId) `
                -Format $previewFormat
            $previewCommands.Add([PSCustomObject]@{
                id         = "preview-$($merge.assetId)"
                type       = 'CreatePreview'
                assetId    = [string]$merge.assetId
                inputPath  = [string]$merge.outputPath
                outputPath = $previewPattern
                executable = if ($ffmpeg) { [string]$ffmpeg.Source } else { 'ffmpeg' }
                arguments  = @(
                    '-hide_banner', '-y',
                    '-i', [string]$merge.outputPath,
                    '-vf', ("fps=1/{0},scale={1}:-2" -f $previewInterval, $previewWidth),
                    $previewPattern
                )
                state      = 'Planned'
            })
        }
    }

    return [PSCustomObject]@{
        schemaVersion = '1.0'
        mode          = [string]$Payload.archive.mode
        ffmpeg        = [PSCustomObject]@{
            available = $null -ne $ffmpeg
            path      = if ($ffmpeg) { [string]$ffmpeg.Source } else { $null }
        }
        profile       = $profile
        encoding      = $encoding
        summary       = [PSCustomObject]@{
            commandCount        = [int]$commands.Count
            mergeCount          = [int]$merges.Count
            proxyCommandCount   = [int]$proxyCommands.Count
            previewCommandCount = [int]$previewCommands.Count
            requiresFfmpeg      = ([int]$commands.Count + [int]$proxyCommands.Count + [int]$previewCommands.Count) -gt 0
        }
        commands      = @($commands.ToArray())
        merges        = @($merges.ToArray())
        proxyCommands = @($proxyCommands.ToArray())
        previewCommands = @($previewCommands.ToArray())
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
            proxyAssetCount   = 0
            previewAssetCount = 0
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

    foreach ($proxyCommand in @($Plan.proxyCommands)) {
        Invoke-BackupFfmpegCommand -Command $proxyCommand -JobId ([string]$Job.id) |
            Out-Null
    }

    foreach ($previewCommand in @($Plan.previewCommands)) {
        Invoke-BackupFfmpegCommand -Command $previewCommand -JobId ([string]$Job.id) |
            Out-Null
    }

    return [PSCustomObject]@{
        encodedChunkCount = $completed
        mergedAssetCount  = @($Plan.merges).Count
        proxyAssetCount   = @($Plan.proxyCommands).Count
        previewAssetCount = @($Plan.previewCommands).Count
        skipped           = $false
    }
}
