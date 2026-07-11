function Get-BackupQualityObjectValue {
    [CmdletBinding()]
    param(
        [object]$InputObject,
        [Parameter(Mandatory)]
        [string]$Name,
        [object]$DefaultValue = $null
    )

    if ($null -eq $InputObject) {
        return $DefaultValue
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return $InputObject[$Name]
        }

        return $DefaultValue
    }
    if ($InputObject.PSObject.Properties.Name -contains $Name) {
        return $InputObject.$Name
    }

    return $DefaultValue
}

function Get-BackupQualityThresholdProfile {
    [CmdletBinding()]
    param(
        [ValidateSet('Draft', 'Balanced', 'High', 'Smallest', 'Lossless')]
        [string]$QualityPreset = 'Balanced'
    )

    $threshold = switch ($QualityPreset) {
        'Draft' {
            [PSCustomObject]@{
                minVmaf = 74.0
                minSsim = 0.900
                minPsnr = 30.0
                maxDecodeErrorCount = 0
            }
        }
        'High' {
            [PSCustomObject]@{
                minVmaf = 92.0
                minSsim = 0.965
                minPsnr = 38.0
                maxDecodeErrorCount = 0
            }
        }
        'Smallest' {
            [PSCustomObject]@{
                minVmaf = 82.0
                minSsim = 0.920
                minPsnr = 32.0
                maxDecodeErrorCount = 0
            }
        }
        'Lossless' {
            [PSCustomObject]@{
                minVmaf = 98.0
                minSsim = 0.995
                minPsnr = 50.0
                maxDecodeErrorCount = 0
            }
        }
        default {
            [PSCustomObject]@{
                minVmaf = 88.0
                minSsim = 0.940
                minPsnr = 34.0
                maxDecodeErrorCount = 0
            }
        }
    }

    return [PSCustomObject]@{
        schemaVersion = '1.0'
        profile       = $QualityPreset
        thresholds    = $threshold
        failureAction = 'FailJobBeforeArchive'
        scope         = 'EncodedMergedAssets'
    }
}

function New-BackupQualityValidationPolicy {
    [CmdletBinding()]
    param(
        [ValidateSet('Draft', 'Balanced', 'High', 'Smallest', 'Lossless')]
        [string]$QualityPreset = 'Balanced',
        [ValidateSet('ArchiveOnly', 'TranscodeAndArchive', 'ProxyOnly', 'CopyOnly')]
        [string]$CompressionMode = 'ArchiveOnly',
        [int]$SampleCount = 3,
        [int]$SampleDurationSeconds = 8,
        [string[]]$Metrics = @('VMAF', 'SSIM', 'PSNR')
    )

    $thresholdProfile = Get-BackupQualityThresholdProfile -QualityPreset $QualityPreset
    return [PSCustomObject]@{
        schemaVersion = '1.0'
        enabled       = $CompressionMode -in @('TranscodeAndArchive', 'ProxyOnly')
        state         = 'Planned'
        mode          = 'SampleDecodeWithOptionalMetrics'
        qualityPreset = $QualityPreset
        decode        = [PSCustomObject]@{
            enabled       = $true
            required      = $true
            sampleCount   = [Math]::Max(1, $SampleCount)
            sampleDurationSeconds = [Math]::Max(1, $SampleDurationSeconds)
            failureAction = 'FailJobBeforeArchive'
        }
        metrics       = [PSCustomObject]@{
            enabled       = $true
            required      = $false
            names         = @($Metrics)
            optionalWhenFilterMissing = $true
            blockWhenMeasuredBelowThreshold = $true
        }
        thresholds    = $thresholdProfile.thresholds
        report        = [PSCustomObject]@{
            includeSamples = $true
            includeMetrics = $true
            includeThresholds = $true
        }
    }
}

function ConvertFrom-BackupFfmpegFilterList {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string[]]$Text
    )

    $names = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($Text)) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $trimmed = ([string]$line).Trim()
        if ($trimmed -match '^[TSC\.A-Z]{3}\s+([A-Za-z0-9_]+)\s+') {
            $names.Add($Matches[1])
            continue
        }
        if ($trimmed -match '\b(libvmaf|ssim|psnr)\b') {
            $names.Add($Matches[1])
        }
    }

    return @(
        $names.ToArray() |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } |
            Sort-Object -Unique
    )
}

function Get-BackupFfmpegFilterNameList {
    [CmdletBinding()]
    param(
        [object]$FfmpegCommand
    )

    if (-not $FfmpegCommand) {
        $FfmpegCommand = Get-BackupFfmpegCommand
    }
    if (-not $FfmpegCommand -or [string]::IsNullOrWhiteSpace([string]$FfmpegCommand.Source)) {
        return @()
    }

    try {
        $output = & ([string]$FfmpegCommand.Source) -hide_banner -filters 2>&1
        return @(ConvertFrom-BackupFfmpegFilterList -Text @($output | ForEach-Object { [string]$_ }))
    }
    catch {
        return @()
    }
}

function New-BackupQualityValidationSamples {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AssetId,
        [Parameter(Mandatory)]
        [double]$DurationSeconds,
        [int]$SampleCount = 3,
        [int]$SampleDurationSeconds = 8
    )

    $effectiveSampleCount = [Math]::Max(1, $SampleCount)
    $effectiveSampleDuration = [Math]::Max(1.0, [double]$SampleDurationSeconds)
    $mediaDuration = [Math]::Max(0.0, $DurationSeconds)
    if ($mediaDuration -gt 0 -and $effectiveSampleDuration -gt $mediaDuration) {
        $effectiveSampleDuration = [Math]::Max(1.0, $mediaDuration)
    }

    $starts = New-Object System.Collections.Generic.List[double]
    if ($mediaDuration -le 0 -or $effectiveSampleCount -eq 1) {
        $starts.Add(0.0)
    }
    else {
        $maxStart = [Math]::Max(0.0, $mediaDuration - $effectiveSampleDuration)
        if ($effectiveSampleCount -eq 2) {
            $starts.Add(0.0)
            $starts.Add($maxStart)
        }
        else {
            $starts.Add(0.0)
            $starts.Add([Math]::Round($maxStart / 2.0, 3))
            $starts.Add($maxStart)
        }
    }

    $samples = New-Object System.Collections.Generic.List[object]
    $index = 0
    foreach ($start in @($starts.ToArray() | Select-Object -First $effectiveSampleCount)) {
        $samples.Add([PSCustomObject]@{
                id              = ("quality-{0}-{1:000}" -f $AssetId, $index)
                assetId         = $AssetId
                index           = $index
                startSeconds    = [Math]::Round([double]$start, 3)
                durationSeconds = [Math]::Round([double]$effectiveSampleDuration, 3)
            })
        $index++
    }

    return @($samples.ToArray())
}

function Get-BackupQualityMetricFilterName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('VMAF', 'SSIM', 'PSNR')]
        [string]$Metric
    )

    switch ($Metric) {
        'VMAF' { return 'libvmaf' }
        'SSIM' { return 'ssim' }
        'PSNR' { return 'psnr' }
    }
}

function New-BackupQualityMetricArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('VMAF', 'SSIM', 'PSNR')]
        [string]$Metric,
        [Parameter(Mandatory)]
        [object]$Sample,
        [Parameter(Mandatory)]
        [string]$OriginalPath,
        [Parameter(Mandatory)]
        [string]$EncodedPath,
        [string]$LogPath
    )

    $filter = switch ($Metric) {
        'VMAF' {
            if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
                "libvmaf=log_fmt=json:log_path=$LogPath"
            }
            else {
                'libvmaf'
            }
        }
        'SSIM' { 'ssim' }
        'PSNR' { 'psnr' }
    }

    return @(
        '-hide_banner',
        '-ss',
        (ConvertTo-BackupInvariantNumber -Value ([double]$Sample.startSeconds)),
        '-t',
        (ConvertTo-BackupInvariantNumber -Value ([double]$Sample.durationSeconds)),
        '-i',
        $OriginalPath,
        '-ss',
        (ConvertTo-BackupInvariantNumber -Value ([double]$Sample.startSeconds)),
        '-t',
        (ConvertTo-BackupInvariantNumber -Value ([double]$Sample.durationSeconds)),
        '-i',
        $EncodedPath,
        '-lavfi',
        ("[0:v][1:v]{0}" -f $filter),
        '-f',
        'null',
        '-'
    )
}

function New-BackupQualityValidationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Payload,
        [Parameter(Mandatory)]
        [object]$Profile,
        [object[]]$Merges = @(),
        [string[]]$AvailableFilters,
        [string]$FfmpegPath,
        [string]$JobId = 'quality'
    )

    $policy = if ($Payload.encoding -and
        $Payload.encoding.PSObject.Properties.Name -contains 'qualityValidation' -and
        $Payload.encoding.qualityValidation) {
        $Payload.encoding.qualityValidation
    }
    else {
        New-BackupQualityValidationPolicy `
            -QualityPreset ([string]$Profile.qualityPreset) `
            -CompressionMode ([string]$Payload.archive.mode)
    }

    $enabled = [bool](Get-BackupQualityObjectValue -InputObject $policy -Name 'enabled' -DefaultValue $false)
    $decode = Get-BackupQualityObjectValue -InputObject $policy -Name 'decode'
    $metrics = Get-BackupQualityObjectValue -InputObject $policy -Name 'metrics'
    $sampleCount = [int](Get-BackupQualityObjectValue -InputObject $decode -Name 'sampleCount' -DefaultValue 3)
    $sampleDuration = [int](Get-BackupQualityObjectValue -InputObject $decode -Name 'sampleDurationSeconds' -DefaultValue 8)
    $metricNames = @(
        Get-BackupQualityObjectValue -InputObject $metrics -Name 'names' -DefaultValue @('VMAF', 'SSIM', 'PSNR') |
            ForEach-Object { [string]$_ }
    )
    if ($null -eq $AvailableFilters) {
        $AvailableFilters = @(Get-BackupFfmpegFilterNameList)
    }
    $normalizedFilters = @(
        $AvailableFilters |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } |
            Sort-Object -Unique
    )

    $samples = New-Object System.Collections.Generic.List[object]
    $decodeCommands = New-Object System.Collections.Generic.List[object]
    $metricCommands = New-Object System.Collections.Generic.List[object]
    if ($enabled) {
        foreach ($merge in @($Merges)) {
            $asset = @(
                $Payload.chunkPlan.assets |
                    Where-Object { [string]$_.id -eq [string]$merge.assetId } |
                    Select-Object -First 1
            )
            $originalPath = if ($asset.Count -gt 0) { [string]$asset[0].path } else { $null }
            $encodedPath = [string]$merge.outputPath
            $durationSeconds = if ($merge.PSObject.Properties.Name -contains 'durationSeconds') {
                [double]$merge.durationSeconds
            }
            else {
                0.0
            }

            foreach ($sample in @(New-BackupQualityValidationSamples `
                        -AssetId ([string]$merge.assetId) `
                        -DurationSeconds $durationSeconds `
                        -SampleCount $sampleCount `
                        -SampleDurationSeconds $sampleDuration)) {
                $sample | Add-Member -NotePropertyName originalPath -NotePropertyValue $originalPath -Force
                $sample | Add-Member -NotePropertyName encodedPath -NotePropertyValue $encodedPath -Force
                $samples.Add($sample)

                $decodeCommands.Add([PSCustomObject]@{
                        id              = "quality-decode-$($sample.id)"
                        type            = 'QualityDecodeSample'
                        assetId         = [string]$merge.assetId
                        sampleId        = [string]$sample.id
                        inputPath       = $encodedPath
                        outputPath      = $null
                        startSeconds    = [double]$sample.startSeconds
                        durationSeconds = [double]$sample.durationSeconds
                        executable      = if ($FfmpegPath) { $FfmpegPath } else { 'ffmpeg' }
                        arguments       = @(
                            '-hide_banner',
                            '-v',
                            'error',
                            '-ss',
                            (ConvertTo-BackupInvariantNumber -Value ([double]$sample.startSeconds)),
                            '-t',
                            (ConvertTo-BackupInvariantNumber -Value ([double]$sample.durationSeconds)),
                            '-i',
                            $encodedPath,
                            '-map',
                            '0:v:0',
                            '-f',
                            'null',
                            '-'
                        )
                        scheduler       = [PSCustomObject]@{
                            lane     = 'QualityValidation'
                            priority = 80
                            weight   = 1
                        }
                        state           = 'Planned'
                    })

                foreach ($metric in @($metricNames)) {
                    if ([string]::IsNullOrWhiteSpace($metric)) {
                        continue
                    }

                    $metricName = ([string]$metric).Trim().ToUpperInvariant()
                    if ($metricName -notin @('VMAF', 'SSIM', 'PSNR')) {
                        continue
                    }

                    $filterName = Get-BackupQualityMetricFilterName -Metric $metricName
                    $filterAvailable = $normalizedFilters -contains $filterName.ToLowerInvariant()
                    $metricLogPath = Join-Path `
                        -Path (Get-BackupJobStateRoot -JobId $JobId) `
                        -ChildPath ("{0}-{1}.quality.log" -f $sample.id, $metricName.ToLowerInvariant())
                    $metricCommands.Add([PSCustomObject]@{
                            id              = "quality-$($metricName.ToLowerInvariant())-$($sample.id)"
                            type            = 'QualityMetricSample'
                            metric          = $metricName
                            filterName      = $filterName
                            filterAvailable = [bool]$filterAvailable
                            assetId         = [string]$merge.assetId
                            sampleId        = [string]$sample.id
                            originalPath    = $originalPath
                            inputPath       = $encodedPath
                            logPath         = $metricLogPath
                            startSeconds    = [double]$sample.startSeconds
                            durationSeconds = [double]$sample.durationSeconds
                            executable      = if ($FfmpegPath) { $FfmpegPath } else { 'ffmpeg' }
                            arguments       = if ($filterAvailable -and
                                -not [string]::IsNullOrWhiteSpace($originalPath)) {
                                @(New-BackupQualityMetricArguments `
                                    -Metric $metricName `
                                    -Sample $sample `
                                    -OriginalPath $originalPath `
                                    -EncodedPath $encodedPath `
                                    -LogPath $metricLogPath)
                            }
                            else {
                                @()
                            }
                            scheduler       = [PSCustomObject]@{
                                lane     = 'QualityValidation'
                                priority = 70
                                weight   = 1
                            }
                            state           = if ($filterAvailable -and -not [string]::IsNullOrWhiteSpace($originalPath)) { 'Planned' } else { 'AdapterRequired' }
                        })
                }
            }
        }
    }

    return [PSCustomObject]@{
        schemaVersion = '1.0'
        enabled       = [bool]$enabled
        state         = if ($enabled) { 'Planned' } else { 'Disabled' }
        policy        = $policy
        availableFilters = @($normalizedFilters)
        samples       = @($samples.ToArray())
        decodeCommands = @($decodeCommands.ToArray())
        metricCommands = @($metricCommands.ToArray())
        summary       = [PSCustomObject]@{
            sampleCount       = $samples.Count
            decodeCommandCount = $decodeCommands.Count
            metricCommandCount = $metricCommands.Count
            plannedMetricCommandCount = @($metricCommands.ToArray() | Where-Object { [string]$_.state -eq 'Planned' }).Count
            adapterRequiredMetricCount = @($metricCommands.ToArray() | Where-Object { [string]$_.state -eq 'AdapterRequired' }).Count
        }
    }
}

function ConvertFrom-BackupQualityMetricOutput {
    [CmdletBinding()]
    param(
        [string[]]$Output
    )

    $metricValues = [ordered]@{}
    foreach ($line in @($Output)) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        $text = [string]$line
        if ($text -match 'VMAF score:\s*(?<value>[0-9]+(?:\.[0-9]+)?)') {
            $metricValues['VMAF'] = [double]::Parse($Matches['value'], [System.Globalization.CultureInfo]::InvariantCulture)
        }
        if ($text -match 'All:\s*(?<value>0(?:\.[0-9]+)?|1(?:\.0+)?)') {
            $metricValues['SSIM'] = [double]::Parse($Matches['value'], [System.Globalization.CultureInfo]::InvariantCulture)
        }
        if ($text -match 'average:\s*(?<value>[0-9]+(?:\.[0-9]+)?)') {
            $metricValues['PSNR'] = [double]::Parse($Matches['value'], [System.Globalization.CultureInfo]::InvariantCulture)
        }
    }

    return [PSCustomObject]$metricValues
}

function Test-BackupQualityValidationResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Policy,
        [object[]]$DecodeResults = @(),
        [object[]]$MetricResults = @()
    )

    $thresholds = Get-BackupQualityObjectValue -InputObject $Policy -Name 'thresholds'
    $metricsPolicy = Get-BackupQualityObjectValue -InputObject $Policy -Name 'metrics'
    $blockMeasured = [bool](Get-BackupQualityObjectValue -InputObject $metricsPolicy -Name 'blockWhenMeasuredBelowThreshold' -DefaultValue $true)
    $failedRules = New-Object System.Collections.Generic.List[object]
    $passedRules = New-Object System.Collections.Generic.List[object]
    $failedDecode = @($DecodeResults | Where-Object { -not [bool](Get-BackupQualityObjectValue -InputObject $_ -Name 'succeeded' -DefaultValue $false) })
    if ($failedDecode.Count -gt 0) {
        $failedRules.Add([PSCustomObject]@{
                rule   = 'SampleDecode'
                reason = 'SampleDecodeFailed'
                failedCount = $failedDecode.Count
            })
    }
    else {
        $passedRules.Add([PSCustomObject]@{
                rule   = 'SampleDecode'
                reason = 'SampleDecodePassed'
                count  = @($DecodeResults).Count
            })
    }

    $metricThresholds = @{
        VMAF = [double](Get-BackupQualityObjectValue -InputObject $thresholds -Name 'minVmaf' -DefaultValue 0)
        SSIM = [double](Get-BackupQualityObjectValue -InputObject $thresholds -Name 'minSsim' -DefaultValue 0)
        PSNR = [double](Get-BackupQualityObjectValue -InputObject $thresholds -Name 'minPsnr' -DefaultValue 0)
    }
    $measuredCount = 0
    foreach ($metricResult in @($MetricResults)) {
        $metricName = ([string](Get-BackupQualityObjectValue -InputObject $metricResult -Name 'metric')).ToUpperInvariant()
        if ($metricName -notin @('VMAF', 'SSIM', 'PSNR')) {
            continue
        }

        $score = Get-BackupQualityObjectValue -InputObject $metricResult -Name 'score'
        if ($null -eq $score) {
            continue
        }

        $measuredCount++
        $minimum = [double]$metricThresholds[$metricName]
        if ([double]$score -lt $minimum) {
            $failedRules.Add([PSCustomObject]@{
                    rule    = $metricName
                    reason  = 'QualityMetricBelowThreshold'
                    score   = [double]$score
                    minimum = $minimum
                    sampleId = [string](Get-BackupQualityObjectValue -InputObject $metricResult -Name 'sampleId')
                })
        }
    }
    if ($measuredCount -eq 0) {
        $passedRules.Add([PSCustomObject]@{
                rule   = 'OptionalMetrics'
                reason = 'NoQualityMetricsMeasured'
            })
    }
    elseif (@($failedRules | Where-Object { [string]$_.reason -eq 'QualityMetricBelowThreshold' }).Count -eq 0) {
        $passedRules.Add([PSCustomObject]@{
                rule   = 'QualityMetrics'
                reason = 'QualityMetricsPassed'
                count  = $measuredCount
            })
    }

    $blockingMetricFailures = if ($blockMeasured) {
        @($failedRules | Where-Object { [string]$_.reason -eq 'QualityMetricBelowThreshold' })
    }
    else {
        @()
    }
    $blockingFailures = @($failedRules | Where-Object { [string]$_.reason -ne 'QualityMetricBelowThreshold' }) + @($blockingMetricFailures)

    return [PSCustomObject]@{
        schemaVersion = '1.0'
        state         = if (@($blockingFailures).Count -eq 0) { 'Passed' } else { 'Failed' }
        passed        = @($blockingFailures).Count -eq 0
        evaluatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        thresholds    = $thresholds
        measuredMetricCount = $measuredCount
        passedRules   = @($passedRules.ToArray())
        failedRules   = @($failedRules.ToArray())
    }
}

function Invoke-BackupQualityValidationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Job,
        [Parameter(Mandatory)]
        [object]$Plan,
        [Parameter(Mandatory)]
        [object]$Scheduler
    )

    if (-not $Plan -or -not [bool]$Plan.enabled) {
        return [PSCustomObject]@{
            state = 'Skipped'
            passed = $true
            decodeResults = @()
            metricResults = @()
            evaluation = $null
        }
    }

    $decodeSchedule = Invoke-BackupScheduledCommandBatch `
        -Job $Job `
        -Commands @($Plan.decodeCommands) `
        -Scheduler $Scheduler `
        -Phase 'QualityDecode' `
        -MessageVerb 'Quality decode sample'

    $decodeResults = @(
        $Plan.decodeCommands |
            ForEach-Object {
                [PSCustomObject]@{
                    sampleId = [string]$_.sampleId
                    assetId  = [string]$_.assetId
                    succeeded = [string]$_.state -eq 'Completed'
                    state    = [string]$_.state
                }
            }
    )
    $metricResults = @()
    $evaluation = Test-BackupQualityValidationResult `
        -Policy $Plan.policy `
        -DecodeResults @($decodeResults) `
        -MetricResults @($metricResults)

    if (-not [bool]$evaluation.passed) {
        $failedReasons = @($evaluation.failedRules | ForEach-Object { [string]$_.reason }) -join ','
        throw "Quality validation failed. FailedRules=$failedReasons."
    }

    Update-BackupJobProgressSnapshot `
        -Job $Job `
        -StageName 'QualityValidationComplete' `
        -StageDisplayName 'Quality validation complete' `
        -Message ("Quality validation passed for {0} sample(s)." -f @($decodeResults).Count) `
        -Current @($decodeResults).Count `
        -Total @($decodeResults).Count `
        -Percent 100 |
        Out-Null

    return [PSCustomObject]@{
        state          = 'Passed'
        passed         = $true
        decodeSchedule = $decodeSchedule
        decodeResults  = @($decodeResults)
        metricResults  = @($metricResults)
        evaluation     = $evaluation
    }
}
