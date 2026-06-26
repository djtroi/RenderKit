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
        [string]$AudioProfile = 'Auto',
        [object]$GpuCapabilities
    )

    $resolvedCodec = Resolve-BackupVideoCodec `
        -VideoCodec $VideoCodec `
        -CompressionPreset $CompressionPreset
    $encoderSelection = Resolve-BackupEncoderDeviceFromCapabilities `
        -VideoCodec $resolvedCodec `
        -EncoderDevice $EncoderDevice `
        -GpuCapabilities $GpuCapabilities
    $resolvedDevice = [string]$encoderSelection.device
    $resolvedAudioProfile = Resolve-BackupAudioProfile `
        -AudioProfile $AudioProfile `
        -VideoCodec $resolvedCodec `
        -QualityPreset $QualityPreset
    $qualityValue = Get-BackupQualityValue `
        -QualityPreset $QualityPreset `
        -VideoCodec $resolvedCodec

    $encoderName = [string]$encoderSelection.encoderName

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
        encoderSelection = $encoderSelection
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

function Get-BackupPlanAsset {
    [CmdletBinding()]
    param(
        [object]$Payload,
        [Parameter(Mandatory)]
        [string]$AssetId
    )

    if (-not $Payload -or -not $Payload.chunkPlan -or -not $Payload.chunkPlan.assets) {
        return $null
    }

    return @($Payload.chunkPlan.assets |
        Where-Object { [string]$_.id -eq $AssetId } |
        Select-Object -First 1)
}

function Get-BackupPlanSourceFile {
    [CmdletBinding()]
    param(
        [object]$Payload,
        [object]$Asset,
        [string]$RelativePath,
        [string]$InputPath
    )

    if (-not $Payload -or -not $Payload.mediaAnalysis -or -not $Payload.mediaAnalysis.files) {
        return $null
    }

    $assetRelativePath = if ($Asset -and $Asset.PSObject.Properties.Name -contains 'relativePath') {
        [string]$Asset.relativePath
    }
    else {
        $null
    }
    $assetPath = if ($Asset -and $Asset.PSObject.Properties.Name -contains 'path') {
        [string]$Asset.path
    }
    else {
        $null
    }

    return @($Payload.mediaAnalysis.files |
        Where-Object {
            ([string]$_.relativePath -eq $RelativePath) -or
            (-not [string]::IsNullOrWhiteSpace($assetRelativePath) -and [string]$_.relativePath -eq $assetRelativePath) -or
            (-not [string]::IsNullOrWhiteSpace($InputPath) -and [string]$_.path -eq $InputPath) -or
            (-not [string]::IsNullOrWhiteSpace($assetPath) -and [string]$_.path -eq $assetPath)
        } |
        Select-Object -First 1)
}

function Get-BackupMetadataStreamList {
    [CmdletBinding()]
    param(
        [object]$Metadata,
        [ValidateSet('videoStreams', 'audioStreams')]
        [string]$PropertyName
    )

    if (-not $Metadata -or -not ($Metadata.PSObject.Properties.Name -contains $PropertyName) -or -not $Metadata.$PropertyName) {
        return @()
    }

    return @($Metadata.$PropertyName)
}

function New-BackupMergeValidationExpectation {
    [CmdletBinding()]
    param(
        [object]$Payload,
        [Parameter(Mandatory)]
        [string]$AssetId,
        [Parameter(Mandatory)]
        [object[]]$Commands,
        [Parameter(Mandatory)]
        [object]$Profile
    )

    $orderedCommands = @($Commands | Sort-Object index)
    $expectedDuration = 0.0
    foreach ($command in @($orderedCommands)) {
        $expectedDuration += [double]$command.durationSeconds
    }
    $expectedDuration = [Math]::Round($expectedDuration, 3)

    $firstCommand = @($orderedCommands | Select-Object -First 1)
    $relativePath = if ($firstCommand.Count -gt 0) { [string]$firstCommand[0].relativePath } else { $null }
    $inputPath = if ($firstCommand.Count -gt 0) { [string]$firstCommand[0].inputPath } else { $null }
    $asset = Get-BackupPlanAsset -Payload $Payload -AssetId $AssetId
    $sourceFile = Get-BackupPlanSourceFile `
        -Payload $Payload `
        -Asset $asset `
        -RelativePath $relativePath `
        -InputPath $inputPath
    $metadata = if ($sourceFile -and $sourceFile.metadata) { $sourceFile.metadata } else { $null }
    $videoStreams = @(Get-BackupMetadataStreamList -Metadata $metadata -PropertyName videoStreams)
    $audioStreams = @(Get-BackupMetadataStreamList -Metadata $metadata -PropertyName audioStreams)
    $mediaType = if ($asset -and $asset.PSObject.Properties.Name -contains 'mediaType' -and $asset.mediaType) {
        [string]$asset.mediaType
    }
    elseif ($sourceFile -and $sourceFile.PSObject.Properties.Name -contains 'mediaType') {
        [string]$sourceFile.mediaType
    }
    else {
        $null
    }
    $sourceHasVideo = ($mediaType -eq 'Video') -or @($videoStreams).Count -gt 0 -or ($metadata -and [bool]$metadata.hasVideo)
    $sourceHasAudio = ($mediaType -eq 'Audio') -or @($audioStreams).Count -gt 0 -or ($metadata -and [bool]$metadata.hasAudio)

    $audioDriftSeconds = 0.0
    foreach ($command in @($orderedCommands)) {
        if ($command.PSObject.Properties.Name -contains 'audioSync' -and $command.audioSync) {
            $audioDriftSeconds += ([double]$command.audioSync.maxDriftMilliseconds / 1000.0)
        }
    }

    $durationTolerance = [Math]::Max(1.0, [Math]::Min(5.0, [double]$expectedDuration * 0.002))
    $durationTolerance = [Math]::Max($durationTolerance, $audioDriftSeconds + 0.25)

    return [PSCustomObject]@{
        schemaVersion            = '1.0'
        required                 = $true
        assetId                  = $AssetId
        relativePath             = $relativePath
        expectedDurationSeconds  = $expectedDuration
        durationToleranceSeconds = [Math]::Round($durationTolerance, 3)
        expectedVideo            = [bool]$sourceHasVideo
        expectedAudio            = [bool]$sourceHasAudio
        expectedVideoCodec       = [string]$Profile.videoCodec
        expectedAudioProfile     = [string]$Profile.audioProfile
        containerPolicy          = 'FfprobeReadableContainer'
        streamPolicy             = 'RequireExpectedPrimaryStreams'
        syncPolicy               = 'DurationDriftWithinTolerance'
        source                   = [PSCustomObject]@{
            mediaType        = $mediaType
            durationSeconds  = if ($sourceFile -and $sourceFile.metadata) { $sourceFile.metadata.durationSeconds } else { $null }
            videoStreamCount = @($videoStreams).Count
            audioStreamCount = @($audioStreams).Count
        }
    }
}

function Get-BackupSchedulerExecution {
    [CmdletBinding()]
    param(
        [object]$Payload
    )

    $execution = if ($Payload -and $Payload.execution) {
        $Payload.execution
    }
    else {
        [PSCustomObject]@{}
    }
    $limits = if ($execution.PSObject.Properties.Name -contains 'resourceLimits' -and $execution.resourceLimits) {
        $execution.resourceLimits
    }
    else {
        [PSCustomObject]@{}
    }
    $maxParallelJobs = if ($execution.PSObject.Properties.Name -contains 'maxParallelJobs' -and $execution.maxParallelJobs) {
        [int]$execution.maxParallelJobs
    }
    else {
        1
    }
    $maxCpuPercent = if ($limits.PSObject.Properties.Name -contains 'maxCpuPercent' -and $limits.maxCpuPercent) {
        [int]$limits.maxCpuPercent
    }
    else {
        90
    }
    $maxGpuPercent = if ($limits.PSObject.Properties.Name -contains 'maxGpuPercent' -and $limits.maxGpuPercent) {
        [int]$limits.maxGpuPercent
    }
    else {
        95
    }
    $maxDiskActivePercent = if ($limits.PSObject.Properties.Name -contains 'maxDiskActivePercent' -and $limits.maxDiskActivePercent) {
        [int]$limits.maxDiskActivePercent
    }
    else {
        90
    }
    $maxTemperatureCelsius = if ($limits.PSObject.Properties.Name -contains 'maxTemperatureCelsius' -and $limits.maxTemperatureCelsius) {
        [int]$limits.maxTemperatureCelsius
    }
    else {
        85
    }
    $minIdleMinutes = if ($limits.PSObject.Properties.Name -contains 'minIdleMinutes' -and $null -ne $limits.minIdleMinutes) {
        [int]$limits.minIdleMinutes
    }
    else {
        10
    }
    $allowedStartTime = if ($limits.PSObject.Properties.Name -contains 'allowedStartTime') {
        [string]$limits.allowedStartTime
    }
    else {
        $null
    }
    $allowedEndTime = if ($limits.PSObject.Properties.Name -contains 'allowedEndTime') {
        [string]$limits.allowedEndTime
    }
    else {
        $null
    }
    $systemRulePollSeconds = if ($limits.PSObject.Properties.Name -contains 'systemRulePollSeconds' -and $limits.systemRulePollSeconds) {
        [int]$limits.systemRulePollSeconds
    }
    else {
        5
    }
    $requireIdle = if ($execution.PSObject.Properties.Name -contains 'requireIdle') { [bool]$execution.requireIdle } else { $false }
    $allowOnBattery = if ($execution.PSObject.Properties.Name -contains 'allowOnBattery') { [bool]$execution.allowOnBattery } else { $false }
    $thermalThrottleEnabled = if ($execution.PSObject.Properties.Name -contains 'thermalThrottleEnabled') { [bool]$execution.thermalThrottleEnabled } else { $true }
    $systemRules = if ($Payload -and $Payload.PSObject.Properties.Name -contains 'systemRules' -and $Payload.systemRules) {
        $Payload.systemRules
    }
    elseif ($execution.PSObject.Properties.Name -contains 'systemRules' -and $execution.systemRules) {
        $execution.systemRules
    }
    else {
        New-RenderKitSystemRulesPolicy `
            -RequireIdle $requireIdle `
            -MinIdleMinutes $minIdleMinutes `
            -AllowOnBattery $allowOnBattery `
            -ThermalThrottleEnabled $thermalThrottleEnabled `
            -MaxCpuPercent $maxCpuPercent `
            -MaxGpuPercent $maxGpuPercent `
            -MaxDiskActivePercent $maxDiskActivePercent `
            -MaxTemperatureCelsius $maxTemperatureCelsius `
            -AllowedStartTime $allowedStartTime `
            -AllowedEndTime $allowedEndTime `
            -PollIntervalSeconds $systemRulePollSeconds
    }

    $maxWorkers = [Math]::Max(1, [Math]::Min(64, $maxParallelJobs))
    $cpuWorkerLimit = if ($maxCpuPercent -lt 45) {
        1
    }
    elseif ($maxCpuPercent -lt 70) {
        [Math]::Min($maxWorkers, 2)
    }
    else {
        $maxWorkers
    }
    $gpuWorkerLimit = if ($maxGpuPercent -lt 50) {
        1
    }
    elseif ($maxGpuPercent -lt 80) {
        [Math]::Min($maxWorkers, 2)
    }
    else {
        $maxWorkers
    }
    $diskWorkerLimit = [Math]::Max(1, [Math]::Min($maxWorkers, 2))

    return [PSCustomObject]@{
        mode                  = if ($maxWorkers -gt 1) { 'WorkerPool' } else { 'SingleWorker' }
        maxWorkers            = $maxWorkers
        cpuWorkerLimit        = [Math]::Max(1, $cpuWorkerLimit)
        gpuWorkerLimit        = [Math]::Max(1, $gpuWorkerLimit)
        diskWorkerLimit       = $diskWorkerLimit
        maxCpuPercent         = $maxCpuPercent
        maxGpuPercent         = $maxGpuPercent
        maxDiskActivePercent  = $maxDiskActivePercent
        maxTemperatureCelsius = $maxTemperatureCelsius
        requireIdle           = $requireIdle
        minIdleMinutes        = $minIdleMinutes
        allowedStartTime      = $allowedStartTime
        allowedEndTime        = $allowedEndTime
        systemRulePollSeconds = $systemRulePollSeconds
        allowOnBattery        = $allowOnBattery
        thermalThrottleEnabled = $thermalThrottleEnabled
        systemRules           = $systemRules
        priority              = if ($execution.PSObject.Properties.Name -contains 'priority') { [int]$execution.priority } else { 0 }
    }
}

function Get-BackupPrimaryTimedAssetId {
    [CmdletBinding()]
    param(
        [object]$Payload
    )

    if (-not $Payload -or -not $Payload.chunkPlan -or -not $Payload.chunkPlan.assets) {
        return $null
    }

    $asset = @($Payload.chunkPlan.assets |
        Where-Object {
            [bool]$_.chunkable -and
            ([string]$_.mediaType -eq 'Video' -or
                ($_.PSObject.Properties.Name -contains 'durationSeconds' -and $null -ne $_.durationSeconds))
        } |
        Sort-Object `
            @{ Expression = { if ($null -ne $_.durationSeconds) { [double]$_.durationSeconds } else { 0.0 } }; Descending = $true },
            @{ Expression = { if ($null -ne $_.sizeBytes) { [int64]$_.sizeBytes } else { [int64]0 } }; Descending = $true },
            id |
        Select-Object -First 1)

    if ($asset.Count -eq 0) {
        return $null
    }

    return [string]$asset[0].id
}

function New-BackupCommandSchedulerMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Command,
        [Parameter(Mandatory)]
        [object]$Profile,
        [string]$PrimaryAssetId,
        [Parameter(Mandatory)]
        [object]$SchedulerExecution
    )

    $commandType = [string]$Command.type
    $assetId = [string]$Command.assetId
    $isPrimaryAsset = -not [string]::IsNullOrWhiteSpace($PrimaryAssetId) -and $assetId -eq $PrimaryAssetId
    $usesGpu = [string]$Profile.encoderDevice -ne 'CPU'

    switch ($commandType) {
        'EncodeChunk' {
            $lane = if ($isPrimaryAsset) { 'PrimaryVideo' } else { 'SecondaryMedia' }
            $resourceClass = if ($usesGpu) { 'GpuEncode' } else { 'CpuEncode' }
            $priority = if ($isPrimaryAsset) { 100 } else { 70 }
            $laneWorkerLimit = if ($usesGpu) {
                [int]$SchedulerExecution.gpuWorkerLimit
            }
            else {
                [int]$SchedulerExecution.cpuWorkerLimit
            }
            $maxConcurrentPerAsset = if ($isPrimaryAsset) { 1 } else { [Math]::Max(1, [Math]::Min(2, $laneWorkerLimit)) }
            $diskWeight = 2
        }
        'MergeAssetChunks' {
            $lane = 'DiskMerge'
            $resourceClass = 'DiskHeavy'
            $priority = 50
            $laneWorkerLimit = [int]$SchedulerExecution.diskWorkerLimit
            $maxConcurrentPerAsset = 1
            $diskWeight = 3
        }
        'CreateProxy' {
            $lane = 'DerivativeMedia'
            $resourceClass = 'CpuEncode'
            $priority = 30
            $laneWorkerLimit = [Math]::Max(1, [Math]::Min([int]$SchedulerExecution.cpuWorkerLimit, 2))
            $maxConcurrentPerAsset = 1
            $diskWeight = 1
        }
        'CreatePreview' {
            $lane = 'DerivativeImage'
            $resourceClass = 'CpuLight'
            $priority = 20
            $laneWorkerLimit = [Math]::Max(1, [Math]::Min([int]$SchedulerExecution.cpuWorkerLimit, 2))
            $maxConcurrentPerAsset = 1
            $diskWeight = 1
        }
        default {
            $lane = 'Utility'
            $resourceClass = 'CpuLight'
            $priority = 10
            $laneWorkerLimit = [int]$SchedulerExecution.maxWorkers
            $maxConcurrentPerAsset = 1
            $diskWeight = 1
        }
    }

    return [PSCustomObject]@{
        lane                  = $lane
        resourceClass         = $resourceClass
        priority              = $priority
        primaryAsset          = [bool]$isPrimaryAsset
        controlledMainVideo   = [bool]($commandType -eq 'EncodeChunk' -and $isPrimaryAsset)
        maxConcurrentPerAsset = [int]$maxConcurrentPerAsset
        laneWorkerLimit       = [Math]::Max(1, [Math]::Min([int]$SchedulerExecution.maxWorkers, [int]$laneWorkerLimit))
        diskWeight            = [int]$diskWeight
        cpuWeight             = if ($resourceClass -in @('CpuEncode', 'CpuLight')) { 1 } else { 0 }
        gpuWeight             = if ($resourceClass -eq 'GpuEncode') { 1 } else { 0 }
    }
}

function Set-BackupCommandSchedulerMetadata {
    [CmdletBinding()]
    param(
        [object[]]$Commands,
        [Parameter(Mandatory)]
        [object]$Profile,
        [string]$PrimaryAssetId,
        [Parameter(Mandatory)]
        [object]$SchedulerExecution
    )

    foreach ($command in @($Commands)) {
        $metadata = New-BackupCommandSchedulerMetadata `
            -Command $command `
            -Profile $Profile `
            -PrimaryAssetId $PrimaryAssetId `
            -SchedulerExecution $SchedulerExecution
        $command | Add-Member `
            -NotePropertyName scheduler `
            -NotePropertyValue $metadata `
            -Force
    }
}

function New-BackupSchedulerPlan {
    [CmdletBinding()]
    param(
        [object]$Payload,
        [Parameter(Mandatory)]
        [object]$Profile,
        [object[]]$Commands,
        [object[]]$Merges,
        [object[]]$ProxyCommands,
        [object[]]$PreviewCommands
    )

    $execution = Get-BackupSchedulerExecution -Payload $Payload
    $primaryAssetId = Get-BackupPrimaryTimedAssetId -Payload $Payload
    $allCommands = @($Commands) + @($Merges) + @($ProxyCommands) + @($PreviewCommands)
    Set-BackupCommandSchedulerMetadata `
        -Commands $allCommands `
        -Profile $Profile `
        -PrimaryAssetId $primaryAssetId `
        -SchedulerExecution $execution

    $laneGroups = @($allCommands | Group-Object { [string]$_.scheduler.lane })
    $lanes = [ordered]@{}
    foreach ($laneGroup in $laneGroups) {
        $sample = @($laneGroup.Group | Select-Object -First 1)
        $lanes[$laneGroup.Name] = [PSCustomObject]@{
            commandCount  = @($laneGroup.Group).Count
            maxConcurrent = if ($sample.Count -gt 0) { [int]$sample[0].scheduler.laneWorkerLimit } else { 1 }
            resourceClass = if ($sample.Count -gt 0) { [string]$sample[0].scheduler.resourceClass } else { 'Unknown' }
        }
    }

    if (-not $lanes.Contains('Checksum')) {
        $lanes['Checksum'] = [PSCustomObject]@{
            commandCount  = 0
            maxConcurrent = [int]$execution.diskWorkerLimit
            resourceClass = 'DiskRead'
            state         = 'ReadyForArchiveLayer'
        }
    }

    return [PSCustomObject]@{
        schemaVersion  = '1.0'
        enabled        = [int]$execution.maxWorkers -gt 1
        mode           = [string]$execution.mode
        primaryAssetId = $primaryAssetId
        workerPool     = [PSCustomObject]@{
            maxWorkers             = [int]$execution.maxWorkers
            cpuWorkers             = [int]$execution.cpuWorkerLimit
            gpuWorkers             = [int]$execution.gpuWorkerLimit
            diskWorkers            = [int]$execution.diskWorkerLimit
            mainVideoMaxConcurrent = 1
        }
        resourceLimits = [PSCustomObject]@{
            maxCpuPercent         = [int]$execution.maxCpuPercent
            maxGpuPercent         = [int]$execution.maxGpuPercent
            maxDiskActivePercent  = [int]$execution.maxDiskActivePercent
            maxTemperatureCelsius = [int]$execution.maxTemperatureCelsius
            diskPolicy            = 'LimitHeavyDiskStages'
            requireIdle           = [bool]$execution.requireIdle
            minIdleMinutes        = [int]$execution.minIdleMinutes
            allowedStartTime      = [string]$execution.allowedStartTime
            allowedEndTime        = [string]$execution.allowedEndTime
            systemRulePollSeconds = [int]$execution.systemRulePollSeconds
            allowOnBattery        = [bool]$execution.allowOnBattery
            thermalThrottleEnabled = [bool]$execution.thermalThrottleEnabled
        }
        systemRules    = $execution.systemRules
        priorities     = [PSCustomObject]@{
            primaryVideo   = 100
            secondaryMedia = 70
            merge          = 50
            proxy          = 30
            preview        = 20
            checksum       = 10
        }
        policy         = [PSCustomObject]@{
            primaryVideo = 'OneChunkAtATime'
            secondaryMedia = 'ParallelWithinWorkerPool'
            imagesAndPreviews = 'ParallelDerivativeLane'
            checksums     = 'ParallelDiskReadLane'
            overloadAction = 'ThrottleByLaneLimits'
        }
        lanes          = [PSCustomObject]$lanes
    }
}

function Get-BackupCommandProgressStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Command
    )

    switch ([string]$Command.type) {
        'EncodeChunk' {
            return [PSCustomObject]@{
                name        = 'Encoding'
                displayName = 'Encoding chunk'
                kind        = 'FfmpegTimedMedia'
                unit        = 'MediaTime'
            }
        }
        'MergeAssetChunks' {
            return [PSCustomObject]@{
                name        = 'Merging'
                displayName = 'Merging chunks'
                kind        = 'FfmpegContainer'
                unit        = 'Asset'
            }
        }
        'CreateProxy' {
            return [PSCustomObject]@{
                name        = 'CreatingProxy'
                displayName = 'Creating proxy'
                kind        = 'FfmpegTimedMedia'
                unit        = 'Asset'
            }
        }
        'CreatePreview' {
            return [PSCustomObject]@{
                name        = 'CreatingPreview'
                displayName = 'Creating preview'
                kind        = 'FfmpegTimedMedia'
                unit        = 'Asset'
            }
        }
        default {
            return [PSCustomObject]@{
                name        = 'Running'
                displayName = 'Running command'
                kind        = 'Command'
                unit        = 'Item'
            }
        }
    }
}

function Get-BackupCommandProgressLogPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [Parameter(Mandatory)]
        [string]$CommandId
    )

    $progressRoot = New-RenderKitStorageDirectory -Path (
        Join-Path -Path (Get-BackupJobStateRoot -JobId $JobId) -ChildPath 'progress'
    )

    return Join-Path -Path $progressRoot -ChildPath ("{0}.ffprogress.log" -f $CommandId)
}

function Get-BackupCommandProcessIdPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [Parameter(Mandatory)]
        [string]$CommandId
    )

    $progressRoot = New-RenderKitStorageDirectory -Path (
        Join-Path -Path (Get-BackupJobStateRoot -JobId $JobId) -ChildPath 'progress'
    )

    return Join-Path -Path $progressRoot -ChildPath ("{0}.pid" -f $CommandId)
}

function Set-BackupCommandProgressMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [object[]]$Commands,
        [ValidateRange(1, 100)]
        [int]$MaxAttemptsPerChunk = 3,
        [ValidateRange(0, 3600)]
        [int]$RetryDelaySeconds = 1
    )

    foreach ($command in @($Commands)) {
        $stage = Get-BackupCommandProgressStage -Command $command
        $logPath = Get-BackupCommandProgressLogPath `
            -JobId $JobId `
            -CommandId ([string]$command.id)
        $pidPath = Get-BackupCommandProcessIdPath `
            -JobId $JobId `
            -CommandId ([string]$command.id)
        $command | Add-Member `
            -NotePropertyName progress `
            -NotePropertyValue ([PSCustomObject]@{
                schemaVersion   = '1.0'
                stageName       = [string]$stage.name
                stageDisplayName = [string]$stage.displayName
                stageKind       = [string]$stage.kind
                unit            = [string]$stage.unit
                logPath         = $logPath
                pidPath         = $pidPath
                supportsFfmpegProgress = [string]$stage.kind -like 'Ffmpeg*'
                state           = 'Planned'
            }) `
            -Force
        $isRetryableChunk = [string]$command.type -eq 'EncodeChunk'
        $command | Add-Member `
            -NotePropertyName control `
            -NotePropertyValue ([PSCustomObject]@{
                schemaVersion     = '1.0'
                retryable         = [bool]$isRetryableChunk
                maxAttempts       = if ($isRetryableChunk) { [int]$MaxAttemptsPerChunk } else { 1 }
                attempts          = if ($command.PSObject.Properties.Name -contains 'attempts') { [int]$command.attempts } else { 0 }
                retryDelaySeconds = [int]$RetryDelaySeconds
                resumeMode        = 'SkipCompletedChunksFromChunkIndex'
                state             = [string]$command.state
            }) `
            -Force
    }
}

function Get-BackupCommandProcessId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Command
    )

    if (-not $Command.progress -or
        [string]::IsNullOrWhiteSpace([string]$Command.progress.pidPath) -or
        -not (Test-Path -LiteralPath ([string]$Command.progress.pidPath) -PathType Leaf)) {
        return $null
    }

    $text = Get-Content -LiteralPath ([string]$Command.progress.pidPath) -Raw -ErrorAction SilentlyContinue
    $pid = 0
    if ([int]::TryParse(([string]$text).Trim(), [ref]$pid) -and $pid -gt 0) {
        return $pid
    }

    return $null
}

function Invoke-BackupProcessControl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Pause', 'Resume', 'Stop')]
        [string]$Action,
        [Parameter(Mandatory)]
        [object[]]$Commands
    )

    $affected = New-Object System.Collections.Generic.List[int]
    foreach ($command in @($Commands)) {
        $pid = Get-BackupCommandProcessId -Command $command
        if ($null -eq $pid) {
            continue
        }

        $process = Get-Process -Id $pid -ErrorAction SilentlyContinue
        if (-not $process) {
            continue
        }

        if ($Action -eq 'Stop') {
            Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
            $affected.Add([int]$pid)
            continue
        }

        $commandName = if ($Action -eq 'Pause') { 'Suspend-Process' } else { 'Resume-Process' }
        if (Get-Command -Name $commandName -ErrorAction SilentlyContinue) {
            & $commandName -Id $pid -ErrorAction SilentlyContinue
            $affected.Add([int]$pid)
        }
    }

    return @($affected.ToArray())
}

function Get-BackupControlSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Job
    )

    $control = Read-BackupControlState -JobId ([string]$Job.id)
    $currentJob = Get-RenderKitJob -JobId ([string]$Job.id)
    $cancelRequested = $false
    if ($currentJob -and -not [string]::IsNullOrWhiteSpace([string]$currentJob.cancelRequestedAtUtc)) {
        $cancelRequested = $true
    }
    if ($cancelRequested -and [string]$control.requestedAction -ne 'Cancel') {
        $control.requestedAction = 'Cancel'
        $control.state = 'CancelRequested'
        if ([string]::IsNullOrWhiteSpace([string]$control.reason)) {
            $control.reason = [string]$currentJob.cancelReason
        }
        Save-BackupControlState `
            -JobId ([string]$Job.id) `
            -State $control |
            Out-Null
    }

    return $control
}

function Set-BackupControlRunning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [string]$Reason
    )

    $control = Read-BackupControlState -JobId $JobId
    $control.requestedAction = 'None'
    $control.state = 'Running'
    $control.reason = $Reason
    Save-BackupControlState -JobId $JobId -State $control | Out-Null
    return $control
}

function Stop-BackupJobForCancellation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Job,
        [string]$Reason = 'Backup job cancellation requested.',
        [object[]]$RunningCommands = @()
    )

    Invoke-BackupProcessControl `
        -Action Stop `
        -Commands $RunningCommands |
        Out-Null
    Update-BackupJobProgressSnapshot `
        -Job $Job `
        -StageName 'Cancelled' `
        -StageDisplayName 'Cancelled' `
        -Message $Reason `
        -Current 0 `
        -Total 0 |
        Out-Null
    Set-RenderKitJobStatus `
        -JobId ([string]$Job.id) `
        -Status Cancelled |
        Out-Null
}

function Wait-BackupJobControlRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Job,
        [object[]]$RunningCommands = @(),
        [string]$Phase = 'Paused',
        [string]$Message = 'Backup job paused.'
    )

    $pausedPids = @()
    while ($true) {
        $control = Get-BackupControlSnapshot -Job $Job
        if ([string]$control.requestedAction -eq 'Cancel') {
            Stop-BackupJobForCancellation `
                -Job $Job `
                -Reason $(if ($control.reason) { [string]$control.reason } else { 'Backup job cancellation requested.' }) `
                -RunningCommands $RunningCommands
            throw "Backup job '$($Job.id)' was cancelled."
        }

        if ([string]$control.requestedAction -ne 'Pause') {
            if (@($pausedPids).Count -gt 0) {
                Invoke-BackupProcessControl -Action Resume -Commands $RunningCommands | Out-Null
            }
            Set-BackupControlRunning `
                -JobId ([string]$Job.id) `
                -Reason $(if ([string]$control.requestedAction -eq 'Resume') { 'Backup job resumed.' } else { $null }) |
                Out-Null
            return
        }

        if (@($pausedPids).Count -eq 0) {
            $pausedPids = @(Invoke-BackupProcessControl -Action Pause -Commands $RunningCommands)
            $control.state = 'Paused'
            Save-BackupControlState -JobId ([string]$Job.id) -State $control | Out-Null
        }

        Update-BackupJobProgressSnapshot `
            -Job $Job `
            -StageName $Phase `
            -StageDisplayName 'Paused' `
            -Message $Message `
            -Current 0 `
            -Total 0 `
            -RunningCommands $RunningCommands |
            Out-Null
        Start-Sleep -Milliseconds 500
    }
}

function Wait-BackupSystemRulesRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Job,
        [object]$Rules,
        [object[]]$RunningCommands = @(),
        [ValidateRange(1, 64)]
        [int]$BaseWorkerLimit = 1,
        [string]$Phase = 'WaitingForSystemRules',
        [string]$Message = 'Waiting for system rules.'
    )

    $pausedForRules = $false
    while ($true) {
        $control = Get-BackupControlSnapshot -Job $Job
        if ([string]$control.requestedAction -eq 'Cancel') {
            Stop-BackupJobForCancellation `
                -Job $Job `
                -Reason $(if ($control.reason) { [string]$control.reason } else { 'Backup job cancellation requested.' }) `
                -RunningCommands $RunningCommands
            throw "Backup job '$($Job.id)' was cancelled."
        }
        if ([string]$control.requestedAction -eq 'Pause') {
            Wait-BackupJobControlRelease `
                -Job $Job `
                -RunningCommands $RunningCommands `
                -Phase $Phase `
                -Message 'Backup job paused.'
        }

        $decision = Test-RenderKitSystemRules `
            -Rules $Rules `
            -BaseWorkerLimit $BaseWorkerLimit

        if ([bool]$decision.canRun) {
            if ($pausedForRules) {
                Invoke-BackupProcessControl `
                    -Action Resume `
                    -Commands $RunningCommands |
                    Out-Null
            }
            if ([bool]$decision.shouldThrottle) {
                $throttledReasons = @($decision.throttledBy | ForEach-Object { [string]$_.reason })
                Update-BackupJobProgressSnapshot `
                    -Job $Job `
                    -StageName $Phase `
                    -StageDisplayName 'System rules throttled' `
                    -Message ("System rules throttled worker pool to {0}/{1}: {2}" -f [int]$decision.effectiveWorkerLimit, $BaseWorkerLimit, (($throttledReasons | Where-Object { $_ }) -join ', ')) `
                    -Current 0 `
                    -Total 0 `
                    -RunningCommands $RunningCommands |
                    Out-Null
            }
            return $decision
        }

        $blockedReasons = @($decision.blockedBy | ForEach-Object { [string]$_.reason })
        $reasonText = (($blockedReasons | Where-Object { $_ }) -join ', ')
        if ([string]::IsNullOrWhiteSpace($reasonText)) {
            $reasonText = 'SystemRuleBlocked'
        }

        if (@($RunningCommands).Count -gt 0 -and
            $Rules -and
            $Rules.PSObject.Properties.Name -contains 'throttling' -and
            $Rules.throttling -and
            [bool]$Rules.throttling.pauseWhenBlocked) {
            Invoke-BackupProcessControl `
                -Action Pause `
                -Commands $RunningCommands |
                Out-Null
            $pausedForRules = $true
        }

        Update-BackupJobProgressSnapshot `
            -Job $Job `
            -StageName $Phase `
            -StageDisplayName 'Waiting for system rules' `
            -Message ("{0}: {1}" -f $Message, $reasonText) `
            -Current 0 `
            -Total 0 `
            -RunningCommands $RunningCommands |
            Out-Null
        Start-Sleep -Seconds ([Math]::Max(1, [int]$decision.waitSeconds))
    }
}

function ConvertTo-BackupSpeedText {
    [CmdletBinding()]
    param(
        [Nullable[double]]$SpeedX,
        [Nullable[double]]$BytesPerSecond
    )

    if ($null -ne $SpeedX) {
        return (([double]$SpeedX).ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture) + 'x')
    }
    if ($null -ne $BytesPerSecond) {
        if ($BytesPerSecond -ge 1GB) {
            return ((([double]$BytesPerSecond / 1GB).ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture)) + ' GB/s')
        }
        if ($BytesPerSecond -ge 1MB) {
            return ((([double]$BytesPerSecond / 1MB).ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture)) + ' MB/s')
        }
        if ($BytesPerSecond -ge 1KB) {
            return ((([double]$BytesPerSecond / 1KB).ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture)) + ' KB/s')
        }
        return (([double]$BytesPerSecond).ToString('0', [System.Globalization.CultureInfo]::InvariantCulture) + ' B/s')
    }

    return $null
}

function Update-BackupFfmpegProgressAccumulator {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$State,
        [Parameter(Mandatory)]
        [string]$Line,
        [Nullable[double]]$DurationSeconds
    )

    $parsed = ConvertFrom-BackupFfmpegProgressLine `
        -Line $Line `
        -DurationSeconds $DurationSeconds
    if (-not $parsed) {
        return $null
    }

    $State[$parsed.key] = $parsed.value
    if ($null -ne $parsed.seconds) {
        $State.outTimeSeconds = [double]$parsed.seconds
    }
    if ($null -ne $parsed.percent) {
        $State.percent = [double]$parsed.percent
    }

    if ($parsed.key -eq 'speed') {
        $speedText = ([string]$parsed.value).Trim()
        $speedNumber = 0.0
        if ($speedText.EndsWith('x')) {
            $speedText = $speedText.Substring(0, $speedText.Length - 1)
        }
        if ([double]::TryParse(
                $speedText,
                [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$speedNumber)) {
            $State.speedX = [double]$speedNumber
        }
    }
    elseif ($parsed.key -eq 'total_size') {
        $size = [int64]0
        if ([int64]::TryParse([string]$parsed.value, [ref]$size)) {
            $State.totalSizeBytes = [int64]$size
        }
    }
    elseif ($parsed.key -eq 'bitrate') {
        $State.bitrate = [string]$parsed.value
    }

    $etaSeconds = $null
    if ($null -ne $DurationSeconds -and
        $DurationSeconds -gt 0 -and
        $State.ContainsKey('outTimeSeconds') -and
        $State.ContainsKey('speedX') -and
        [double]$State.speedX -gt 0) {
        $remainingMediaSeconds = [Math]::Max(0, [double]$DurationSeconds - [double]$State.outTimeSeconds)
        $etaSeconds = [Math]::Round($remainingMediaSeconds / [double]$State.speedX, 1)
    }

    return [PSCustomObject]@{
        key             = [string]$parsed.key
        value           = [string]$parsed.value
        seconds         = if ($State.ContainsKey('outTimeSeconds')) { [double]$State.outTimeSeconds } else { $null }
        durationSeconds = $DurationSeconds
        percent         = if ($State.ContainsKey('percent')) { [double]$State.percent } else { $null }
        speedX          = if ($State.ContainsKey('speedX')) { [double]$State.speedX } else { $null }
        speedText       = if ($State.ContainsKey('speedX')) { ConvertTo-BackupSpeedText -SpeedX ([double]$State.speedX) } else { $null }
        etaSeconds      = $etaSeconds
        totalSizeBytes  = if ($State.ContainsKey('totalSizeBytes')) { [int64]$State.totalSizeBytes } else { $null }
        bitrate         = if ($State.ContainsKey('bitrate')) { [string]$State.bitrate } else { $null }
        isTerminal      = [bool]$parsed.isTerminal
    }
}

function Read-BackupFfmpegProgressLogSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Command
    )

    if (-not $Command.progress -or
        -not [bool]$Command.progress.supportsFfmpegProgress -or
        [string]::IsNullOrWhiteSpace([string]$Command.progress.logPath) -or
        -not (Test-Path -LiteralPath ([string]$Command.progress.logPath) -PathType Leaf)) {
        return $null
    }

    $state = @{}
    $snapshot = $null
    foreach ($line in @(Get-Content -LiteralPath ([string]$Command.progress.logPath) -ErrorAction SilentlyContinue)) {
        $current = Update-BackupFfmpegProgressAccumulator `
            -State $state `
            -Line ([string]$line) `
            -DurationSeconds ([double]$Command.durationSeconds)
        if ($current) {
            $snapshot = $current
        }
    }

    return $snapshot
}

function New-BackupCopyProgressSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int64]$BytesCompleted,
        [Parameter(Mandatory)]
        [int64]$BytesTotal,
        [datetime]$StartedAtUtc = (Get-Date).ToUniversalTime()
    )

    $elapsedSeconds = [Math]::Max(0.001, ((Get-Date).ToUniversalTime() - $StartedAtUtc).TotalSeconds)
    $bytesPerSecond = [double]$BytesCompleted / $elapsedSeconds
    $percent = if ($BytesTotal -gt 0) {
        [Math]::Min(100, [Math]::Round(([double]$BytesCompleted / [double]$BytesTotal) * 100, 2))
    }
    else {
        $null
    }
    $etaSeconds = if ($BytesTotal -gt 0 -and $bytesPerSecond -gt 0) {
        [Math]::Round(([double]($BytesTotal - $BytesCompleted) / $bytesPerSecond), 1)
    }
    else {
        $null
    }

    return [PSCustomObject]@{
        bytesCompleted = [int64]$BytesCompleted
        bytesTotal     = [int64]$BytesTotal
        percent        = $percent
        bytesPerSecond = $bytesPerSecond
        speedText      = ConvertTo-BackupSpeedText -BytesPerSecond $bytesPerSecond
        etaSeconds     = $etaSeconds
    }
}

function New-BackupProgressSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [Parameter(Mandatory)]
        [string]$StageName,
        [string]$StageDisplayName,
        [string]$Message,
        [object]$Command,
        [int]$Current = 0,
        [int]$Total = 0,
        [Nullable[double]]$Percent,
        [object]$FfmpegProgress,
        [object]$CopyProgress,
        [object[]]$RunningCommands = @()
    )

    if ($null -eq $Percent -and $Total -gt 0) {
        $Percent = [Math]::Round(([double]$Current / [double]$Total) * 100, 2)
    }
    if ([string]::IsNullOrWhiteSpace($StageDisplayName)) {
        $StageDisplayName = $StageName
    }
    $activeCommands = @($RunningCommands | ForEach-Object {
            [PSCustomObject]@{
                id           = [string]$_.id
                type         = [string]$_.type
                assetId      = [string]$_.assetId
                chunkId      = [string]$_.chunkId
                relativePath = [string]$_.relativePath
                lane         = if ($_.scheduler) { [string]$_.scheduler.lane } else { $null }
            }
        })

    return [PSCustomObject]@{
        schemaVersion = '1.0'
        jobId         = $JobId
        updatedAtUtc  = (Get-Date).ToUniversalTime().ToString('o')
        stage         = [PSCustomObject]@{
            name        = $StageName
            displayName = $StageDisplayName
            message     = $Message
        }
        overall      = [PSCustomObject]@{
            current    = $Current
            total      = $Total
            percent    = $Percent
            etaSeconds = if ($FfmpegProgress -and $null -ne $FfmpegProgress.etaSeconds) { $FfmpegProgress.etaSeconds } elseif ($CopyProgress) { $CopyProgress.etaSeconds } else { $null }
            speedText  = if ($FfmpegProgress -and $FfmpegProgress.speedText) { [string]$FfmpegProgress.speedText } elseif ($CopyProgress) { [string]$CopyProgress.speedText } else { $null }
        }
        current      = [PSCustomObject]@{
            commandId       = if ($Command) { [string]$Command.id } else { $null }
            commandType     = if ($Command) { [string]$Command.type } else { $null }
            assetId         = if ($Command) { [string]$Command.assetId } else { $null }
            chunkId         = if ($Command) { [string]$Command.chunkId } else { $null }
            relativePath    = if ($Command) { [string]$Command.relativePath } else { $null }
            chunkIndex      = if ($Command -and $Command.PSObject.Properties.Name -contains 'index') { [int]$Command.index } else { $null }
            percent         = if ($FfmpegProgress -and $null -ne $FfmpegProgress.percent) { $FfmpegProgress.percent } elseif ($CopyProgress) { $CopyProgress.percent } else { $null }
            mediaTimeSeconds = if ($FfmpegProgress) { $FfmpegProgress.seconds } else { $null }
            durationSeconds = if ($FfmpegProgress) { $FfmpegProgress.durationSeconds } elseif ($Command -and $Command.PSObject.Properties.Name -contains 'durationSeconds') { $Command.durationSeconds } else { $null }
            etaSeconds      = if ($FfmpegProgress) { $FfmpegProgress.etaSeconds } elseif ($CopyProgress) { $CopyProgress.etaSeconds } else { $null }
            speedX          = if ($FfmpegProgress) { $FfmpegProgress.speedX } else { $null }
            speedText       = if ($FfmpegProgress -and $FfmpegProgress.speedText) { [string]$FfmpegProgress.speedText } elseif ($CopyProgress) { [string]$CopyProgress.speedText } else { $null }
            bytesCompleted  = if ($CopyProgress) { $CopyProgress.bytesCompleted } else { $null }
            bytesTotal      = if ($CopyProgress) { $CopyProgress.bytesTotal } else { $null }
        }
        chunks       = [PSCustomObject]@{
            completed = $Current
            total     = $Total
            active    = @($activeCommands)
        }
        copy         = $CopyProgress
    }
}

function Update-BackupJobProgressSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Job,
        [Parameter(Mandatory)]
        [string]$StageName,
        [string]$StageDisplayName,
        [string]$Message,
        [object]$Command,
        [int]$Current = 0,
        [int]$Total = 0,
        [Nullable[double]]$Percent,
        [object]$FfmpegProgress,
        [object]$CopyProgress,
        [object[]]$RunningCommands = @()
    )

    $snapshot = New-BackupProgressSnapshot `
        -JobId ([string]$Job.id) `
        -StageName $StageName `
        -StageDisplayName $StageDisplayName `
        -Message $Message `
        -Command $Command `
        -Current $Current `
        -Total $Total `
        -Percent $Percent `
        -FfmpegProgress $FfmpegProgress `
        -CopyProgress $CopyProgress `
        -RunningCommands $RunningCommands

    Save-BackupProgressState `
        -JobId ([string]$Job.id) `
        -State $snapshot |
        Out-Null

    Update-RenderKitJobProgress `
        -JobId ([string]$Job.id) `
        -Phase $StageName `
        -Message $Message `
        -Current $Current `
        -Total $Total `
        -Percent $snapshot.overall.percent |
        Out-Null

    return $snapshot
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

    $gpuCapabilities = $null
    try {
        $gpuCapabilities = Get-BackupGpuCapabilityReport
    }
    catch {
        $gpuCapabilities = New-BackupGpuCapabilityReport `
            -EncoderNames @() `
            -VideoControllerNames @() `
            -DetectedCommands @() `
            -Source 'Failed'
    }

    $profile = Get-BackupEncodingProfile `
        -CompressionPreset ([string]$Payload.archive.compressionPreset) `
        -VideoCodec ([string]$encoding.videoCodec) `
        -EncoderDevice ([string]$encoding.encoderDevice) `
        -QualityPreset ([string]$encoding.qualityPreset) `
        -AudioProfile ([string]$encoding.audioProfile) `
        -GpuCapabilities $gpuCapabilities
    $ffmpeg = Get-BackupFfmpegCommand
    $ffprobe = Get-BackupFfprobeCommand
    $commands = New-Object System.Collections.Generic.List[object]
    $merges = New-Object System.Collections.Generic.List[object]
    $proxyCommands = New-Object System.Collections.Generic.List[object]
    $previewCommands = New-Object System.Collections.Generic.List[object]
    $completedChunkIndex = Get-BackupCompletedChunkIndex -JobId ([string]$Job.id)
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
        $chunkState = 'Planned'
        $chunkAttempts = if ($chunk.PSObject.Properties.Name -contains 'attempts') { [int]$chunk.attempts } else { 0 }
        if ($completedChunkIndex.ContainsKey([string]$chunk.id)) {
            $completedEntry = $completedChunkIndex[[string]$chunk.id]
            if (-not [string]::IsNullOrWhiteSpace([string]$completedEntry.outputPath)) {
                $outputPath = [string]$completedEntry.outputPath
            }
            $chunkState = 'Completed'
            if ($completedEntry.PSObject.Properties.Name -contains 'attempts') {
                $chunkAttempts = [int]$completedEntry.attempts
            }
        }
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
            audioSync       = if ($chunk.PSObject.Properties.Name -contains 'audioSync') { $chunk.audioSync } else { $null }
            arguments       = @(New-BackupFfmpegChunkArguments `
                    -Chunk $chunk `
                    -Profile $profile `
                    -OutputPath $outputPath)
            state           = $chunkState
            attempts        = $chunkAttempts
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
        $mergeValidation = New-BackupMergeValidationExpectation `
            -Payload $Payload `
            -AssetId $assetId `
            -Commands @($group.Group) `
            -Profile $profile

        $merges.Add([PSCustomObject]@{
            id             = "merge-$assetId"
            type           = 'MergeAssetChunks'
            assetId        = $assetId
            chunkIds       = @($group.Group | Sort-Object index | ForEach-Object { [string]$_.chunkId })
            inputPaths     = @($group.Group | Sort-Object index | ForEach-Object { [string]$_.outputPath })
            concatListPath = $concatListPath
            outputPath     = $mergeOutput
            durationSeconds = [double]$mergeValidation.expectedDurationSeconds
            executable     = if ($ffmpeg) { [string]$ffmpeg.Source } else { 'ffmpeg' }
            arguments      = @('-hide_banner', '-y', '-f', 'concat', '-safe', '0', '-i', $concatListPath, '-c', 'copy', '-progress', 'pipe:1', '-nostats', $mergeOutput)
            validation     = $mergeValidation
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
                durationSeconds = [double]$merge.validation.expectedDurationSeconds
                executable = if ($ffmpeg) { [string]$ffmpeg.Source } else { 'ffmpeg' }
                arguments  = @(
                    '-hide_banner', '-y',
                    '-i', [string]$merge.outputPath,
                    '-vf', ("scale=-2:{0}" -f $proxyHeight),
                    '-c:v', 'libx264',
                    '-preset', 'veryfast',
                    '-crf', '30',
                    '-an',
                    '-progress', 'pipe:1',
                    '-nostats',
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
                durationSeconds = [double]$merge.validation.expectedDurationSeconds
                executable = if ($ffmpeg) { [string]$ffmpeg.Source } else { 'ffmpeg' }
                arguments  = @(
                    '-hide_banner', '-y',
                    '-i', [string]$merge.outputPath,
                    '-vf', ("fps=1/{0},scale={1}:-2" -f $previewInterval, $previewWidth),
                    '-progress', 'pipe:1',
                    '-nostats',
                    $previewPattern
                )
                state      = 'Planned'
            })
        }
    }

    $qualityValidation = New-BackupQualityValidationPlan `
        -Payload $Payload `
        -Profile $profile `
        -Merges @($merges.ToArray()) `
        -FfmpegPath $(if ($ffmpeg) { [string]$ffmpeg.Source } else { 'ffmpeg' }) `
        -JobId ([string]$Job.id)
    $scheduler = New-BackupSchedulerPlan `
        -Payload $Payload `
        -Profile $profile `
        -Commands @($commands.ToArray()) `
        -Merges @($merges.ToArray()) `
        -ProxyCommands @($proxyCommands.ToArray()) `
        -PreviewCommands @($previewCommands.ToArray())
    Set-BackupCommandProgressMetadata `
        -JobId ([string]$Job.id) `
        -Commands (@($commands.ToArray()) + @($merges.ToArray()) + @($qualityValidation.decodeCommands) + @($qualityValidation.metricCommands | Where-Object { [string]$_.state -eq 'Planned' }) + @($proxyCommands.ToArray()) + @($previewCommands.ToArray())) `
        -MaxAttemptsPerChunk $(if ($Payload.control -and $Payload.control.retry -and $Payload.control.retry.maxAttemptsPerChunk) { [int]$Payload.control.retry.maxAttemptsPerChunk } else { 3 }) `
        -RetryDelaySeconds $(if ($Payload.control -and $Payload.control.retry -and $Payload.control.retry.retryDelaySeconds) { [int]$Payload.control.retry.retryDelaySeconds } else { 1 })

    return [PSCustomObject]@{
        schemaVersion = '1.0'
        mode          = [string]$Payload.archive.mode
        ffmpeg        = [PSCustomObject]@{
            available = $null -ne $ffmpeg
            path      = if ($ffmpeg) { [string]$ffmpeg.Source } else { $null }
        }
        ffprobe       = [PSCustomObject]@{
            available = $null -ne $ffprobe
            path      = if ($ffprobe) { [string]$ffprobe.Source } else { $null }
        }
        profile       = $profile
        encoding      = $encoding
        gpuDetection  = [PSCustomObject]@{
            plan         = if ($encoding.PSObject.Properties.Name -contains 'gpuDetection') { $encoding.gpuDetection } else { $null }
            capabilities = $gpuCapabilities
            selection    = $profile.encoderSelection
        }
        qualityValidation = $qualityValidation
        scheduler     = $scheduler
        summary       = [PSCustomObject]@{
            commandCount        = [int]$commands.Count
            mergeCount          = [int]$merges.Count
            mergeValidationCount = [int]$merges.Count
            qualitySampleCount  = [int]$qualityValidation.summary.sampleCount
            qualityDecodeCommandCount = [int]$qualityValidation.summary.decodeCommandCount
            qualityMetricCommandCount = [int]$qualityValidation.summary.metricCommandCount
            proxyCommandCount   = [int]$proxyCommands.Count
            previewCommandCount = [int]$previewCommands.Count
            requiresFfmpeg      = ([int]$commands.Count + [int]$merges.Count + [int]$proxyCommands.Count + [int]$previewCommands.Count) -gt 0
            requiresFfprobe     = [int]$merges.Count -gt 0
        }
        commands      = @($commands.ToArray())
        merges        = @($merges.ToArray())
        qualityDecodeCommands = @($qualityValidation.decodeCommands)
        qualityMetricCommands = @($qualityValidation.metricCommands)
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

function Test-BackupMergeProbeMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$MergeCommand,
        [Parameter(Mandatory)]
        [object]$Metadata
    )

    $validation = $MergeCommand.validation
    $failures = New-Object System.Collections.Generic.List[string]
    $videoStreams = @(Get-BackupMetadataStreamList -Metadata $Metadata -PropertyName videoStreams)
    $audioStreams = @(Get-BackupMetadataStreamList -Metadata $Metadata -PropertyName audioStreams)
    $format = if ($Metadata -and $Metadata.PSObject.Properties.Name -contains 'format') {
        [string]$Metadata.format
    }
    else {
        $null
    }
    $actualDuration = if ($Metadata -and $Metadata.PSObject.Properties.Name -contains 'durationSeconds' -and $null -ne $Metadata.durationSeconds) {
        [double]$Metadata.durationSeconds
    }
    else {
        $null
    }
    $expectedDuration = if ($validation -and $validation.PSObject.Properties.Name -contains 'expectedDurationSeconds' -and $null -ne $validation.expectedDurationSeconds) {
        [double]$validation.expectedDurationSeconds
    }
    else {
        $null
    }
    $durationTolerance = if ($validation -and $validation.PSObject.Properties.Name -contains 'durationToleranceSeconds' -and $null -ne $validation.durationToleranceSeconds) {
        [double]$validation.durationToleranceSeconds
    }
    else {
        1.0
    }
    $durationDrift = $null

    if ([string]::IsNullOrWhiteSpace($format)) {
        $failures.Add('container format was not reported by ffprobe.')
    }
    if ($null -ne $expectedDuration -and $expectedDuration -gt 0) {
        if ($null -eq $actualDuration) {
            $failures.Add('merged duration was not reported by ffprobe.')
        }
        else {
            $durationDrift = [Math]::Round(($actualDuration - $expectedDuration), 3)
            if ([Math]::Abs([double]$durationDrift) -gt $durationTolerance) {
                $failures.Add(
                    "duration drift $durationDrift seconds exceeds tolerance $durationTolerance seconds."
                )
            }
        }
    }

    $expectedVideo = $validation -and
        $validation.PSObject.Properties.Name -contains 'expectedVideo' -and
        [bool]$validation.expectedVideo
    $expectedAudio = $validation -and
        $validation.PSObject.Properties.Name -contains 'expectedAudio' -and
        [bool]$validation.expectedAudio

    if ($expectedVideo -and @($videoStreams).Count -eq 0) {
        $failures.Add('expected video stream is missing.')
    }
    if ($expectedAudio -and @($audioStreams).Count -eq 0) {
        $failures.Add('expected audio stream is missing.')
    }

    if ($failures.Count -gt 0) {
        throw "Merged asset validation failed for '$($MergeCommand.assetId)': $($failures -join ' ')"
    }

    return [PSCustomObject]@{
        assetId     = [string]$MergeCommand.assetId
        outputPath  = [string]$MergeCommand.outputPath
        succeeded   = $true
        checkedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        container   = [PSCustomObject]@{
            status = 'Passed'
            format = $format
        }
        sync        = [PSCustomObject]@{
            status                   = 'Passed'
            expectedDurationSeconds  = $expectedDuration
            actualDurationSeconds    = $actualDuration
            durationDriftSeconds     = $durationDrift
            durationToleranceSeconds = $durationTolerance
        }
        streams     = [PSCustomObject]@{
            status        = 'Passed'
            expectedVideo = [bool]$expectedVideo
            expectedAudio = [bool]$expectedAudio
            videoCount    = @($videoStreams).Count
            audioCount    = @($audioStreams).Count
            video         = @($videoStreams)
            audio         = @($audioStreams)
        }
    }
}

function Test-BackupMergedAsset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$MergeCommand,
        [Parameter(Mandatory)]
        [object]$FfprobeCommand
    )

    if (-not (Test-Path -LiteralPath ([string]$MergeCommand.outputPath) -PathType Leaf)) {
        throw "Merged asset '$($MergeCommand.outputPath)' was not created."
    }
    if (-not $FfprobeCommand -or [string]::IsNullOrWhiteSpace([string]$FfprobeCommand.Source)) {
        throw 'ffprobe executable was not found.'
    }
    if (-not (Test-Path -LiteralPath ([string]$FfprobeCommand.Source) -PathType Leaf)) {
        throw "ffprobe executable '$($FfprobeCommand.Source)' was not found."
    }

    $probe = Invoke-BackupFfprobe `
        -Path ([string]$MergeCommand.outputPath) `
        -Command $FfprobeCommand
    if (-not [bool]$probe.succeeded) {
        throw "Merged asset validation failed for '$($MergeCommand.assetId)': $($probe.error)"
    }

    $metadata = ConvertTo-BackupMediaProbeMetadata -ProbeData $probe.data
    return Test-BackupMergeProbeMetadata `
        -MergeCommand $MergeCommand `
        -Metadata $metadata
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

function Sort-BackupScheduledCommand {
    [CmdletBinding()]
    param(
        [object[]]$Commands
    )

    return @($Commands | Sort-Object `
            @{ Expression = { if ($_.scheduler) { [int]$_.scheduler.priority } else { 0 } }; Descending = $true },
            @{ Expression = { if ($_.scheduler) { [string]$_.scheduler.lane } else { '' } } },
            assetId,
            index,
            id)
}

function Test-BackupScheduledCommandCanStart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Command,
        [object[]]$RunningCommands
    )

    if (-not $Command.scheduler) {
        return $true
    }

    $lane = [string]$Command.scheduler.lane
    $assetId = [string]$Command.assetId
    $laneLimit = [Math]::Max(1, [int]$Command.scheduler.laneWorkerLimit)
    $assetLimit = [Math]::Max(1, [int]$Command.scheduler.maxConcurrentPerAsset)
    $runningInLane = @($RunningCommands | Where-Object {
            $_.scheduler -and [string]$_.scheduler.lane -eq $lane
        }).Count
    $runningForAsset = @($RunningCommands | Where-Object {
            [string]$_.assetId -eq $assetId
        }).Count

    return $runningInLane -lt $laneLimit -and $runningForAsset -lt $assetLimit
}

function Select-BackupScheduledCommand {
    [CmdletBinding()]
    param(
        [object[]]$PendingCommands,
        [object[]]$RunningCommands
    )

    foreach ($candidate in @(Sort-BackupScheduledCommand -Commands $PendingCommands)) {
        if (Test-BackupScheduledCommandCanStart `
                -Command $candidate `
                -RunningCommands $RunningCommands) {
            return $candidate
        }
    }

    return $null
}

function Get-BackupScheduledCommandAttempts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Command
    )

    if ($Command.control -and $Command.control.PSObject.Properties.Name -contains 'attempts') {
        return [int]$Command.control.attempts
    }
    if ($Command.PSObject.Properties.Name -contains 'attempts') {
        return [int]$Command.attempts
    }

    return 0
}

function Set-BackupScheduledCommandState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Command,
        [Parameter(Mandatory)]
        [ValidateSet('Planned', 'Running', 'Completed', 'Failed', 'RetryScheduled', 'Skipped')]
        [string]$State,
        [Nullable[int]]$Attempts
    )

    $Command | Add-Member -NotePropertyName state -NotePropertyValue $State -Force
    if ($Command.progress) {
        $Command.progress.state = $State
    }
    if ($Command.control) {
        $Command.control.state = $State
        if ($null -ne $Attempts) {
            $Command.control.attempts = [int]$Attempts
        }
    }
    if ($null -ne $Attempts) {
        $Command | Add-Member -NotePropertyName attempts -NotePropertyValue ([int]$Attempts) -Force
    }
}

function Start-BackupScheduledCommandAttempt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Job,
        [Parameter(Mandatory)]
        [object]$Command
    )

    $attempts = (Get-BackupScheduledCommandAttempts -Command $Command) + 1
    Set-BackupScheduledCommandState -Command $Command -State Running -Attempts $attempts
    if ([string]$Command.type -eq 'EncodeChunk') {
        Update-BackupChunkIndexEntry `
            -JobId ([string]$Job.id) `
            -ChunkId ([string]$Command.chunkId) `
            -State Running `
            -OutputPath ([string]$Command.outputPath) `
            -Attempts $attempts |
            Out-Null
    }

    return $attempts
}

function Complete-BackupScheduledCommandAttempt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Job,
        [Parameter(Mandatory)]
        [object]$Command
    )

    $attempts = Get-BackupScheduledCommandAttempts -Command $Command
    Set-BackupScheduledCommandState -Command $Command -State Completed -Attempts $attempts
    if ([string]$Command.type -eq 'EncodeChunk') {
        Update-BackupChunkIndexEntry `
            -JobId ([string]$Job.id) `
            -ChunkId ([string]$Command.chunkId) `
            -State Completed `
            -OutputPath ([string]$Command.outputPath) `
            -Attempts $attempts |
            Out-Null
    }
}

function Fail-BackupScheduledCommandAttempt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Job,
        [Parameter(Mandatory)]
        [object]$Command,
        [Parameter(Mandatory)]
        [ValidateSet('Failed', 'RetryScheduled')]
        [string]$State,
        [string]$ErrorMessage
    )

    $attempts = Get-BackupScheduledCommandAttempts -Command $Command
    Set-BackupScheduledCommandState -Command $Command -State $State -Attempts $attempts
    if ([string]$Command.type -eq 'EncodeChunk') {
        Update-BackupChunkIndexEntry `
            -JobId ([string]$Job.id) `
            -ChunkId ([string]$Command.chunkId) `
            -State $State `
            -OutputPath ([string]$Command.outputPath) `
            -Attempts $attempts `
            -ErrorMessage $ErrorMessage |
            Out-Null
    }
}

function Test-BackupScheduledCommandCanRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Command
    )

    if (-not $Command.control -or -not [bool]$Command.control.retryable) {
        return $false
    }

    $attempts = Get-BackupScheduledCommandAttempts -Command $Command
    $maxAttempts = if ($Command.control.maxAttempts) { [int]$Command.control.maxAttempts } else { 1 }
    return $attempts -lt $maxAttempts
}

function Get-BackupScheduledCommandRetryDelay {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Command
    )

    if ($Command.control -and $Command.control.retryDelaySeconds) {
        return [Math]::Max(0, [int]$Command.control.retryDelaySeconds)
    }

    return 0
}

function Invoke-BackupScheduledCommandSerial {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Job,
        [Parameter(Mandatory)]
        [object]$Command,
        [int]$Completed,
        [int]$Total,
        [string]$Phase,
        [string]$MessageVerb,
        [switch]$ParseProgress
    )

    $targetName = if (-not [string]::IsNullOrWhiteSpace([string]$Command.relativePath)) {
        [string]$Command.relativePath
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$Command.assetId)) {
        [string]$Command.assetId
    }
    else {
        [string]$Command.id
    }

    Update-BackupJobProgressSnapshot `
        -Job $Job `
        -StageName $Phase `
        -StageDisplayName $MessageVerb `
        -Message ("{0} {1}/{2}: {3}" -f $MessageVerb, ($Completed + 1), $Total, $targetName) `
        -Command $Command `
        -Current $Completed `
        -Total $Total |
        Out-Null

    $ffmpegProgressState = @{}
    Invoke-BackupFfmpegCommand -Command $Command -JobId ([string]$Job.id) |
        ForEach-Object {
            if ($ParseProgress) {
                $progress = Update-BackupFfmpegProgressAccumulator `
                    -State $ffmpegProgressState `
                    -Line ([string]$_) `
                    -DurationSeconds ([double]$Command.durationSeconds)
                if ($progress -and $null -ne $progress.percent) {
                    $overall = [Math]::Round(((($Completed + ($progress.percent / 100.0)) / $Total) * 100), 2)
                    Update-BackupJobProgressSnapshot `
                        -Job $Job `
                        -StageName $Phase `
                        -StageDisplayName $MessageVerb `
                        -Message ("{0} {1}/{2}: {3}" -f $MessageVerb, ($Completed + 1), $Total, $targetName) `
                        -Command $Command `
                        -Current $Completed `
                        -Total $Total `
                        -Percent $overall `
                        -FfmpegProgress $progress |
                        Out-Null
                }
            }
        }
}

function Start-BackupScheduledThreadJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Command
    )

    Start-ThreadJob `
        -Name ([string]$Command.id) `
        -ArgumentList $Command `
        -ScriptBlock {
            param($ScheduledCommand)

            function ConvertTo-BackupProcessArgumentText {
                param([string[]]$Arguments)

                $escaped = foreach ($argument in @($Arguments)) {
                    if ($argument -match '[\s"]') {
                        '"' + ($argument -replace '"', '\"') + '"'
                    }
                    else {
                        $argument
                    }
                }

                return ($escaped -join ' ')
            }

            $progressLogPath = if ($ScheduledCommand.progress -and $ScheduledCommand.progress.logPath) {
                [string]$ScheduledCommand.progress.logPath
            }
            else {
                $null
            }
            if (-not [string]::IsNullOrWhiteSpace($progressLogPath)) {
                $progressFolder = Split-Path -Path $progressLogPath -Parent
                if (-not [string]::IsNullOrWhiteSpace($progressFolder) -and
                    -not (Test-Path -LiteralPath $progressFolder -PathType Container)) {
                    New-Item -ItemType Directory -Path $progressFolder -Force | Out-Null
                }
                Set-Content -LiteralPath $progressLogPath -Value @() -Encoding UTF8
            }

            $pidPath = if ($ScheduledCommand.progress -and $ScheduledCommand.progress.pidPath) {
                [string]$ScheduledCommand.progress.pidPath
            }
            else {
                $null
            }

            $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
            $processInfo.FileName = [string]$ScheduledCommand.executable
            $processInfo.UseShellExecute = $false
            $processInfo.RedirectStandardOutput = $true
            $processInfo.RedirectStandardError = $true
            $processInfo.CreateNoWindow = $true
            try {
                foreach ($argument in @($ScheduledCommand.arguments)) {
                    $processInfo.ArgumentList.Add([string]$argument)
                }
            }
            catch {
                $processInfo.Arguments = ConvertTo-BackupProcessArgumentText -Arguments @($ScheduledCommand.arguments)
            }

            $process = [System.Diagnostics.Process]::new()
            $process.StartInfo = $processInfo
            $errorLines = New-Object System.Collections.Generic.List[string]
            $process.add_ErrorDataReceived({
                    param($sender, $eventArgs)
                    if (-not [string]::IsNullOrWhiteSpace($eventArgs.Data)) {
                        $errorLines.Add([string]$eventArgs.Data)
                    }
                })
            [void]$process.Start()
            if (-not [string]::IsNullOrWhiteSpace($pidPath)) {
                $pidFolder = Split-Path -Path $pidPath -Parent
                if (-not [string]::IsNullOrWhiteSpace($pidFolder) -and
                    -not (Test-Path -LiteralPath $pidFolder -PathType Container)) {
                    New-Item -ItemType Directory -Path $pidFolder -Force | Out-Null
                }
                Set-Content -LiteralPath $pidPath -Value ([string]$process.Id) -Encoding UTF8
            }
            $process.BeginErrorReadLine()

            $lines = New-Object System.Collections.Generic.List[string]
            while (-not $process.StandardOutput.EndOfStream) {
                $line = $process.StandardOutput.ReadLine()
                if ($null -eq $line) {
                    continue
                }
                $lines.Add([string]$line)
                if (-not [string]::IsNullOrWhiteSpace($progressLogPath)) {
                    Add-Content -LiteralPath $progressLogPath -Value ([string]$line) -Encoding UTF8
                }
            }
            $process.WaitForExit()

            [PSCustomObject]@{
                commandId = [string]$ScheduledCommand.id
                processId = [int]$process.Id
                exitCode  = [int]$process.ExitCode
                output    = @($lines.ToArray())
                error     = @($errorLines.ToArray())
            }
        }
}

function Invoke-BackupScheduledCommandBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Job,
        [object[]]$Commands,
        [Parameter(Mandatory)]
        [object]$Scheduler,
        [string]$Phase = 'Running',
        [string]$MessageVerb = 'Running command',
        [switch]$ParseProgress
    )

    $commandList = @(Sort-BackupScheduledCommand -Commands $Commands)
    $total = @($commandList).Count
    if ($total -eq 0) {
        return [PSCustomObject]@{
            completedCount = 0
            usedParallel   = $false
            workerLimit    = 0
            fallback       = $null
        }
    }

    $alreadyCompleted = @($commandList | Where-Object { [string]$_.state -eq 'Completed' })
    $commandsToRun = @($commandList | Where-Object { [string]$_.state -ne 'Completed' })
    $completedParallel = @($alreadyCompleted).Count
    if ($completedParallel -gt 0) {
        Update-BackupJobProgressSnapshot `
            -Job $Job `
            -StageName $Phase `
            -StageDisplayName $MessageVerb `
            -Message ("{0} resume skipped {1}/{2} already completed item(s)" -f $MessageVerb, $completedParallel, $total) `
            -Current $completedParallel `
            -Total $total `
            -Percent ([Math]::Round(([double]$completedParallel / [double]$total) * 100, 2)) |
            Out-Null
    }
    if (@($commandsToRun).Count -eq 0) {
        return [PSCustomObject]@{
            completedCount = $completedParallel
            skippedCount   = $completedParallel
            usedParallel   = $false
            workerLimit    = 0
            fallback       = 'AlreadyCompleted'
        }
    }

    $threadJobCommand = Get-Command -Name Start-ThreadJob -ErrorAction SilentlyContinue
    $workerLimit = if ($Scheduler -and $Scheduler.workerPool) {
        [Math]::Max(1, [int]$Scheduler.workerPool.maxWorkers)
    }
    else {
        1
    }
    $systemRules = if ($Scheduler -and $Scheduler.PSObject.Properties.Name -contains 'systemRules') {
        $Scheduler.systemRules
    }
    else {
        $null
    }
    $lastSystemRuleDecision = $null
    $canUseThreadJobs = $null -ne $threadJobCommand
    if (-not $canUseThreadJobs) {
        $completed = $completedParallel
        foreach ($command in @($commandsToRun)) {
            $done = $false
            while (-not $done) {
                Wait-BackupJobControlRelease `
                    -Job $Job `
                    -RunningCommands @() `
                    -Phase $Phase `
                    -Message ("{0} paused." -f $MessageVerb)
                $lastSystemRuleDecision = Wait-BackupSystemRulesRelease `
                    -Job $Job `
                    -Rules $systemRules `
                    -RunningCommands @() `
                    -BaseWorkerLimit 1 `
                    -Phase 'WaitingForSystemRules' `
                    -Message ("{0} waiting for system rules" -f $MessageVerb)
                Start-BackupScheduledCommandAttempt -Job $Job -Command $command | Out-Null
                try {
                    Invoke-BackupScheduledCommandSerial `
                        -Job $Job `
                        -Command $command `
                        -Completed $completed `
                        -Total $total `
                        -Phase $Phase `
                        -MessageVerb $MessageVerb `
                        -ParseProgress:$ParseProgress
                    Complete-BackupScheduledCommandAttempt -Job $Job -Command $command
                    $completed++
                    $done = $true
                    Update-BackupJobProgressSnapshot `
                        -Job $Job `
                        -StageName $Phase `
                        -StageDisplayName $MessageVerb `
                        -Message ("{0} complete {1}/{2}" -f $MessageVerb, $completed, $total) `
                        -Command $command `
                        -Current $completed `
                        -Total $total `
                        -Percent ([Math]::Round(([double]$completed / [double]$total) * 100, 2)) |
                        Out-Null
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    if (Test-BackupScheduledCommandCanRetry -Command $command) {
                        Fail-BackupScheduledCommandAttempt `
                            -Job $Job `
                            -Command $command `
                            -State RetryScheduled `
                            -ErrorMessage $errorMessage
                        Update-BackupJobProgressSnapshot `
                            -Job $Job `
                            -StageName $Phase `
                            -StageDisplayName $MessageVerb `
                            -Message ("{0} retry scheduled for {1} after attempt {2}" -f $MessageVerb, [string]$command.id, (Get-BackupScheduledCommandAttempts -Command $command)) `
                            -Command $command `
                            -Current $completed `
                            -Total $total |
                            Out-Null
                        $delay = Get-BackupScheduledCommandRetryDelay -Command $command
                        if ($delay -gt 0) {
                            Start-Sleep -Seconds $delay
                        }
                        Set-BackupScheduledCommandState -Command $command -State Planned -Attempts (Get-BackupScheduledCommandAttempts -Command $command)
                        continue
                    }

                    Fail-BackupScheduledCommandAttempt `
                        -Job $Job `
                        -Command $command `
                        -State Failed `
                        -ErrorMessage $errorMessage
                    throw
                }
            }
        }

        return [PSCustomObject]@{
            completedCount = $completed
            skippedCount   = $completedParallel
            usedParallel   = $false
            workerLimit    = 1
            systemRules    = [PSCustomObject]@{
                enforced     = $null -ne $systemRules
                lastDecision = $lastSystemRuleDecision
            }
            fallback       = 'StartThreadJobUnavailable'
        }
    }

    $pending = [System.Collections.ArrayList]::new()
    foreach ($command in @($commandsToRun)) {
        [void]$pending.Add($command)
    }
    $running = @{}

    try {
        while ($pending.Count -gt 0 -or $running.Count -gt 0) {
            Wait-BackupJobControlRelease `
                -Job $Job `
                -RunningCommands @($running.Values | ForEach-Object { $_.command }) `
                -Phase $Phase `
                -Message ("{0} paused." -f $MessageVerb)
            $lastSystemRuleDecision = Wait-BackupSystemRulesRelease `
                -Job $Job `
                -Rules $systemRules `
                -RunningCommands @($running.Values | ForEach-Object { $_.command }) `
                -BaseWorkerLimit $workerLimit `
                -Phase 'WaitingForSystemRules' `
                -Message ("{0} waiting for system rules" -f $MessageVerb)
            $effectiveWorkerLimit = [Math]::Max(1, [int]$lastSystemRuleDecision.effectiveWorkerLimit)

            while ($pending.Count -gt 0 -and $running.Count -lt $effectiveWorkerLimit) {
                $next = Select-BackupScheduledCommand `
                    -PendingCommands @($pending) `
                    -RunningCommands @($running.Values | ForEach-Object { $_.command })
                if (-not $next) {
                    break
                }

                [void]$pending.Remove($next)
                Start-BackupScheduledCommandAttempt -Job $Job -Command $next | Out-Null
                $startedJob = Start-BackupScheduledThreadJob -Command $next
                $running[[string]$startedJob.Id] = [PSCustomObject]@{
                    job     = $startedJob
                    command = $next
                }
                Update-BackupJobProgressSnapshot `
                    -Job $Job `
                    -StageName $Phase `
                    -StageDisplayName $MessageVerb `
                    -Message ("{0} running {1}/{2} with {3}/{4} worker(s)" -f $MessageVerb, $completedParallel, $total, $running.Count, $effectiveWorkerLimit) `
                    -Command $next `
                    -Current $completedParallel `
                    -Total $total `
                    -RunningCommands @($running.Values | ForEach-Object { $_.command }) |
                    Out-Null
            }

            if ($running.Count -eq 0) {
                if ($pending.Count -gt 0) {
                    throw "No schedulable backup command was found for phase '$Phase'."
                }
                break
            }

            $finishedJob = Wait-Job -Job @($running.Values | ForEach-Object { $_.job }) -Any -Timeout 1
            if (-not $finishedJob) {
                $runningCommands = @($running.Values | ForEach-Object { $_.command })
                $activeProgress = @($runningCommands |
                    ForEach-Object { Read-BackupFfmpegProgressLogSnapshot -Command $_ } |
                    Where-Object { $null -ne $_ })
                $activeProgressFraction = 0.0
                foreach ($progress in @($activeProgress)) {
                    if ($null -ne $progress.percent) {
                        $activeProgressFraction += ([double]$progress.percent / 100.0)
                    }
                }
                $overallPercent = if ($total -gt 0) {
                    [Math]::Round(((($completedParallel + $activeProgressFraction) / $total) * 100), 2)
                }
                else {
                    $null
                }
                $currentCommand = @($runningCommands | Select-Object -First 1)
                $currentProgress = @($activeProgress | Select-Object -First 1)
                Update-BackupJobProgressSnapshot `
                    -Job $Job `
                    -StageName $Phase `
                    -StageDisplayName $MessageVerb `
                    -Message ("{0} running {1}/{2} with {3}/{4} worker(s)" -f $MessageVerb, $completedParallel, $total, $running.Count, $effectiveWorkerLimit) `
                    -Command $(if ($currentCommand.Count -gt 0) { $currentCommand[0] } else { $null }) `
                    -Current $completedParallel `
                    -Total $total `
                    -Percent $overallPercent `
                    -FfmpegProgress $(if ($currentProgress.Count -gt 0) { $currentProgress[0] } else { $null }) `
                    -RunningCommands $runningCommands |
                    Out-Null
                continue
            }
            foreach ($jobHandle in @($finishedJob)) {
                $key = [string]$jobHandle.Id
                $entry = $running[$key]
                $receiveError = $null
                $result = $null
                try {
                    $result = Receive-Job -Job $jobHandle -ErrorAction Stop
                }
                catch {
                    $receiveError = $_.Exception.Message
                }
                Remove-Job -Job $jobHandle -Force -ErrorAction SilentlyContinue
                $running.Remove($key)

                $resultItems = @($result)
                $resultObject = if ($resultItems.Count -gt 0) { $resultItems[$resultItems.Count - 1] } else { $null }
                $exitCode = if ($resultObject -and $null -ne $resultObject.exitCode) { [int]$resultObject.exitCode } else { 1 }
                if (-not [string]::IsNullOrWhiteSpace($receiveError) -or -not $resultObject -or $exitCode -ne 0) {
                    $errorMessage = if (-not [string]::IsNullOrWhiteSpace($receiveError)) {
                        $receiveError
                    }
                    elseif ($resultObject -and $resultObject.error -and @($resultObject.error).Count -gt 0) {
                        (@($resultObject.error) -join [Environment]::NewLine)
                    }
                    else {
                        "ffmpeg command '$($entry.command.id)' failed with exit code $exitCode."
                    }

                    if (Test-BackupScheduledCommandCanRetry -Command $entry.command) {
                        Fail-BackupScheduledCommandAttempt `
                            -Job $Job `
                            -Command $entry.command `
                            -State RetryScheduled `
                            -ErrorMessage $errorMessage
                        Update-BackupJobProgressSnapshot `
                            -Job $Job `
                            -StageName $Phase `
                            -StageDisplayName $MessageVerb `
                            -Message ("{0} retry scheduled for {1} after attempt {2}" -f $MessageVerb, [string]$entry.command.id, (Get-BackupScheduledCommandAttempts -Command $entry.command)) `
                            -Command $entry.command `
                            -Current $completedParallel `
                            -Total $total `
                            -RunningCommands @($running.Values | ForEach-Object { $_.command }) |
                            Out-Null
                        $delay = Get-BackupScheduledCommandRetryDelay -Command $entry.command
                        if ($delay -gt 0) {
                            Start-Sleep -Seconds $delay
                        }
                        Set-BackupScheduledCommandState -Command $entry.command -State Planned -Attempts (Get-BackupScheduledCommandAttempts -Command $entry.command)
                        [void]$pending.Add($entry.command)
                        continue
                    }

                    Fail-BackupScheduledCommandAttempt `
                        -Job $Job `
                        -Command $entry.command `
                        -State Failed `
                        -ErrorMessage $errorMessage
                    throw $errorMessage
                }

                Complete-BackupScheduledCommandAttempt -Job $Job -Command $entry.command
                $completedParallel++
                Update-BackupJobProgressSnapshot `
                    -Job $Job `
                    -StageName $Phase `
                    -StageDisplayName $MessageVerb `
                    -Message ("{0} complete {1}/{2}" -f $MessageVerb, $completedParallel, $total) `
                    -Command $entry.command `
                    -Current $completedParallel `
                    -Total $total `
                    -Percent ([Math]::Round(([double]$completedParallel / [double]$total) * 100, 2)) `
                    -RunningCommands @($running.Values | ForEach-Object { $_.command }) |
                    Out-Null
            }
        }
    }
    catch {
        foreach ($entry in @($running.Values)) {
            if ($entry.job) {
                Remove-Job -Job $entry.job -Force -ErrorAction SilentlyContinue
            }
        }
        throw
    }

    return [PSCustomObject]@{
        completedCount = $completedParallel
        skippedCount   = @($alreadyCompleted).Count
        usedParallel   = $true
        workerLimit    = $workerLimit
        effectiveWorkerLimit = if ($lastSystemRuleDecision) { [int]$lastSystemRuleDecision.effectiveWorkerLimit } else { $workerLimit }
        systemRules    = [PSCustomObject]@{
            enforced     = $null -ne $systemRules
            lastDecision = $lastSystemRuleDecision
        }
        fallback       = if ($workerLimit -le 1) { 'SingleWorkerThreadJob' } else { $null }
    }
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
        Update-BackupJobProgressSnapshot `
            -Job $Job `
            -StageName 'EncodingSkipped' `
            -StageDisplayName 'Encoding skipped' `
            -Message 'No chunkable media requires encoding.' `
            -Current 0 `
            -Total 0 `
            -Percent 100 |
            Out-Null
        return [PSCustomObject]@{
            encodedChunkCount          = 0
            mergedAssetCount           = 0
            mergeValidationCount       = 0
            mergeValidationFailedCount = 0
            mergeValidations           = @()
            qualityValidationCount     = 0
            qualityValidationFailedCount = 0
            qualityValidations         = @()
            qualityValidation          = [PSCustomObject]@{
                state   = 'Skipped'
                passed  = $true
                reason  = 'EncodingSkipped'
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

    if (-not [bool]$Plan.ffmpeg.available) {
        throw 'ffmpeg was not found. Install ffmpeg or run the backup without TranscodeAndArchive mode.'
    }
    if ([bool]$Plan.summary.requiresFfprobe -and -not [bool]$Plan.ffprobe.available) {
        throw 'ffprobe was not found. Install ffprobe to validate merged backup media.'
    }

    $encodeSchedule = Invoke-BackupScheduledCommandBatch `
        -Job $Job `
        -Commands @($Plan.commands) `
        -Scheduler $Plan.scheduler `
        -Phase 'Encoding' `
        -MessageVerb 'Encoding chunk' `
        -ParseProgress
    $completed = [int]$encodeSchedule.completedCount

    $mergeValidations = New-Object System.Collections.Generic.List[object]
    $ffprobeCommand = if ([bool]$Plan.summary.requiresFfprobe) {
        [PSCustomObject]@{ Source = [string]$Plan.ffprobe.path }
    }
    else {
        $null
    }
    $mergeTotal = @($Plan.merges).Count
    $mergeCompleted = 0
    foreach ($merge in @($Plan.merges)) {
        Write-BackupConcatList -MergeCommand $merge
    }
    $mergeSchedule = Invoke-BackupScheduledCommandBatch `
        -Job $Job `
        -Commands @($Plan.merges) `
        -Scheduler $Plan.scheduler `
        -Phase 'Merging' `
        -MessageVerb 'Merging asset'

    foreach ($merge in @(Sort-BackupScheduledCommand -Commands @($Plan.merges))) {
        Update-BackupJobProgressSnapshot `
            -Job $Job `
            -StageName 'ValidatingMerge' `
            -StageDisplayName 'Validating merged asset' `
            -Message ("Validating merged asset {0}/{1}: {2}" -f ($mergeCompleted + 1), $mergeTotal, [string]$merge.assetId) `
            -Command $merge `
            -Current $mergeCompleted `
            -Total $mergeTotal |
            Out-Null

        $mergeValidations.Add(
            (Test-BackupMergedAsset `
                -MergeCommand $merge `
                -FfprobeCommand $ffprobeCommand)
        )
        $mergeCompleted++

        Update-BackupJobProgressSnapshot `
            -Job $Job `
            -StageName 'MergeValidated' `
            -StageDisplayName 'Merged asset validated' `
            -Message ("Validated merged asset {0}/{1}: {2}" -f $mergeCompleted, $mergeTotal, [string]$merge.assetId) `
            -Command $merge `
            -Current $mergeCompleted `
            -Total $mergeTotal |
            Out-Null
    }

    $qualityValidationResult = Invoke-BackupQualityValidationPlan `
        -Job $Job `
        -Plan $Plan.qualityValidation `
        -Scheduler $Plan.scheduler

    $proxySchedule = Invoke-BackupScheduledCommandBatch `
        -Job $Job `
        -Commands @($Plan.proxyCommands) `
        -Scheduler $Plan.scheduler `
        -Phase 'CreatingProxy' `
        -MessageVerb 'Creating proxy'
    $previewSchedule = Invoke-BackupScheduledCommandBatch `
        -Job $Job `
        -Commands @($Plan.previewCommands) `
        -Scheduler $Plan.scheduler `
        -Phase 'CreatingPreview' `
        -MessageVerb 'Creating preview'

    return [PSCustomObject]@{
        encodedChunkCount          = $completed
        mergedAssetCount           = @($Plan.merges).Count
        mergeValidationCount       = @($mergeValidations.ToArray()).Count
        mergeValidationFailedCount = 0
        mergeValidations           = @($mergeValidations.ToArray())
        qualityValidationCount     = @($qualityValidationResult.decodeResults).Count
        qualityValidationFailedCount = if ($qualityValidationResult.evaluation) { @($qualityValidationResult.evaluation.failedRules).Count } else { 0 }
        qualityValidations         = @($qualityValidationResult.decodeResults)
        qualityValidation          = $qualityValidationResult
        proxyAssetCount            = @($Plan.proxyCommands).Count
        previewAssetCount          = @($Plan.previewCommands).Count
        scheduler                  = [PSCustomObject]@{
            usedParallel = [bool]($encodeSchedule.usedParallel -or $mergeSchedule.usedParallel -or $qualityValidationResult.decodeSchedule.usedParallel -or $proxySchedule.usedParallel -or $previewSchedule.usedParallel)
            encode       = $encodeSchedule
            merge        = $mergeSchedule
            qualityValidation = $qualityValidationResult.decodeSchedule
            proxy        = $proxySchedule
            preview      = $previewSchedule
        }
        skipped                    = $false
    }
}
