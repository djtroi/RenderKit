function Get-RenderKitBackupManifestSchemaVersion {
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    return '2.0'
}

function New-BackupManifest {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        "PSUseShouldProcessForStateChangingFunctions",
        "",
        Justification = "internal function. The public function already has a DryRun feature")]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Project,
        [Parameter(Mandatory)]
        [hashtable]$Options,
        [hashtable]$Statistics,
        [hashtable]$Archive,
        [array]$CleanupSummary,
        [object]$Job,
        [object]$Profile,
        [object]$Pipeline,
        [array]$StorageTiers,
        [object]$Safety
    )

    if (-not $Statistics) {
        $Statistics = @{}
    }
    if (-not $Archive) {
        $Archive = @{}
    }
    if (-not $CleanupSummary) {
        $CleanupSummary = @()
    }
    if (-not $Job) {
        $Job = [PSCustomObject]@{
            id            = $null
            type          = 'BackupProject'
            executionMode = 'Immediate'
            queued        = $false
        }
    }
    if (-not $Profile) {
        $Profile = [PSCustomObject]@{
            configProfile     = 'legacy'
            cleanupPresets    = @($Options.profiles)
            compressionPreset = 'Balanced'
        }
    }
    if (-not $Pipeline) {
        $Pipeline = [PSCustomObject]@{
            archiveFormat = 'Zip'
            encoding      = [PSCustomObject]@{
                videoCodec    = 'Auto'
                encoderDevice = 'Auto'
                qualityPreset = 'Balanced'
                audioProfile  = 'Auto'
                gpuDetection  = New-BackupGpuDetectionPlan `
                    -VideoCodec 'Auto' `
                    -EncoderDevice 'Auto' `
                    -CompressionPreset 'Balanced'
                qualityValidation = New-BackupQualityValidationPolicy `
                    -QualityPreset 'Balanced' `
                    -CompressionMode 'ArchiveOnly'
                proxy         = [PSCustomObject]@{ enabled = $false }
                preview       = [PSCustomObject]@{ enabled = $false }
            }
            chunking      = [PSCustomObject]@{
                enabled    = $false
                strategy   = 'Disabled'
                resumeMode = 'WholeArchive'
            }
            merge         = [PSCustomObject]@{
                strategy   = 'FfmpegConcatCopy'
                validation = [PSCustomObject]@{
                    enabled        = $false
                    containerProbe = 'ffprobe'
                    streamPolicy   = 'RequireExpectedPrimaryStreams'
                    syncPolicy     = 'DurationDriftWithinTolerance'
                }
            }
            scheduler     = [PSCustomObject]@{
                enabled         = $false
                mode            = 'SingleWorker'
                maxParallelJobs = 1
                policy          = [PSCustomObject]@{
                    primaryVideo = 'OneChunkAtATime'
                    secondaryMedia = 'ParallelWithinWorkerPool'
                    checksums     = 'ParallelDiskReadLane'
                }
            }
            progress      = [PSCustomObject]@{
                statePath = $null
                source    = [PSCustomObject]@{
                    ffmpegProgress = 'pipe:1'
                    copyProgress   = 'byte-callback'
                    chunkProgress  = 'chunk-index'
                }
                metrics   = @(
                    'StageName',
                    'OverallPercent',
                    'ChunkPercent',
                    'EtaSeconds',
                    'Speed'
                )
            }
            control       = [PSCustomObject]@{
                statePath = $null
                pause     = [PSCustomObject]@{
                    enabled = $true
                    mode    = 'ProcessSuspendWhenSupported'
                }
                resume    = [PSCustomObject]@{
                    enabled = $true
                    mode    = 'SkipCompletedChunksFromChunkIndex'
                }
                cancel    = [PSCustomObject]@{
                    enabled = $true
                    mode    = 'OrderedStopActiveProcesses'
                }
                retry     = [PSCustomObject]@{
                    maxAttemptsPerChunk = 3
                }
            }
            background    = [PSCustomObject]@{
                enabled   = $true
                queueName = 'backup'
                worker    = [PSCustomObject]@{
                    mode              = 'LocalWorker'
                    startCommand      = 'Start-RenderKitJobWorker'
                    statusCommand     = 'Get-RenderKitJobStatus'
                    workerStatusCommand = 'Get-RenderKitJobWorkerStatus'
                }
                recovery  = [PSCustomObject]@{
                    leaseHeartbeat      = 'ProgressExtendsLease'
                    staleRunningJobMode = 'RequeueAfterExpiredLease'
                    crashedWorkerState  = 'DetectPreviousWorkerPid'
                }
                logs      = [PSCustomObject]@{
                    persistent = $true
                    format     = 'jsonl'
                }
            }
            storageCascade = [PSCustomObject]@{
                schemaVersion = '1.0'
                enabled       = $false
                mode          = 'SingleTarget'
                strategy      = 'FastestWritableFirstThenCascade'
                stages        = @()
            }
            copyVerify = [PSCustomObject]@{
                schemaVersion = '1.0'
                enabled       = $false
                state         = 'Planned'
                algorithm     = 'SHA256'
                verify        = [PSCustomObject]@{
                    afterEveryTier      = $true
                    method              = 'ChecksumCompare'
                    releaseRequires     = 'ArchiveIntegrityAndRequiredStorageTiersVerified'
                    primaryTierRequired = $true
                    requiredTierIds     = @()
                }
                retry         = [PSCustomObject]@{
                    maxAttempts = 1
                }
            }
            safeDelete = New-BackupSafeDeletePolicy `
                -Mode $(if ($Options.keepSourceProject) { 'KeepSource' } else { 'RemoveSourceAfterVerified' }) `
                -RequiredStorageTierIds @()
            mediaAnalysis = [PSCustomObject]@{
                summary = $null
            }
            chunkPlan = [PSCustomObject]@{
                summary = $null
            }
            resume = [PSCustomObject]@{
                statePath = $null
            }
        }
    }
    if (-not $StorageTiers) {
        $StorageTiers = @()
    }
    if (-not $Safety) {
        $Safety = [PSCustomObject]@{
            deletePolicy = [PSCustomObject]@{
                mode                           = if ($Options.keepSourceProject) { 'KeepSource' } else { 'RemoveSourceAfterVerified' }
                requiresArchiveIntegrity       = $true
                requiresDecodeValidation       = $true
                decodeValidationScope          = 'WhenProducedMediaExists'
                requiresPrimaryTierVerification = $true
                requiresAllTierVerification    = $false
                releaseCondition                = 'ArchiveIntegrityDecodeAndRequiredStorageTiersVerified'
            }
            safeDelete = New-BackupSafeDeletePolicy `
                -Mode $(if ($Options.keepSourceProject) { 'KeepSource' } else { 'RemoveSourceAfterVerified' }) `
                -RequiredStorageTierIds @()
        }
    }

    return [PSCustomObject]@{
        schemaVersion = Get-RenderKitBackupManifestSchemaVersion
        backup = @{
            id        = [guid]::NewGuid().ToString()
            createdAt = (Get-Date).ToString("o")
            createdBy = $ENV:USERNAME
            machine   = $ENV:COMPUTERNAME
            tool      = @{
                name    = "RenderKit"
                version = $script:RenderKitModuleVersion
            }
        }
        project = @{
            id       = $Project.id
            name     = $Project.Name
            rootPath = $Project.RootPath
        }
        options    = $Options
        job        = $Job
        profile    = $Profile
        pipeline   = $Pipeline
        storageTiers = @($StorageTiers)
        safety     = $Safety
        statistics = $Statistics
        archive    = $Archive
        cleanup    = $CleanupSummary
    }
}
