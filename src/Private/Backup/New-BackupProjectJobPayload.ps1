function ConvertTo-BackupProjectStorageTier {
    [CmdletBinding()]
    param(
        [hashtable[]]$StorageTier,
        [string]$DestinationRoot,
        [string]$ArchivePath
    )

    $tiers = New-Object System.Collections.Generic.List[object]
    $index = 0
    foreach ($tier in @($StorageTier)) {
        if (-not $tier) {
            continue
        }

        $index++
        $tierName = if ($tier.ContainsKey('Name')) { [string]$tier.Name } else { "Tier$index" }
        $tierPath = if ($tier.ContainsKey('Path')) { [string]$tier.Path } else { $null }
        if ([string]::IsNullOrWhiteSpace($tierPath)) {
            throw "Backup storage tier '$tierName' must provide a Path value."
        }

        $tiers.Add([PSCustomObject]@{
            id       = if ($tier.ContainsKey('Id')) { [string]$tier.Id } else { "tier-$index" }
            name     = $tierName
            kind     = if ($tier.ContainsKey('Kind')) { [string]$tier.Kind } else { 'LocalFileSystem' }
            role     = if ($tier.ContainsKey('Role')) { [string]$tier.Role } else { if ($index -eq 1) { 'Primary' } else { 'Cascade' } }
            order    = if ($tier.ContainsKey('Order')) { [int]$tier.Order } else { $index }
            path     = $tierPath
            verify   = [PSCustomObject]@{
                enabled   = if ($tier.ContainsKey('Verify')) { [bool]$tier.Verify } else { $true }
                algorithm = if ($tier.ContainsKey('VerifyAlgorithm')) { [string]$tier.VerifyAlgorithm } else { 'SHA256' }
            }
            state    = 'Planned'
        })
    }

    if ($tiers.Count -eq 0) {
        $primaryPath = $DestinationRoot
        if ([string]::IsNullOrWhiteSpace($primaryPath) -and
            -not [string]::IsNullOrWhiteSpace($ArchivePath)) {
            $primaryPath = Split-Path -Path $ArchivePath -Parent
        }

        if (-not [string]::IsNullOrWhiteSpace($primaryPath)) {
            $tiers.Add([PSCustomObject]@{
                id     = 'tier-1'
                name   = 'Primary'
                kind   = 'LocalFileSystem'
                role   = 'Primary'
                order  = 1
                path   = $primaryPath
                verify = [PSCustomObject]@{
                    enabled   = $true
                    algorithm = 'SHA256'
                }
                state  = 'Planned'
            })
        }
    }

    return @($tiers.ToArray() | Sort-Object order, id)
}

function New-BackupProjectJobPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Project,
        [Parameter(Mandatory)]
        [pscustomobject]$ArchiveDescriptor,
        [string[]]$CleanupPreset = @('General'),
        [string]$ConfigProfile = 'balanced',
        [ValidateSet('Zip', 'SevenZip', 'TarZstd', 'Folder')]
        [string]$ArchiveFormat = 'Zip',
        [ValidateSet('ArchiveOnly', 'TranscodeAndArchive', 'CopyOnly')]
        [string]$CompressionMode = 'ArchiveOnly',
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
        [switch]$CreateProxy,
        [switch]$CreatePreview,
        [switch]$KeepEmptyFolders,
        [switch]$KeepSourceProject,
        [switch]$DryRun,
        [switch]$Background,
        [switch]$DisableChunking,
        [ValidateRange(10, 86400)]
        [int]$ChunkDurationSeconds = 600,
        [hashtable[]]$StorageTier,
        [ValidateRange(1, 64)]
        [int]$MaxParallelJobs = 1,
        [ValidateRange(1, 100)]
        [int]$MaxCpuPercent = 90,
        [ValidateRange(1, 100)]
        [int]$MaxGpuPercent = 95,
        [ValidateRange(1, 100)]
        [int]$MaxDiskActivePercent = 90,
        [ValidateRange(1, 120)]
        [int]$MaxTemperatureCelsius = 85,
        [switch]$RequireIdle,
        [ValidateRange(0, 1440)]
        [int]$MinIdleMinutes = 10,
        [string]$AllowedStartTime,
        [string]$AllowedEndTime,
        [ValidateRange(1, 3600)]
        [int]$SystemRulePollSeconds = 5,
        [switch]$AllowOnBattery,
        [switch]$DisableThermalThrottle,
        [string]$QueueName = 'backup',
        [int]$Priority = 0
    )

    if ([string]::IsNullOrWhiteSpace($ConfigProfile)) {
        $ConfigProfile = 'balanced'
    }
    if ([string]::IsNullOrWhiteSpace($QueueName)) {
        $QueueName = 'backup'
    }

    $chunkingEnabled = -not [bool]$DisableChunking
    $probeTimedMedia = $chunkingEnabled -and $CompressionMode -eq 'TranscodeAndArchive'
    $mediaAnalysis = Get-BackupMediaAnalysis `
        -ProjectRoot ([string]$Project.RootPath) `
        -ProbeTimedMedia:$probeTimedMedia
    $chunkPlan = New-BackupChunkPlan `
        -MediaAnalysis $mediaAnalysis `
        -ChunkDurationSeconds $ChunkDurationSeconds `
        -Enabled:$probeTimedMedia
    $deletePolicyMode = if ($KeepSourceProject) { 'KeepSource' } else { 'RemoveSourceAfterVerified' }
    $storageTiers = ConvertTo-BackupProjectStorageTier `
        -StorageTier $StorageTier `
        -DestinationRoot ([string]$ArchiveDescriptor.DestinationRoot) `
        -ArchivePath ([string]$ArchiveDescriptor.ArchivePath)
    $systemRules = New-RenderKitSystemRulesPolicy `
        -RequireIdle ([bool]$RequireIdle) `
        -MinIdleMinutes $MinIdleMinutes `
        -AllowOnBattery ([bool]$AllowOnBattery) `
        -ThermalThrottleEnabled (-not [bool]$DisableThermalThrottle) `
        -MaxCpuPercent $MaxCpuPercent `
        -MaxGpuPercent $MaxGpuPercent `
        -MaxDiskActivePercent $MaxDiskActivePercent `
        -MaxTemperatureCelsius $MaxTemperatureCelsius `
        -AllowedStartTime $AllowedStartTime `
        -AllowedEndTime $AllowedEndTime `
        -PollIntervalSeconds $SystemRulePollSeconds

    $now = (Get-Date).ToUniversalTime().ToString('o')
    return [PSCustomObject]@{
        schemaVersion    = '1.0'
        kind             = 'BackupProject'
        requestedAtUtc   = $now
        project          = [PSCustomObject]@{
            id       = [string]$Project.Id
            name     = [string]$Project.Name
            rootPath = [string]$Project.RootPath
        }
        source           = [PSCustomObject]@{
            rootPath        = [string]$Project.RootPath
            cleanup         = [PSCustomObject]@{
                presets          = @($CleanupPreset)
                keepEmptyFolders = [bool]$KeepEmptyFolders
            }
            deletePolicy    = [PSCustomObject]@{
                mode                           = $deletePolicyMode
                requiresArchiveIntegrity       = $true
                requiresPrimaryTierVerification = $true
                requiresAllTierVerification    = $false
            }
        }
        profile          = [PSCustomObject]@{
            configProfile     = $ConfigProfile
            cleanupPresets    = @($CleanupPreset)
            compressionPreset = $CompressionPreset
        }
        encoding         = [PSCustomObject]@{
            schemaVersion    = '1.0'
            videoCodec       = $VideoCodec
            encoderDevice    = $EncoderDevice
            qualityPreset    = $QualityPreset
            audioProfile     = $AudioProfile
            proxy            = [PSCustomObject]@{
                enabled     = [bool]$CreateProxy
                height      = 720
                videoCodec  = 'H264'
                quality     = 'Draft'
            }
            preview          = [PSCustomObject]@{
                enabled        = [bool]$CreatePreview
                format         = 'jpg'
                intervalSeconds = 60
                width          = 1280
            }
        }
        archive          = [PSCustomObject]@{
            format            = $ArchiveFormat
            mode              = $CompressionMode
            compressionPreset = $CompressionPreset
            destinationRoot   = [string]$ArchiveDescriptor.DestinationRoot
            fileName          = [string]$ArchiveDescriptor.ArchiveFileName
            path              = [string]$ArchiveDescriptor.ArchivePath
        }
        chunking         = [PSCustomObject]@{
            enabled         = $chunkingEnabled
            strategy        = if ($chunkingEnabled) { 'TimeRange' } else { 'Disabled' }
            durationSeconds = if ($chunkingEnabled) { $ChunkDurationSeconds } else { 0 }
            resumeMode      = if ($chunkingEnabled) { 'ChunkManifest' } else { 'WholeArchive' }
            state           = 'Planned'
            plannedChunkCount = [int]$chunkPlan.summary.chunkCount
        }
        merge            = [PSCustomObject]@{
            schemaVersion = '1.0'
            strategy      = 'FfmpegConcatCopy'
            state         = 'Planned'
            validation    = [PSCustomObject]@{
                enabled           = $probeTimedMedia
                containerProbe    = 'ffprobe'
                streamPolicy      = 'RequireExpectedPrimaryStreams'
                syncPolicy        = 'DurationDriftWithinTolerance'
                failureAction     = 'FailJobBeforeArchive'
            }
        }
        scheduler        = [PSCustomObject]@{
            schemaVersion   = '1.0'
            enabled         = $MaxParallelJobs -gt 1
            mode            = if ($MaxParallelJobs -gt 1) { 'WorkerPool' } else { 'SingleWorker' }
            maxParallelJobs = $MaxParallelJobs
            queuePriority   = $Priority
            policy          = [PSCustomObject]@{
                primaryVideo = 'OneChunkAtATime'
                secondaryMedia = 'ParallelWithinWorkerPool'
                imagesAndPreviews = 'ParallelDerivativeLane'
                checksums     = 'ParallelDiskReadLane'
                overloadAction = 'ThrottleByLaneLimits'
            }
            resourceLimits  = [PSCustomObject]@{
                maxCpuPercent = $MaxCpuPercent
                maxGpuPercent = $MaxGpuPercent
                maxDiskActivePercent = $MaxDiskActivePercent
                maxTemperatureCelsius = $MaxTemperatureCelsius
                diskPolicy    = 'LimitHeavyDiskStages'
                requireIdle   = [bool]$RequireIdle
                minIdleMinutes = $MinIdleMinutes
                allowedStartTime = $AllowedStartTime
                allowedEndTime = $AllowedEndTime
                systemRulePollSeconds = $SystemRulePollSeconds
            }
        }
        progress         = [PSCustomObject]@{
            schemaVersion = '1.0'
            state         = 'Planned'
            statePath     = $null
            source        = [PSCustomObject]@{
                ffmpegProgress = 'pipe:1'
                copyProgress   = 'byte-callback'
                chunkProgress  = 'chunk-index'
            }
            metrics       = @(
                'StageName',
                'OverallPercent',
                'ChunkPercent',
                'EtaSeconds',
                'Speed',
                'ActiveCommands',
                'BytesCompleted',
                'BytesTotal'
            )
            stages        = @(
                'PlanningEncoding',
                'Encoding',
                'Merging',
                'ValidatingMerge',
                'CreatingProxy',
                'CreatingPreview',
                'EncodingComplete'
            )
        }
        control          = [PSCustomObject]@{
            schemaVersion = '1.0'
            statePath     = $null
            pause         = [PSCustomObject]@{
                enabled = $true
                mode    = 'ProcessSuspendWhenSupported'
            }
            resume        = [PSCustomObject]@{
                enabled = $true
                mode    = 'SkipCompletedChunksFromChunkIndex'
            }
            cancel        = [PSCustomObject]@{
                enabled = $true
                mode    = 'OrderedStopActiveProcesses'
            }
            retry         = [PSCustomObject]@{
                maxAttemptsPerChunk = 3
                retryDelaySeconds   = 1
            }
        }
        background        = [PSCustomObject]@{
            schemaVersion = '1.0'
            enabled       = $true
            queueName     = 'backup'
            worker        = [PSCustomObject]@{
                mode              = 'LocalWorker'
                startCommand      = 'Start-RenderKitJobWorker'
                statusCommand     = 'Get-RenderKitJobStatus'
                workerStatusCommand = 'Get-RenderKitJobWorkerStatus'
                supportsDetached  = $true
                stateRoot         = $null
                logRoot           = $null
            }
            recovery      = [PSCustomObject]@{
                leaseHeartbeat       = 'ProgressExtendsLease'
                staleRunningJobMode  = 'RequeueAfterExpiredLease'
                crashedWorkerState   = 'DetectPreviousWorkerPid'
            }
            logs          = [PSCustomObject]@{
                persistent = $true
                format     = 'jsonl'
                tailCommand = 'Get-RenderKitJobStatus -IncludeLogs'
            }
        }
        systemRules       = $systemRules
        mediaAnalysis    = [PSCustomObject]@{
            schemaVersion = [string]$mediaAnalysis.schemaVersion
            probe         = $mediaAnalysis.probe
            summary       = $mediaAnalysis.summary
            files         = @($mediaAnalysis.files)
        }
        chunkPlan        = $chunkPlan
        resume           = [PSCustomObject]@{
            schemaVersion = '1.0'
            strategy      = if ($probeTimedMedia) { 'ChunkManifest' } else { 'WholeArchive' }
            state         = 'Planned'
            jobId         = $null
            statePath     = $null
            progressStatePath = $null
            lastCompletedChunkId = $null
        }
        storageTiers     = @($storageTiers)
        execution        = [PSCustomObject]@{
            mode                   = if ($Background) { 'Background' } else { 'Immediate' }
            queueName              = $QueueName
            priority               = $Priority
            dryRun                 = [bool]$DryRun
            maxParallelJobs        = $MaxParallelJobs
            requireIdle            = [bool]$RequireIdle
            allowOnBattery         = [bool]$AllowOnBattery
            thermalThrottleEnabled = -not [bool]$DisableThermalThrottle
            resourceLimits         = [PSCustomObject]@{
                maxCpuPercent = $MaxCpuPercent
                maxGpuPercent = $MaxGpuPercent
                maxDiskActivePercent = $MaxDiskActivePercent
                maxTemperatureCelsius = $MaxTemperatureCelsius
            }
            systemRules             = $systemRules
        }
        advancedFeatures = [PSCustomObject]@{
            gpuDetection      = [PSCustomObject]@{ enabled = $true; state = 'Planned' }
            deduplication     = [PSCustomObject]@{ enabled = $true; state = 'Planned' }
            qualityValidation = [PSCustomObject]@{ enabled = $true; state = 'Planned'; metrics = @('DecodeProbe') }
            tapeTargets       = [PSCustomObject]@{ enabled = $true; state = 'AdapterPlanned' }
            cloudTargets      = [PSCustomObject]@{ enabled = $true; state = 'AdapterPlanned' }
            idleDetection     = [PSCustomObject]@{ enabled = [bool]$RequireIdle; state = 'Planned' }
        }
    }
}

function New-BackupProjectJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Payload,
        [string]$QueueName = 'backup',
        [int]$Priority = 0,
        [string]$CorrelationId,
        [object]$RequestedBy
    )

    if ([string]::IsNullOrWhiteSpace($QueueName)) {
        $QueueName = 'backup'
    }

    $job = New-RenderKitJob `
        -JobType 'BackupProject' `
        -Payload $Payload `
        -PayloadSchemaVersion ([string]$Payload.schemaVersion) `
        -QueueName $QueueName `
        -Priority $Priority `
        -CorrelationId $CorrelationId `
        -RequestedBy $RequestedBy

    if ($Payload.PSObject.Properties.Name -contains 'resume' -and $Payload.resume) {
        $resumeStatePath = Get-BackupResumeStatePath -JobId ([string]$job.id)
        $progressStatePath = Get-BackupProgressStatePath -JobId ([string]$job.id)
        $controlStatePath = Get-BackupControlStatePath -JobId ([string]$job.id)
        $Payload.resume.jobId = [string]$job.id
        $Payload.resume.statePath = $resumeStatePath
        $Payload.resume.progressStatePath = $progressStatePath
        if ($Payload.PSObject.Properties.Name -contains 'progress' -and $Payload.progress) {
            $Payload.progress.statePath = $progressStatePath
        }
        if ($Payload.PSObject.Properties.Name -contains 'control' -and $Payload.control) {
            $Payload.control.statePath = $controlStatePath
        }
        if ($Payload.PSObject.Properties.Name -contains 'background' -and $Payload.background) {
            $Payload.background.queueName = $QueueName
            $Payload.background.worker.stateRoot = Get-RenderKitWorkerStateRoot
            $Payload.background.worker.logRoot = Get-RenderKitWorkerLogRoot
        }
        if ($Payload.chunkPlan -and $Payload.chunkPlan.index) {
            $Payload.chunkPlan.index.jobId = [string]$job.id
            $Payload.chunkPlan.index.statePath = Get-BackupChunkIndexPath -JobId ([string]$job.id)
            Save-BackupChunkIndex `
                -JobId ([string]$job.id) `
                -ChunkIndex $Payload.chunkPlan.index |
                Out-Null
        }
        $job.payload = $Payload

        Save-BackupResumeState `
            -JobId ([string]$job.id) `
            -State (New-BackupResumeState -Job $job -Payload $Payload) |
            Out-Null
        Save-BackupControlState `
            -JobId ([string]$job.id) `
            -State (New-BackupControlState -JobId ([string]$job.id) -StatePath $controlStatePath) |
            Out-Null
    }

    return Add-RenderKitJob -Job $job
}
