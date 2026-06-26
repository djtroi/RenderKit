Describe 'RenderKit BackupProject job planning' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (
            Split-Path -Parent $PSScriptRoot)
        Import-Module `
            (Join-Path $repositoryRoot 'RenderKit.psd1') `
            -Force
    }

    BeforeEach {
        $env:RENDERKIT_HOME = Join-Path $TestDrive 'renderkit-home'
        if (Test-Path -LiteralPath $env:RENDERKIT_HOME) {
            Remove-Item -LiteralPath $env:RENDERKIT_HOME -Recurse -Force
        }
    }

    AfterEach {
        $env:RENDERKIT_HOME = $null
    }

    AfterAll {
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
    }

    It 'queues a background BackupProject job with chunking and storage tiers' {
        $projectParent = Join-Path $TestDrive 'projects'
        $projectRoot = Join-Path $projectParent 'SmokeProject'
        $metadataRoot = Join-Path $projectRoot '.renderkit'
        New-Item -ItemType Directory -Path $metadataRoot -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $projectRoot 'Media') -Force | Out-Null
        Set-Content `
            -LiteralPath (Join-Path $projectRoot 'Media\clip.mp4') `
            -Value 'placeholder' `
            -Encoding UTF8
        [PSCustomObject]@{
            tool = 'RenderKit'
            schemaVersion = '1.0'
            project = [PSCustomObject]@{
                id = 'smoke-project'
                name = 'SmokeProject'
                createdAt = (Get-Date).ToString('o')
            }
            lifecycle = [PSCustomObject]@{
                status = 'Draft'
            }
        } |
            ConvertTo-Json -Depth 8 |
            Set-Content `
                -LiteralPath (Join-Path $metadataRoot 'project.json') `
                -Encoding UTF8

        $result = Backup-Project `
            -ProjectName SmokeProject `
            -Path $projectParent `
            -Background `
            -ConfigProfile smallest `
            -ArchiveFormat SevenZip `
            -CompressionMode TranscodeAndArchive `
            -CompressionPreset Smallest `
            -VideoCodec AV1 `
            -EncoderDevice CPU `
            -QualityPreset Smallest `
            -AudioProfile Opus_96 `
            -CreateProxy `
            -CreatePreview `
            -ChunkDurationSeconds 120 `
            -MaxParallelJobs 4 `
            -MaxCpuPercent 75 `
            -MaxGpuPercent 80 `
            -RequireIdle `
            -StorageTier @{
                Name = 'Fast SSD'
                Path = (Join-Path $TestDrive 'fast')
                Kind = 'LocalFileSystem'
            } `
            -StorageTierProfile @('HDD', 'NAS', 'CloudS3') `
            -StorageTierPath @(
                (Join-Path $TestDrive 'hdd'),
                '\\nas\renderkit\SmokeProject',
                's3://renderkit-backups/SmokeProject'
            )

        $result.JobType | Should -Be 'BackupProject'
        $result.Status | Should -Be 'Queued'
        $result.Payload.profile.configProfile | Should -Be 'smallest'
        $result.Payload.archive.format | Should -Be 'SevenZip'
        $result.Payload.encoding.videoCodec | Should -Be 'AV1'
        $result.Payload.encoding.encoderDevice | Should -Be 'CPU'
        $result.Payload.encoding.audioProfile | Should -Be 'Opus_96'
        $result.Payload.encoding.gpuDetection.enabled | Should -BeTrue
        $result.Payload.encoding.gpuDetection.providers | Should -Contain 'Nvidia'
        $result.Payload.encoding.gpuDetection.codecSupport | Should -Contain 'AV1'
        $result.Payload.encoding.gpuDetection.cache.enabled | Should -BeTrue
        $result.Payload.encoding.gpuDetection.benchmark.state | Should -Be 'AvailableOnWorker'
        $result.Payload.encoding.qualityValidation.enabled | Should -BeTrue
        $result.Payload.encoding.qualityValidation.decode.required | Should -BeTrue
        $result.Payload.encoding.qualityValidation.metrics.names | Should -Contain 'VMAF'
        $result.Payload.encoding.qualityValidation.thresholds.minVmaf | Should -Be 82.0
        $result.Payload.encoding.proxy.enabled | Should -BeTrue
        $result.Payload.encoding.preview.enabled | Should -BeTrue
        $result.Payload.chunking.enabled | Should -BeTrue
        $result.Payload.merge.validation.enabled | Should -BeTrue
        $result.Payload.merge.validation.syncPolicy | Should -Be 'DurationDriftWithinTolerance'
        $result.Payload.chunking.durationSeconds | Should -Be 120
        $result.Payload.scheduler.enabled | Should -BeTrue
        $result.Payload.scheduler.maxParallelJobs | Should -Be 4
        $result.Payload.scheduler.resourceLimits.maxCpuPercent | Should -Be 75
        $result.Payload.scheduler.policy.primaryVideo | Should -Be 'OneChunkAtATime'
        $result.Payload.progress.source.ffmpegProgress | Should -Be 'pipe:1'
        $result.Payload.progress.metrics | Should -Contain 'EtaSeconds'
        $result.Payload.progress.stages | Should -Contain 'QualityDecode'
        $result.Payload.progress.stages | Should -Contain 'QualityValidationComplete'
        $result.Payload.progress.statePath | Should -Be $result.Payload.resume.progressStatePath
        Test-Path -LiteralPath (Split-Path -Path $result.Payload.progress.statePath -Parent) |
            Should -BeTrue
        $result.Payload.control.pause.enabled | Should -BeTrue
        $result.Payload.control.resume.mode | Should -Be 'SkipCompletedChunksFromChunkIndex'
        $result.Payload.control.cancel.mode | Should -Be 'OrderedStopActiveProcesses'
        $result.Payload.control.retry.maxAttemptsPerChunk | Should -Be 3
        Test-Path -LiteralPath $result.Payload.control.statePath |
            Should -BeTrue
        $result.Payload.background.enabled | Should -BeTrue
        $result.Payload.background.queueName | Should -Be 'backup'
        $result.Payload.background.worker.startCommand | Should -Be 'Start-RenderKitJobWorker'
        $result.Payload.background.worker.statusCommand | Should -Be 'Get-RenderKitJobStatus'
        $result.Payload.background.recovery.staleRunningJobMode | Should -Be 'RequeueAfterExpiredLease'
        Test-Path -LiteralPath $result.Payload.background.worker.stateRoot |
            Should -BeTrue
        Test-Path -LiteralPath $result.Payload.background.worker.logRoot |
            Should -BeTrue
        $result.Payload.execution.requireIdle | Should -BeTrue
        $result.Payload.storageTiers[0].name | Should -Be 'Fast SSD'
        $result.Payload.storageTiers[0].profile | Should -Be 'FastSSD'
        $result.Payload.storageTiers[1].profile | Should -Be 'HDD'
        $result.Payload.storageTiers[2].profile | Should -Be 'NAS'
        $result.Payload.storageTiers[3].profile | Should -Be 'CloudS3'
        $result.Payload.storageTiers[0].fallback.toTierId | Should -Be $result.Payload.storageTiers[1].id
        $result.Payload.storageTiers[3].target.kind | Should -Be 'Uri'
        $result.Payload.storageCascade.mode | Should -Be 'Cascading'
        $result.Payload.storageCascade.strategy | Should -Be 'FastestWritableFirstThenCascade'
        $result.Payload.storageCascade.supportedProfiles | Should -Contain 'Tape'
        $result.Payload.storageCascade.stages[0].action | Should -Be 'WritePrimary'
        $result.Payload.storageCascade.stages[1].action | Should -Be 'CascadeCopy'
        $result.Payload.copyVerify.enabled | Should -BeTrue
        $result.Payload.copyVerify.verify.afterEveryTier | Should -BeTrue
        $result.Payload.copyVerify.verify.releaseRequires |
            Should -Be 'ArchiveIntegrityAndRequiredStorageTiersVerified'
        $result.Payload.source.deletePolicy.requiresStorageCascadeVerification |
            Should -BeTrue
        $result.Payload.source.deletePolicy.requiresDecodeValidation |
            Should -BeTrue
        $result.Payload.source.deletePolicy.releaseCondition |
            Should -Be 'ArchiveIntegrityDecodeAndRequiredStorageTiersVerified'
        $result.Payload.safeDelete.mode | Should -Be 'RemoveSourceAfterVerified'
        $result.Payload.safeDelete.rules.requiresArchiveIntegrity | Should -BeTrue
        $result.Payload.safeDelete.rules.requiresDecodeValidation | Should -BeTrue
        $result.Payload.safeDelete.rules.requiresStorageCascadeVerification | Should -BeTrue
        $result.Payload.safeDelete.rules.requiredStorageTierIds |
            Should -Contain $result.Payload.storageTiers[0].id
        $result.Payload.advancedFeatures.gpuDetection.cache.enabled | Should -BeTrue
        $result.Payload.advancedFeatures.gpuDetection.benchmark.enabled | Should -BeTrue
        $result.Payload.advancedFeatures.deduplication.enabled | Should -BeTrue
        $result.Payload.advancedFeatures.deduplication.mode |
            Should -Be 'ContentHashCanonicalManifest'
        $result.Payload.reports.enabled | Should -BeTrue
        $result.Payload.reports.formats | Should -Contain 'Json'
        $result.Payload.reports.formats | Should -Contain 'Html'
        $result.Payload.reports.formats | Should -Contain 'Text'
        $result.Payload.advancedFeatures.reports.mode |
            Should -Be 'SidecarAuditReports'
        $result.Payload.advancedFeatures.qualityValidation.thresholds.minVmaf | Should -Be 82.0
        $result.Payload.mediaAnalysis.summary.mediaFileCount | Should -Be 1
        $result.Payload.resume.jobId | Should -Be $result.JobId
        Test-Path -LiteralPath $result.Payload.resume.statePath |
            Should -BeTrue
        Test-Path -LiteralPath $result.Payload.chunkPlan.index.statePath |
            Should -BeTrue

        InModuleScope RenderKit {
            $jobs = @((Read-RenderKitJobStore).jobs)
            $jobs.Count | Should -Be 1
            $jobs[0].jobType | Should -Be 'BackupProject'
            $jobs[0].payload.archive.format | Should -Be 'SevenZip'
            Test-Path -LiteralPath $jobs[0].payload.resume.statePath |
                Should -BeTrue
        }
    }

    It 'builds storage tier cascade profiles with fallbacks' {
        $cascade = InModuleScope RenderKit -Parameters @{
            FastPath = (Join-Path $TestDrive 'fast')
            HddPath = (Join-Path $TestDrive 'hdd')
        } {
            $tiers = ConvertTo-BackupProjectStorageTier `
                -StorageTier @(
                    @{
                        Name = 'Fast SSD'
                        Profile = 'FastSSD'
                        Path = $FastPath
                        Required = $true
                    }
                    @{
                        Name = 'Nearline HDD'
                        Profile = 'HDD'
                        Path = $HddPath
                    }
                    @{
                        Name = 'LTO Archive'
                        Profile = 'Tape'
                        Uri = 'ltfs://library/A00001'
                    }
                ) `
                -DestinationRoot $FastPath
            [PSCustomObject]@{
                tiers = @($tiers)
                plan  = New-BackupStorageCascadePlan -StorageTiers @($tiers)
            }
        }

        $cascade.tiers.Count | Should -Be 3
        $cascade.tiers[0].profile | Should -Be 'FastSSD'
        $cascade.tiers[0].required | Should -BeTrue
        $cascade.tiers[0].fallback.toTierId | Should -Be $cascade.tiers[1].id
        $cascade.tiers[1].copy.mode | Should -Be 'CascadeFromPreviousVerifiedTier'
        $cascade.tiers[2].adapter | Should -Be 'LTFS'
        $cascade.tiers[2].target.kind | Should -Be 'Uri'
        $cascade.plan.mode | Should -Be 'Cascading'
        $cascade.plan.finalTierIds | Should -Contain $cascade.tiers[2].id
        $cascade.plan.fallbackPolicy.defaultAction | Should -Be 'UseNextAvailableTier'
        $cascade.plan.interactive.command | Should -Be 'Backup-Project -ConfigureStorageTiers'
    }

    It 'copies and verifies archive artifacts across required storage tiers' {
        $verified = InModuleScope RenderKit -Parameters @{
            SourcePath = (Join-Path $TestDrive 'primary\backup.zip')
            Primary   = (Join-Path $TestDrive 'primary')
            Secondary = (Join-Path $TestDrive 'secondary')
        } {
            New-Item -ItemType Directory -Path $Primary -Force | Out-Null
            Set-Content -LiteralPath $SourcePath -Value 'archive-bytes' -Encoding UTF8
            $sourceItem = Get-Item -LiteralPath $SourcePath
            $hash = Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256
            $tiers = ConvertTo-BackupProjectStorageTier `
                -StorageTier @(
                    @{
                        Name = 'Fast SSD'
                        Profile = 'FastSSD'
                        Path = $Primary
                        Required = $true
                        RetryDelaySeconds = 0
                    }
                    @{
                        Name = 'Nearline HDD'
                        Profile = 'HDD'
                        Path = $Secondary
                        Required = $true
                        RetryDelaySeconds = 0
                    }
                ) `
                -DestinationRoot $Primary `
                -ArchivePath $SourcePath
            $cascade = New-BackupStorageCascadePlan -StorageTiers @($tiers)
            $report = Invoke-BackupStorageTierCopyVerifyChain `
                -ArchivePath $SourcePath `
                -StorageTiers @($tiers) `
                -StorageCascade $cascade `
                -ExpectedHash ([string]$hash.Hash) `
                -ExpectedSizeBytes ([int64]$sourceItem.Length) `
                -Algorithm SHA256 `
                -ArchiveIntegrityPassed $true
            [PSCustomObject]@{
                report = $report
                secondaryPath = Join-Path $Secondary (Split-Path -Path $SourcePath -Leaf)
            }
        }

        $verified.report.state | Should -Be 'Verified'
        $verified.report.summary.verifiedTierCount | Should -Be 2
        $verified.report.release.canReleaseSource | Should -BeTrue
        $verified.report.tiers[0].health.state | Should -Be 'Healthy'
        $verified.report.tiers[1].copied | Should -BeTrue
        $verified.report.tiers[1].verified | Should -BeTrue
        Test-Path -LiteralPath $verified.secondaryPath | Should -BeTrue
    }

    It 'blocks source release when a required tier cannot be verified' {
        $blocked = InModuleScope RenderKit -Parameters @{
            SourcePath = (Join-Path $TestDrive 'blocked-primary\backup.zip')
            Primary   = (Join-Path $TestDrive 'blocked-primary')
        } {
            New-Item -ItemType Directory -Path $Primary -Force | Out-Null
            Set-Content -LiteralPath $SourcePath -Value 'archive-bytes' -Encoding UTF8
            $sourceItem = Get-Item -LiteralPath $SourcePath
            $hash = Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256
            $tiers = ConvertTo-BackupProjectStorageTier `
                -StorageTier @(
                    @{
                        Name = 'Fast SSD'
                        Profile = 'FastSSD'
                        Path = $Primary
                        Required = $true
                        RetryDelaySeconds = 0
                    }
                    @{
                        Name = 'Required Cloud Copy'
                        Profile = 'CloudS3'
                        Uri = 's3://renderkit-required/backup.zip'
                        Required = $true
                        RetryDelaySeconds = 0
                    }
                ) `
                -DestinationRoot $Primary `
                -ArchivePath $SourcePath
            $cascade = New-BackupStorageCascadePlan -StorageTiers @($tiers)
            Invoke-BackupStorageTierCopyVerifyChain `
                -ArchivePath $SourcePath `
                -StorageTiers @($tiers) `
                -StorageCascade $cascade `
                -ExpectedHash ([string]$hash.Hash) `
                -ExpectedSizeBytes ([int64]$sourceItem.Length) `
                -Algorithm SHA256 `
                -ArchiveIntegrityPassed $true
        }

        $blocked.state | Should -Be 'Blocked'
        $blocked.release.canReleaseSource | Should -BeFalse
        $blocked.release.failedRequiredTierIds | Should -Contain 'tier-2'
        $blocked.tiers[1].state | Should -Be 'AdapterRequired'
    }

    It 'adds failure-recovery policy and custom chunk retry limits to queued jobs' {
        $projectParent = Join-Path $TestDrive 'failure-policy-projects'
        $projectRoot = Join-Path $projectParent 'FailurePolicyProject'
        $metadataRoot = Join-Path $projectRoot '.renderkit'
        New-Item -ItemType Directory -Path $metadataRoot -Force | Out-Null
        Set-Content `
            -LiteralPath (Join-Path $projectRoot 'notes.txt') `
            -Value 'notes' `
            -Encoding UTF8
        [PSCustomObject]@{
            tool = 'RenderKit'
            schemaVersion = '1.0'
            project = [PSCustomObject]@{
                id = 'failure-policy-project'
                name = 'FailurePolicyProject'
                createdAt = (Get-Date).ToString('o')
            }
            lifecycle = [PSCustomObject]@{
                status = 'Draft'
            }
        } |
            ConvertTo-Json -Depth 8 |
            Set-Content `
                -LiteralPath (Join-Path $metadataRoot 'project.json') `
                -Encoding UTF8

        $queued = Backup-Project `
            -ProjectName FailurePolicyProject `
            -Path $projectParent `
            -Background `
            -KeepSourceProject `
            -SimulateFailure CorruptChunk `
            -MaxChunkRetryAttempts 4 `
            -ChunkRetryDelaySeconds 0 `
            -SimulatedFailureCount 2

        $queued.Payload.failureRecovery.enabled | Should -BeTrue
        $queued.Payload.failureRecovery.strategy |
            Should -Be 'DetectClassifyRetryOrBlockRelease'
        $queued.Payload.failureRecovery.simulation.scenarios |
            Should -Contain 'CorruptChunk'
        $queued.Payload.failureRecovery.simulation.failAttempts |
            Should -Be 2
        $queued.Payload.control.retry.maxAttemptsPerChunk |
            Should -Be 4
        $queued.Payload.control.retry.retryDelaySeconds |
            Should -Be 0
        $queued.Payload.advancedFeatures.failureRecovery.retry.chunk.maxAttempts |
            Should -Be 4
    }

    It 'classifies missing targets and full disks before storage copy starts' {
        $health = InModuleScope RenderKit -Parameters @{
            TargetPath = (Join-Path $TestDrive 'failure-health-target')
        } {
            $tiers = ConvertTo-BackupProjectStorageTier `
                -StorageTier @(
                    @{
                        Name = 'Fast SSD'
                        Profile = 'FastSSD'
                        Path = $TargetPath
                        Required = $true
                    }
                ) `
                -DestinationRoot $TargetPath
            $missingPolicy = New-BackupFailureRecoveryPolicy `
                -SimulateFailure MissingTarget
            $missingTiers = Set-BackupFailureSimulationOnStorageTiers `
                -StorageTiers @($tiers) `
                -Simulation $missingPolicy.simulation
            $missing = Test-BackupStorageTierHealth `
                -Tier $missingTiers[0] `
                -RequiredBytes 1024 `
                -CreateTargetRoot

            $fullPolicy = New-BackupFailureRecoveryPolicy `
                -SimulateFailure FullDisk
            $fullTiers = Set-BackupFailureSimulationOnStorageTiers `
                -StorageTiers @($tiers) `
                -Simulation $fullPolicy.simulation
            $full = Test-BackupStorageTierHealth `
                -Tier $fullTiers[0] `
                -RequiredBytes 1024 `
                -CreateTargetRoot

            [PSCustomObject]@{
                missing = $missing
                full    = $full
            }
        }

        $health.missing.healthy | Should -BeFalse
        $health.missing.reason | Should -Be 'MissingTarget'
        $health.missing.failureClass.category |
            Should -Be 'MissingStorageTarget'
        $health.full.healthy | Should -BeFalse
        $health.full.state | Should -Be 'InsufficientSpace'
        $health.full.reason | Should -Be 'InsufficientFreeSpace'
        $health.full.failureClass.category |
            Should -Be 'InsufficientStorageCapacity'
    }

    It 'retries a transient storage copy failure and verifies the tier' {
        $verified = InModuleScope RenderKit -Parameters @{
            SourcePath = (Join-Path $TestDrive 'transient-primary\backup.zip')
            Primary   = (Join-Path $TestDrive 'transient-primary')
        } {
            New-Item -ItemType Directory -Path $Primary -Force | Out-Null
            Set-Content -LiteralPath $SourcePath -Value 'archive-bytes' -Encoding UTF8
            $sourceItem = Get-Item -LiteralPath $SourcePath
            $hash = Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256
            $tiers = ConvertTo-BackupProjectStorageTier `
                -StorageTier @(
                    @{
                        Name = 'Fast SSD'
                        Profile = 'FastSSD'
                        Path = $Primary
                        Required = $true
                        MaxRetries = 2
                        RetryDelaySeconds = 0
                    }
                ) `
                -DestinationRoot $Primary `
                -ArchivePath $SourcePath
            $policy = New-BackupFailureRecoveryPolicy `
                -SimulateFailure TransientStorageCopy `
                -SimulatedFailureCount 1
            $tiers = Set-BackupFailureSimulationOnStorageTiers `
                -StorageTiers @($tiers) `
                -Simulation $policy.simulation
            $cascade = New-BackupStorageCascadePlan -StorageTiers @($tiers)
            Invoke-BackupStorageTierCopyVerifyChain `
                -ArchivePath $SourcePath `
                -StorageTiers @($tiers) `
                -StorageCascade $cascade `
                -ExpectedHash ([string]$hash.Hash) `
                -ExpectedSizeBytes ([int64]$sourceItem.Length) `
                -Algorithm SHA256 `
                -ArchiveIntegrityPassed $true
        }

        $verified.state | Should -Be 'Verified'
        $verified.tiers[0].verified | Should -BeTrue
        $verified.tiers[0].attempts.Count | Should -Be 2
        $verified.tiers[0].attempts[0].state | Should -Be 'Failed'
        $verified.tiers[0].attempts[0].failureClass.scenario |
            Should -Be 'TransientStorageCopy'
        $verified.tiers[0].attempts[1].state | Should -Be 'Verified'
        $verified.release.canReleaseSource | Should -BeTrue
    }

    It 'allows safe delete only after archive, decode, and tier checks pass' {
        $decision = InModuleScope RenderKit {
            $policy = New-BackupSafeDeletePolicy -RequiredStorageTierIds @('tier-1', 'tier-2')
            Test-BackupSafeDeletePolicy `
                -Policy $policy `
                -ArchiveInfo ([PSCustomObject]@{
                    contentIntegrity = [PSCustomObject]@{
                        checked = $true
                        isMatch = $true
                    }
                }) `
                -StorageVerification ([PSCustomObject]@{
                    state = 'Verified'
                    release = [PSCustomObject]@{
                        canReleaseSource = $true
                        primaryTierVerified = $true
                        failedRequiredTierIds = @()
                    }
                    tiers = @(
                        [PSCustomObject]@{ tierId = 'tier-1'; verified = $true }
                        [PSCustomObject]@{ tierId = 'tier-2'; verified = $true }
                    )
                }) `
                -MergeValidations @(
                    [PSCustomObject]@{
                        assetId = 'main'
                        succeeded = $true
                    }
                ) `
                -DryRun $false `
                -DeleteRequested $true
        }

        $decision.state | Should -Be 'Allowed'
        $decision.canDelete | Should -BeTrue
        $decision.reason | Should -Be 'SafeDeleteChecksPassed'
        $decision.failedRules.Count | Should -Be 0
        $decision.passedRules.reason | Should -Contain 'DecodeValidationPassed'
    }

    It 'blocks safe delete when decode validation fails' {
        $decision = InModuleScope RenderKit {
            $policy = New-BackupSafeDeletePolicy -RequiredStorageTierIds @('tier-1')
            Test-BackupSafeDeletePolicy `
                -Policy $policy `
                -ArchiveInfo ([PSCustomObject]@{
                    contentIntegrity = [PSCustomObject]@{
                        checked = $true
                        isMatch = $true
                    }
                }) `
                -StorageVerification ([PSCustomObject]@{
                    state = 'Verified'
                    release = [PSCustomObject]@{
                        canReleaseSource = $true
                        primaryTierVerified = $true
                        failedRequiredTierIds = @()
                    }
                    tiers = @(
                        [PSCustomObject]@{ tierId = 'tier-1'; verified = $true }
                    )
                }) `
                -MergeValidations @(
                    [PSCustomObject]@{
                        assetId = 'main'
                        succeeded = $false
                    }
                ) `
                -DryRun $false `
                -DeleteRequested $true
        }

        $decision.state | Should -Be 'Blocked'
        $decision.canDelete | Should -BeFalse
        $decision.failedRules.reason | Should -Contain 'DecodeValidationFailed'
        $decision.evidence.decodeValidation.failedAssetIds | Should -Contain 'main'
    }

    It 'blocks safe delete when the policy keeps the source' {
        $decision = InModuleScope RenderKit {
            $policy = New-BackupSafeDeletePolicy -Mode KeepSource -RequiredStorageTierIds @('tier-1')
            Test-BackupSafeDeletePolicy `
                -Policy $policy `
                -ArchiveInfo ([PSCustomObject]@{
                    contentIntegrity = [PSCustomObject]@{
                        checked = $true
                        isMatch = $true
                    }
                }) `
                -StorageVerification ([PSCustomObject]@{
                    state = 'Verified'
                    release = [PSCustomObject]@{
                        canReleaseSource = $true
                        primaryTierVerified = $true
                        failedRequiredTierIds = @()
                    }
                    tiers = @(
                        [PSCustomObject]@{ tierId = 'tier-1'; verified = $true }
                    )
                }) `
                -MergeValidations @() `
                -DryRun $false `
                -DeleteRequested $true
        }

        $decision.state | Should -Be 'Blocked'
        $decision.canDelete | Should -BeFalse
        $decision.failedRules.reason | Should -Contain 'PolicyKeepsSource'
    }

    It 'plans hash-based deduplication groups and archive exclusions' {
        $plan = InModuleScope RenderKit -Parameters @{
            Root = (Join-Path $TestDrive 'dedup-plan')
        } {
            New-Item -ItemType Directory -Path (Join-Path $Root 'Media') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $Root 'Media\a.mov') -Value 'same-bytes' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $Root 'Media\b.mov') -Value 'same-bytes' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $Root 'Media\c.mov') -Value 'unique-bytes' -Encoding UTF8

            $index = Get-BackupFileHashIndex `
                -RootPath $Root `
                -BasePath $Root `
                -Algorithm SHA256
            New-BackupDeduplicationPlan `
                -SourceIndex $index `
                -Policy (New-BackupDeduplicationPolicy)
        }

        $plan.enabled | Should -BeTrue
        $plan.summary.sourceFileCount | Should -Be 3
        $plan.summary.uniqueFileCount | Should -Be 2
        $plan.summary.duplicateFileCount | Should -Be 1
        $plan.summary.duplicateGroupCount | Should -Be 1
        $plan.archive.excludedRelativePaths | Should -Contain 'Media/b.mov'
        $plan.groups[0].canonicalRelativePath | Should -Be 'Media/a.mov'
        $plan.groups[0].duplicateRelativePaths | Should -Contain 'Media/b.mov'
    }

    It 'archives only canonical duplicate content and verifies with dedup references' {
        $result = InModuleScope RenderKit -Parameters @{
            Root = (Join-Path $TestDrive 'dedup-archive\ProjectA')
            Archive = (Join-Path $TestDrive 'dedup-archive\ProjectA.zip')
        } {
            New-Item -ItemType Directory -Path (Join-Path $Root 'Media') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $Root 'Media\a.mov') -Value 'same-bytes' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $Root 'Media\b.mov') -Value 'same-bytes' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $Root 'Media\c.mov') -Value 'unique-bytes' -Encoding UTF8

            $index = Get-BackupFileHashIndex `
                -RootPath $Root `
                -BasePath $Root `
                -Algorithm SHA256
            $dedup = New-BackupDeduplicationPlan `
                -SourceIndex $index `
                -Policy (New-BackupDeduplicationPolicy)
            $archiveResult = Compress-Project `
                -ProjectPath $Root `
                -DestinationPath $Archive `
                -DeduplicationPlan $dedup
            $verified = Test-BackupArchiveContentIntegrity `
                -ProjectPath $Root `
                -ArchivePath $Archive `
                -SourceIndex $index `
                -DeduplicationPlan $dedup `
                -Algorithm SHA256
            $zip = [System.IO.Compression.ZipFile]::OpenRead($Archive)
            try {
                $entries = @($zip.Entries | ForEach-Object { [string]$_.FullName })
            }
            finally {
                $zip.Dispose()
            }

            [PSCustomObject]@{
                archiveResult = $archiveResult
                verified = $verified
                entries = @($entries)
                dedup = $dedup
            }
        }

        $result.archiveResult.SourceFileCount | Should -Be 3
        $result.archiveResult.ArchivedFileCount | Should -Be 2
        $result.archiveResult.DeduplicatedFileCount | Should -Be 1
        $result.verified.IsMatch | Should -BeTrue
        $result.verified.DeduplicatedInArchiveCount | Should -Be 1
        $result.verified.DeduplicationMismatchCount | Should -Be 0
        $result.entries | Should -Contain 'ProjectA/Media/a.mov'
        $result.entries | Should -Not -Contain 'ProjectA/Media/b.mov'
    }

    It 'removes the source project only after the storage verify chain succeeds' {
        $projectParent = Join-Path $TestDrive 'verify-projects'
        $projectRoot = Join-Path $projectParent 'VerifyProject'
        $metadataRoot = Join-Path $projectRoot '.renderkit'
        $primary = Join-Path $TestDrive 'verify-primary'
        $secondary = Join-Path $TestDrive 'verify-secondary'
        New-Item -ItemType Directory -Path $metadataRoot -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $projectRoot 'Media') -Force | Out-Null
        Set-Content `
            -LiteralPath (Join-Path $projectRoot 'notes.txt') `
            -Value 'notes' `
            -Encoding UTF8
        Set-Content `
            -LiteralPath (Join-Path $projectRoot 'Media\a.mov') `
            -Value 'same-media-bytes' `
            -Encoding UTF8
        Set-Content `
            -LiteralPath (Join-Path $projectRoot 'Media\b.mov') `
            -Value 'same-media-bytes' `
            -Encoding UTF8
        [PSCustomObject]@{
            tool = 'RenderKit'
            schemaVersion = '1.0'
            project = [PSCustomObject]@{
                id = 'verify-project'
                name = 'VerifyProject'
                createdAt = (Get-Date).ToString('o')
            }
            lifecycle = [PSCustomObject]@{
                status = 'Draft'
            }
        } |
            ConvertTo-Json -Depth 8 |
            Set-Content `
                -LiteralPath (Join-Path $metadataRoot 'project.json') `
                -Encoding UTF8

        $result = Backup-Project `
            -ProjectName VerifyProject `
            -Path $projectParent `
            -DestinationRoot $primary `
            -StorageTier @(
                @{
                    Name = 'Fast SSD'
                    Profile = 'FastSSD'
                    Path = $primary
                    Required = $true
                    RetryDelaySeconds = 0
                }
                @{
                    Name = 'HDD'
                    Profile = 'HDD'
                    Path = $secondary
                    Required = $true
                    RetryDelaySeconds = 0
                }
            )

        $result.SourceRemoved | Should -BeTrue
        Test-Path -LiteralPath $projectRoot | Should -BeFalse
        Test-Path -LiteralPath $result.BackupPath | Should -BeTrue
        $secondaryArchive = Join-Path $secondary (Split-Path -Path $result.BackupPath -Leaf)
        Test-Path -LiteralPath $secondaryArchive | Should -BeTrue
        $result.Archive.storageVerification.release.canReleaseSource | Should -BeTrue
        $result.Archive.storageVerification.summary.verifiedTierCount | Should -Be 2
        $result.Archive.storageVerification.tiers[1].targetHash |
            Should -Be $result.Archive.hash
        $result.Archive.safeDelete.state | Should -Be 'Allowed'
        $result.Archive.safeDelete.canDelete | Should -BeTrue
        $result.Archive.safeDelete.failedRules.Count | Should -Be 0
        $result.Archive.deduplication.summary.duplicateFileCount | Should -Be 1
        $result.Archive.contentIntegrity.deduplicatedInArchiveCount | Should -Be 1
        $result.Statistics.deduplication.estimatedSavedBytes | Should -BeGreaterThan 0
        $result.Reports.state | Should -Be 'Written'
        $result.Reports.summary.writtenCount | Should -Be 3
        $jsonReport = @($result.Reports.files | Where-Object { $_.format -eq 'Json' })[0]
        $htmlReport = @($result.Reports.files | Where-Object { $_.format -eq 'Html' })[0]
        $textReport = @($result.Reports.files | Where-Object { $_.format -eq 'Text' })[0]
        Test-Path -LiteralPath $jsonReport.path | Should -BeTrue
        Test-Path -LiteralPath $htmlReport.path | Should -BeTrue
        Test-Path -LiteralPath $textReport.path | Should -BeTrue

        $json = Get-Content -LiteralPath $jsonReport.path -Raw | ConvertFrom-Json
        $json.kind | Should -Be 'BackupAuditReport'
        $json.source.removed | Should -BeTrue
        $json.source.checksums.Count | Should -BeGreaterThan 0
        $json.targets.tiers.Count | Should -Be 2
        $json.archive.hash | Should -Be $result.Archive.hash
        $json.savings.deduplicatedBytes | Should -BeGreaterThan 0
        (Get-Content -LiteralPath $htmlReport.path -Raw) |
            Should -Match 'RenderKit Backup Audit Report'
        (Get-Content -LiteralPath $textReport.path -Raw) |
            Should -Match 'SourceChecksums'
    }

    It 'records pause, resume, and cancel requests for a background BackupProject job' {
        $projectParent = Join-Path $TestDrive 'control-projects'
        $projectRoot = Join-Path $projectParent 'ControlProject'
        $metadataRoot = Join-Path $projectRoot '.renderkit'
        New-Item -ItemType Directory -Path $metadataRoot -Force | Out-Null
        Set-Content `
            -LiteralPath (Join-Path $projectRoot 'notes.txt') `
            -Value 'notes' `
            -Encoding UTF8
        [PSCustomObject]@{
            tool = 'RenderKit'
            schemaVersion = '1.0'
            project = [PSCustomObject]@{
                id = 'control-project'
                name = 'ControlProject'
                createdAt = (Get-Date).ToString('o')
            }
            lifecycle = [PSCustomObject]@{
                status = 'Draft'
            }
        } |
            ConvertTo-Json -Depth 8 |
            Set-Content `
                -LiteralPath (Join-Path $metadataRoot 'project.json') `
                -Encoding UTF8

        $queued = Backup-Project `
            -ProjectName ControlProject `
            -Path $projectParent `
            -Background `
            -KeepSourceProject

        $queued.Commands.Status | Should -Match 'Get-BackupJob'
        $queued.Commands.Watch | Should -Match 'Get-BackupJob'
        $queued.Commands.Pause | Should -Match 'Pause-BackupJob'
        $queued.Commands.Worker | Should -Match 'MaxJobs 1'
        $status = Get-BackupJob -JobId $queued.JobId
        $status.JobId | Should -Be $queued.JobId
        $status.Status | Should -Be 'Queued'
        $status.ProjectName | Should -Be 'ControlProject'
        $status.ArchivePath | Should -Be $queued.ArchivePath
        $status.ControlState | Should -Be 'Running'
        $status.Paths.progressStatePath | Should -Be $queued.Payload.progress.statePath

        $pause = Pause-BackupJob `
            -JobId $queued.JobId `
            -Reason 'test pause'
        $pause.state | Should -Be 'PauseRequested'
        $pause.reason | Should -Be 'test pause'

        $resume = Resume-BackupJob `
            -JobId $queued.JobId `
            -Reason 'test resume'
        $resume.state | Should -Be 'ResumeRequested'
        $resume.reason | Should -Be 'test resume'

        $cancel = Stop-BackupJob `
            -JobId $queued.JobId `
            -Reason 'test cancel'
        $cancel.state | Should -Be 'CancelRequested'
        $cancel.reason | Should -Be 'test cancel'

        $controlState = Get-Content `
            -LiteralPath $queued.Payload.control.statePath `
            -Raw |
            ConvertFrom-Json
        $job = InModuleScope RenderKit -Parameters @{ JobId = $queued.JobId } {
            Get-RenderKitJob -JobId $JobId
        }

        $controlState.state | Should -Be 'CancelRequested'
        $job.status | Should -Be 'Cancelled'
        $job.cancelRequestedAtUtc | Should -Not -BeNullOrEmpty
    }

    It 'turns abort simulation into a cancelled worker job' {
        $projectParent = Join-Path $TestDrive 'abort-simulation-projects'
        $projectRoot = Join-Path $projectParent 'AbortSimulationProject'
        $metadataRoot = Join-Path $projectRoot '.renderkit'
        New-Item -ItemType Directory -Path $metadataRoot -Force | Out-Null
        Set-Content `
            -LiteralPath (Join-Path $projectRoot 'notes.txt') `
            -Value 'notes' `
            -Encoding UTF8
        [PSCustomObject]@{
            tool = 'RenderKit'
            schemaVersion = '1.0'
            project = [PSCustomObject]@{
                id = 'abort-simulation-project'
                name = 'AbortSimulationProject'
                createdAt = (Get-Date).ToString('o')
            }
            lifecycle = [PSCustomObject]@{
                status = 'Draft'
            }
        } |
            ConvertTo-Json -Depth 8 |
            Set-Content `
                -LiteralPath (Join-Path $metadataRoot 'project.json') `
                -Encoding UTF8

        $queued = Backup-Project `
            -ProjectName AbortSimulationProject `
            -Path $projectParent `
            -Background `
            -KeepSourceProject `
            -SimulateFailure AbortRequested

        $job = InModuleScope RenderKit -Parameters @{ JobId = $queued.JobId } {
            Invoke-RenderKitJob -JobId $JobId
        }
        $controlState = Get-Content `
            -LiteralPath $queued.Payload.control.statePath `
            -Raw |
            ConvertFrom-Json

        $job.status | Should -Be 'Cancelled'
        $job.progress.phase | Should -Be 'Cancelled'
        $controlState.state | Should -Be 'CancelRequested'
        $controlState.reason | Should -Match 'Simulated abort requested'
    }

    It 'analyzes project media files without requiring ffprobe' {
        $projectRoot = Join-Path $TestDrive 'AnalysisProject'
        New-Item -ItemType Directory -Path (Join-Path $projectRoot 'Media') -Force | Out-Null
        Set-Content `
            -LiteralPath (Join-Path $projectRoot 'Media\clip.mp4') `
            -Value 'video-placeholder' `
            -Encoding UTF8
        Set-Content `
            -LiteralPath (Join-Path $projectRoot 'Media\still.jpg') `
            -Value 'image-placeholder' `
            -Encoding UTF8
        Set-Content `
            -LiteralPath (Join-Path $projectRoot 'notes.txt') `
            -Value 'notes' `
            -Encoding UTF8

        $analysis = InModuleScope RenderKit -Parameters @{ Root = $projectRoot } {
            Get-BackupMediaAnalysis -ProjectRoot $Root
        }

        $analysis.summary.fileCount | Should -Be 3
        $analysis.summary.mediaFileCount | Should -Be 2
        $analysis.summary.videoFileCount | Should -Be 1
        $analysis.summary.imageFileCount | Should -Be 1
        $analysis.probe.requested | Should -BeFalse
        @($analysis.files | Where-Object { $_.relativePath -eq 'Media/clip.mp4' })[0].mediaType |
            Should -Be 'Video'
    }

    It 'plans resumable time-range chunks for timed media' {
        $chunkPlan = InModuleScope RenderKit {
            $analysis = [PSCustomObject]@{
                files = @(
                    [PSCustomObject]@{
                        relativePath = 'Media/main.mp4'
                        path = 'D:\Projects\ClientA\Media\main.mp4'
                        mediaType = 'Video'
                        sizeBytes = [int64]60000000000
                        isChunkable = $true
                        metadata = [PSCustomObject]@{
                            durationSeconds = 125.0
                        }
                    }
                    [PSCustomObject]@{
                        relativePath = 'Media/still.jpg'
                        path = 'D:\Projects\ClientA\Media\still.jpg'
                        mediaType = 'Image'
                        sizeBytes = [int64]1024
                        isChunkable = $false
                        metadata = [PSCustomObject]@{
                            durationSeconds = $null
                        }
                    }
                )
            }

            New-BackupChunkPlan `
                -MediaAnalysis $analysis `
                -ChunkDurationSeconds 60 `
                -Enabled
        }

        $chunkPlan.enabled | Should -BeTrue
        $chunkPlan.summary.assetCount | Should -Be 2
        $chunkPlan.summary.chunkableAssetCount | Should -Be 1
        $chunkPlan.summary.chunkCount | Should -Be 3
        $chunkPlan.summary.passThroughFileCount | Should -Be 1
        $chunkPlan.chunks[0].startSeconds | Should -Be 0
        $chunkPlan.chunks[1].startSeconds | Should -Be 60
        $chunkPlan.chunks[2].durationSeconds | Should -Be 5
        $chunkPlan.chunks[0].resumeKey | Should -Not -BeNullOrEmpty
        $chunkPlan.segmentation.boundaryStrategy |
            Should -Be 'KeyframeAwareWithEstimatedFallback'
        $chunkPlan.index.entries.Count | Should -Be 3
        $chunkPlan.chunks[0].audioSync.actionOnDrift |
            Should -Be 'FailChunkAndRetry'
        $chunkPlan.chunks[0].gop.strategy |
            Should -Be 'ReencodeWithBoundaryKeyframes'
    }

    It 'snaps chunk boundaries to nearby keyframes when available' {
        $chunkPlan = InModuleScope RenderKit {
            $analysis = [PSCustomObject]@{
                files = @(
                    [PSCustomObject]@{
                        relativePath = 'Media/main.mp4'
                        path = 'D:\Projects\ClientA\Media\main.mp4'
                        mediaType = 'Video'
                        sizeBytes = [int64]60000000000
                        isChunkable = $true
                        metadata = [PSCustomObject]@{
                            durationSeconds = 125.0
                            keyframes = @(0.0, 58.0, 120.0, 125.0)
                        }
                    }
                )
            }

            New-BackupChunkPlan `
                -MediaAnalysis $analysis `
                -ChunkDurationSeconds 60 `
                -Enabled
        }

        $chunkPlan.strategy | Should -Be 'KeyframeAwareTimeRange'
        $chunkPlan.assets[0].segmentation.mode |
            Should -Be 'KeyframeAwareTimeRange'
        $chunkPlan.assets[0].segmentation.gopStrategy |
            Should -Be 'SnapBoundariesToKeyframes'
        $chunkPlan.summary.chunkCount | Should -Be 3
        $chunkPlan.chunks[1].startSeconds | Should -Be 58
        $chunkPlan.chunks[1].segment.startBoundarySource |
            Should -Be 'Keyframe'
        $chunkPlan.chunks[1].segment.startKeyframeAligned |
            Should -BeTrue
        $chunkPlan.chunks[1].durationSeconds | Should -Be 62
        $chunkPlan.index.entries[1].startSeconds | Should -Be 58
    }

    It 'builds ffmpeg encode and merge plans for chunked assets' {
        $plan = InModuleScope RenderKit {
            $payload = [PSCustomObject]@{
                archive = [PSCustomObject]@{
                    mode = 'TranscodeAndArchive'
                    compressionPreset = 'Balanced'
                }
                encoding = [PSCustomObject]@{
                    videoCodec = 'H265'
                    encoderDevice = 'CPU'
                    qualityPreset = 'High'
                    audioProfile = 'AAC_192'
                    proxy = [PSCustomObject]@{ enabled = $true; height = 720 }
                    preview = [PSCustomObject]@{ enabled = $true; format = 'jpg'; intervalSeconds = 30; width = 960 }
                }
                mediaAnalysis = [PSCustomObject]@{
                    files = @(
                        [PSCustomObject]@{
                            relativePath = 'Media/main.mp4'
                            path = 'D:\Projects\ClientA\Media\main.mp4'
                            mediaType = 'Video'
                            metadata = [PSCustomObject]@{
                                durationSeconds = 90.0
                                format = 'mov,mp4,m4a,3gp,3g2,mj2'
                                videoStreams = @(
                                    [PSCustomObject]@{
                                        index = 0
                                        codec = 'h264'
                                    }
                                )
                                audioStreams = @(
                                    [PSCustomObject]@{
                                        index = 1
                                        codec = 'aac'
                                    }
                                )
                                hasVideo = $true
                                hasAudio = $true
                            }
                        }
                    )
                }
                chunkPlan = [PSCustomObject]@{
                    assets = @(
                        [PSCustomObject]@{
                            id = 'asset-main'
                            relativePath = 'Media/main.mp4'
                            path = 'D:\Projects\ClientA\Media\main.mp4'
                            mediaType = 'Video'
                        }
                    )
                    chunks = @(
                        [PSCustomObject]@{
                            id = 'chunk-main-000000'
                            assetId = 'asset-main'
                            relativePath = 'Media/main.mp4'
                            index = 0
                            startSeconds = 0.0
                            durationSeconds = 60.0
                            audioSync = [PSCustomObject]@{
                                maxDriftMilliseconds = 50
                            }
                        }
                        [PSCustomObject]@{
                            id = 'chunk-main-000001'
                            assetId = 'asset-main'
                            relativePath = 'Media/main.mp4'
                            index = 1
                            startSeconds = 60.0
                            durationSeconds = 30.0
                            audioSync = [PSCustomObject]@{
                                maxDriftMilliseconds = 50
                            }
                        }
                    )
                }
            }
            $job = [PSCustomObject]@{
                id = 'job-encode-plan'
                payload = $payload
            }

            New-BackupEncodingPlan -Job $job -Payload $payload
        }

        $plan.profile.videoCodec | Should -Be 'H265'
        $plan.profile.encoderDevice | Should -Be 'CPU'
        $plan.profile.encoderName | Should -Be 'libx265'
        $plan.profile.encoderSelection.source | Should -Be 'UserRequested'
        $plan.gpuDetection.capabilities.cache.enabled | Should -BeTrue
        $plan.gpuDetection.selection.device | Should -Be 'CPU'
        $plan.profile.qualityPreset | Should -Be 'High'
        $plan.profile.audioProfile | Should -Be 'AAC_192'
        $plan.summary.commandCount | Should -Be 2
        $plan.summary.mergeCount | Should -Be 1
        $plan.summary.mergeValidationCount | Should -Be 1
        $plan.summary.requiresFfprobe | Should -BeTrue
        $plan.summary.proxyCommandCount | Should -Be 1
        $plan.summary.previewCommandCount | Should -Be 1
        $plan.commands[0].arguments | Should -Contain '-progress'
        $plan.commands[0].arguments | Should -Contain 'pipe:1'
        $plan.commands[0].progress.stageName | Should -Be 'Encoding'
        $plan.commands[0].progress.logPath | Should -Match 'ffprogress\.log'
        $plan.commands[0].arguments | Should -Contain 'libx265'
        $plan.commands[0].arguments | Should -Contain '192k'
        $plan.commands[0].outputPath | Should -Match 'encoded'
        $plan.merges[0].arguments | Should -Contain 'concat'
        $plan.merges[0].arguments | Should -Contain '-progress'
        $plan.merges[0].progress.stageName | Should -Be 'Merging'
        $plan.merges[0].validation.expectedDurationSeconds | Should -Be 90
        $plan.merges[0].validation.expectedVideo | Should -BeTrue
        $plan.merges[0].validation.expectedAudio | Should -BeTrue
        $plan.merges[0].validation.syncPolicy | Should -Be 'DurationDriftWithinTolerance'
        $plan.proxyCommands[0].arguments | Should -Contain 'libx264'
        $plan.proxyCommands[0].arguments | Should -Contain '-progress'
        $plan.previewCommands[0].arguments | Should -Contain 'fps=1/30,scale=960:-2'
        $plan.previewCommands[0].arguments | Should -Contain '-progress'
    }

    It 'injects corrupt chunk simulations into retryable encode commands' {
        $plan = InModuleScope RenderKit {
            $payload = [PSCustomObject]@{
                archive = [PSCustomObject]@{
                    mode = 'TranscodeAndArchive'
                    compressionPreset = 'Balanced'
                }
                control = [PSCustomObject]@{
                    retry = [PSCustomObject]@{
                        maxAttemptsPerChunk = 4
                        retryDelaySeconds = 0
                    }
                }
                failureRecovery = New-BackupFailureRecoveryPolicy `
                    -SimulateFailure CorruptChunk `
                    -MaxChunkRetryAttempts 4 `
                    -ChunkRetryDelaySeconds 0 `
                    -SimulatedFailureCount 2
                encoding = [PSCustomObject]@{
                    videoCodec = 'H265'
                    encoderDevice = 'CPU'
                    qualityPreset = 'Balanced'
                    audioProfile = 'AAC_128'
                    proxy = [PSCustomObject]@{ enabled = $false }
                    preview = [PSCustomObject]@{ enabled = $false }
                }
                mediaAnalysis = [PSCustomObject]@{
                    files = @(
                        [PSCustomObject]@{
                            relativePath = 'Media/main.mp4'
                            path = 'D:\Projects\ClientA\Media\main.mp4'
                            mediaType = 'Video'
                            metadata = [PSCustomObject]@{
                                durationSeconds = 60.0
                                videoStreams = @([PSCustomObject]@{ index = 0; codec = 'h264' })
                                audioStreams = @([PSCustomObject]@{ index = 1; codec = 'aac' })
                                hasVideo = $true
                                hasAudio = $true
                            }
                        }
                    )
                }
                chunkPlan = [PSCustomObject]@{
                    assets = @(
                        [PSCustomObject]@{
                            id = 'asset-main'
                            relativePath = 'Media/main.mp4'
                            path = 'D:\Projects\ClientA\Media\main.mp4'
                            mediaType = 'Video'
                        }
                    )
                    chunks = @(
                        [PSCustomObject]@{
                            id = 'chunk-main-000000'
                            assetId = 'asset-main'
                            relativePath = 'Media/main.mp4'
                            index = 0
                            startSeconds = 0.0
                            durationSeconds = 60.0
                        }
                    )
                }
            }
            $job = [PSCustomObject]@{
                id = 'job-corrupt-chunk-plan'
                payload = $payload
            }

            New-BackupEncodingPlan -Job $job -Payload $payload
        }

        $plan.commands[0].failureSimulation.scenarios |
            Should -Contain 'CorruptChunk'
        $plan.commands[0].failureSimulation.failAttempts |
            Should -Be 2
        $plan.commands[0].control.retryable | Should -BeTrue
        $plan.commands[0].control.maxAttempts | Should -Be 4
        $plan.commands[0].control.retryDelaySeconds | Should -Be 0
    }

    It 'skips completed chunk-index entries when rebuilding an encoding plan' {
        $encodedOutput = Join-Path $TestDrive 'already-encoded-chunk.mkv'
        Set-Content -LiteralPath $encodedOutput -Value 'encoded' -Encoding UTF8

        $plan = InModuleScope RenderKit -Parameters @{ OutputPath = $encodedOutput } {
            $jobId = 'job-resume-plan'
            Save-BackupChunkIndex `
                -JobId $jobId `
                -ChunkIndex ([PSCustomObject]@{
                    entries = @(
                        [PSCustomObject]@{
                            chunkId = 'chunk-main-000000'
                            resumeKey = 'chunk-main-000000'
                            assetId = 'asset-main'
                            relativePath = 'Media/main.mp4'
                            index = 0
                            state = 'Completed'
                            attempts = 2
                            outputPath = $OutputPath
                            completedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
                        }
                        [PSCustomObject]@{
                            chunkId = 'chunk-main-000001'
                            resumeKey = 'chunk-main-000001'
                            assetId = 'asset-main'
                            relativePath = 'Media/main.mp4'
                            index = 1
                            state = 'Pending'
                            attempts = 0
                            outputPath = $null
                            completedAtUtc = $null
                        }
                    )
                }) |
                Out-Null

            $payload = [PSCustomObject]@{
                archive = [PSCustomObject]@{
                    mode = 'TranscodeAndArchive'
                    compressionPreset = 'Balanced'
                }
                control = [PSCustomObject]@{
                    retry = [PSCustomObject]@{
                        maxAttemptsPerChunk = 3
                        retryDelaySeconds = 1
                    }
                }
                encoding = [PSCustomObject]@{
                    videoCodec = 'H265'
                    encoderDevice = 'CPU'
                    qualityPreset = 'Balanced'
                    audioProfile = 'AAC_128'
                    proxy = [PSCustomObject]@{ enabled = $false }
                    preview = [PSCustomObject]@{ enabled = $false }
                }
                mediaAnalysis = [PSCustomObject]@{
                    files = @(
                        [PSCustomObject]@{
                            relativePath = 'Media/main.mp4'
                            path = 'D:\Projects\ClientA\Media\main.mp4'
                            mediaType = 'Video'
                            metadata = [PSCustomObject]@{
                                durationSeconds = 90.0
                                videoStreams = @([PSCustomObject]@{ index = 0; codec = 'h264' })
                                audioStreams = @([PSCustomObject]@{ index = 1; codec = 'aac' })
                                hasVideo = $true
                                hasAudio = $true
                            }
                        }
                    )
                }
                chunkPlan = [PSCustomObject]@{
                    assets = @(
                        [PSCustomObject]@{
                            id = 'asset-main'
                            relativePath = 'Media/main.mp4'
                            path = 'D:\Projects\ClientA\Media\main.mp4'
                            mediaType = 'Video'
                        }
                    )
                    chunks = @(
                        [PSCustomObject]@{
                            id = 'chunk-main-000000'
                            assetId = 'asset-main'
                            relativePath = 'Media/main.mp4'
                            index = 0
                            startSeconds = 0.0
                            durationSeconds = 60.0
                        }
                        [PSCustomObject]@{
                            id = 'chunk-main-000001'
                            assetId = 'asset-main'
                            relativePath = 'Media/main.mp4'
                            index = 1
                            startSeconds = 60.0
                            durationSeconds = 30.0
                        }
                    )
                }
            }

            New-BackupEncodingPlan `
                -Job ([PSCustomObject]@{
                    id = $jobId
                    payload = $payload
                }) `
                -Payload $payload
        }

        $plan.commands[0].state | Should -Be 'Completed'
        $plan.commands[0].outputPath | Should -Be $encodedOutput
        $plan.commands[0].control.attempts | Should -Be 2
        $plan.commands[1].state | Should -Be 'Planned'
        $plan.commands[1].control.maxAttempts | Should -Be 3
        $plan.commands[1].control.retryable | Should -BeTrue
    }

    It 'plans scheduler lanes for controlled main video and parallel secondary media' {
        $plan = InModuleScope RenderKit {
            $payload = [PSCustomObject]@{
                archive = [PSCustomObject]@{
                    mode = 'TranscodeAndArchive'
                    compressionPreset = 'Balanced'
                }
                encoding = [PSCustomObject]@{
                    videoCodec = 'H265'
                    encoderDevice = 'CPU'
                    qualityPreset = 'Balanced'
                    audioProfile = 'AAC_128'
                    proxy = [PSCustomObject]@{ enabled = $false }
                    preview = [PSCustomObject]@{ enabled = $false }
                }
                execution = [PSCustomObject]@{
                    maxParallelJobs = 4
                    requireIdle = $true
                    allowOnBattery = $false
                    resourceLimits = [PSCustomObject]@{
                        maxCpuPercent = 75
                        maxGpuPercent = 80
                    }
                }
                mediaAnalysis = [PSCustomObject]@{
                    files = @(
                        [PSCustomObject]@{
                            relativePath = 'Media/main.mp4'
                            path = 'D:\Projects\ClientA\Media\main.mp4'
                            mediaType = 'Video'
                            metadata = [PSCustomObject]@{
                                durationSeconds = 600.0
                                videoStreams = @([PSCustomObject]@{ index = 0; codec = 'h264' })
                                audioStreams = @([PSCustomObject]@{ index = 1; codec = 'aac' })
                                hasVideo = $true
                                hasAudio = $true
                            }
                        }
                        [PSCustomObject]@{
                            relativePath = 'Media/broll-a.mp4'
                            path = 'D:\Projects\ClientA\Media\broll-a.mp4'
                            mediaType = 'Video'
                            metadata = [PSCustomObject]@{
                                durationSeconds = 30.0
                                videoStreams = @([PSCustomObject]@{ index = 0; codec = 'h264' })
                                audioStreams = @()
                                hasVideo = $true
                                hasAudio = $false
                            }
                        }
                    )
                }
                chunkPlan = [PSCustomObject]@{
                    assets = @(
                        [PSCustomObject]@{
                            id = 'asset-main'
                            relativePath = 'Media/main.mp4'
                            path = 'D:\Projects\ClientA\Media\main.mp4'
                            mediaType = 'Video'
                            durationSeconds = 600.0
                            sizeBytes = [int64]60000000000
                            chunkable = $true
                        }
                        [PSCustomObject]@{
                            id = 'asset-broll'
                            relativePath = 'Media/broll-a.mp4'
                            path = 'D:\Projects\ClientA\Media\broll-a.mp4'
                            mediaType = 'Video'
                            durationSeconds = 30.0
                            sizeBytes = [int64]60000000
                            chunkable = $true
                        }
                    )
                    chunks = @(
                        [PSCustomObject]@{
                            id = 'chunk-main-000000'
                            assetId = 'asset-main'
                            relativePath = 'Media/main.mp4'
                            index = 0
                            startSeconds = 0.0
                            durationSeconds = 60.0
                        }
                        [PSCustomObject]@{
                            id = 'chunk-main-000001'
                            assetId = 'asset-main'
                            relativePath = 'Media/main.mp4'
                            index = 1
                            startSeconds = 60.0
                            durationSeconds = 60.0
                        }
                        [PSCustomObject]@{
                            id = 'chunk-broll-000000'
                            assetId = 'asset-broll'
                            relativePath = 'Media/broll-a.mp4'
                            index = 0
                            startSeconds = 0.0
                            durationSeconds = 30.0
                        }
                    )
                }
            }
            $job = [PSCustomObject]@{
                id = 'job-scheduler-plan'
                payload = $payload
            }

            New-BackupEncodingPlan -Job $job -Payload $payload
        }
        $mainCommands = @($plan.commands | Where-Object { $_.assetId -eq 'asset-main' })
        $brollCommand = @($plan.commands | Where-Object { $_.assetId -eq 'asset-broll' })[0]

        $plan.scheduler.enabled | Should -BeTrue
        $plan.scheduler.primaryAssetId | Should -Be 'asset-main'
        $plan.scheduler.workerPool.maxWorkers | Should -Be 4
        $plan.scheduler.resourceLimits.maxCpuPercent | Should -Be 75
        $plan.scheduler.resourceLimits.requireIdle | Should -BeTrue
        $plan.scheduler.policy.primaryVideo | Should -Be 'OneChunkAtATime'
        $mainCommands[0].scheduler.lane | Should -Be 'PrimaryVideo'
        $mainCommands[0].scheduler.maxConcurrentPerAsset | Should -Be 1
        $mainCommands[0].scheduler.controlledMainVideo | Should -BeTrue
        $brollCommand.scheduler.lane | Should -Be 'SecondaryMedia'
        $brollCommand.scheduler.priority | Should -BeLessThan $mainCommands[0].scheduler.priority
        $plan.merges[0].scheduler.lane | Should -Be 'DiskMerge'
        $plan.scheduler.lanes.Checksum.resourceClass | Should -Be 'DiskRead'
    }

    It 'validates merged assets for container, streams, and sync drift' {
        $validation = InModuleScope RenderKit {
            $merge = [PSCustomObject]@{
                assetId = 'asset-main'
                outputPath = 'D:\Backups\asset-main.mkv'
                validation = [PSCustomObject]@{
                    expectedDurationSeconds = 90.0
                    durationToleranceSeconds = 1.0
                    expectedVideo = $true
                    expectedAudio = $true
                }
            }
            $metadata = [PSCustomObject]@{
                durationSeconds = 90.02
                format = 'matroska,webm'
                videoStreams = @(
                    [PSCustomObject]@{
                        index = 0
                        codec = 'hevc'
                    }
                )
                audioStreams = @(
                    [PSCustomObject]@{
                        index = 1
                        codec = 'aac'
                    }
                )
                hasVideo = $true
                hasAudio = $true
            }

            Test-BackupMergeProbeMetadata `
                -MergeCommand $merge `
                -Metadata $metadata
        }
        $failureMessage = InModuleScope RenderKit {
            $merge = [PSCustomObject]@{
                assetId = 'asset-main'
                outputPath = 'D:\Backups\asset-main.mkv'
                validation = [PSCustomObject]@{
                    expectedDurationSeconds = 90.0
                    durationToleranceSeconds = 1.0
                    expectedVideo = $true
                    expectedAudio = $true
                }
            }
            $metadata = [PSCustomObject]@{
                durationSeconds = 95.0
                format = 'matroska,webm'
                videoStreams = @(
                    [PSCustomObject]@{
                        index = 0
                        codec = 'hevc'
                    }
                )
                audioStreams = @(
                    [PSCustomObject]@{
                        index = 1
                        codec = 'aac'
                    }
                )
                hasVideo = $true
                hasAudio = $true
            }

            try {
                Test-BackupMergeProbeMetadata `
                    -MergeCommand $merge `
                    -Metadata $metadata |
                    Out-Null
                $null
            }
            catch {
                $_.Exception.Message
            }
        }

        $validation.succeeded | Should -BeTrue
        $validation.container.status | Should -Be 'Passed'
        $validation.sync.durationDriftSeconds | Should -Be 0.02
        $validation.streams.videoCount | Should -Be 1
        $validation.streams.audioCount | Should -Be 1
        $failureMessage | Should -Match 'duration drift'
    }

    It 'maps codec and GPU selections to concrete ffmpeg encoders' {
        $profiles = InModuleScope RenderKit {
            @(
                Get-BackupEncodingProfile `
                    -CompressionPreset Balanced `
                    -VideoCodec H264 `
                    -EncoderDevice Nvidia `
                    -QualityPreset Draft `
                    -AudioProfile AAC_128
                Get-BackupEncodingProfile `
                    -CompressionPreset Smallest `
                    -VideoCodec AV1 `
                    -EncoderDevice IntelQuickSync `
                    -QualityPreset Smallest `
                    -AudioProfile Opus_96
                Get-BackupEncodingProfile `
                    -CompressionPreset Balanced `
                    -VideoCodec H265 `
                    -EncoderDevice AMD `
                    -QualityPreset Balanced `
                    -AudioProfile AAC_192
            )
        }

        $profiles[0].encoderName | Should -Be 'h264_nvenc'
        $profiles[0].videoCodec | Should -Be 'H264'
        $profiles[1].encoderName | Should -Be 'av1_qsv'
        $profiles[1].videoCodec | Should -Be 'AV1'
        $profiles[1].audioArgs | Should -Contain 'libopus'
        $profiles[2].encoderName | Should -Be 'hevc_amf'
        $profiles[2].videoCodec | Should -Be 'H265'
        $profiles[2].audioArgs | Should -Contain '192k'
    }

    It 'detects hardware encoder capabilities from ffmpeg encoders and GPU hints' {
        $report = InModuleScope RenderKit {
            $encoderNames = ConvertFrom-BackupFfmpegEncoderList -Text @(
                ' V....D h264_nvenc           NVIDIA NVENC H.264 encoder'
                ' V....D hevc_nvenc           NVIDIA NVENC hevc encoder'
                ' V....D av1_nvenc            NVIDIA NVENC av1 encoder'
                ' V....D h264_qsv             H.264 Quick Sync Video encoder'
                ' V....D hevc_qsv             HEVC Quick Sync Video encoder'
                ' V....D av1_qsv              AV1 Quick Sync Video encoder'
                ' V....D h264_amf             AMD AMF H.264 encoder'
                ' V....D hevc_amf             AMD AMF HEVC encoder'
                ' V....D av1_amf              AMD AMF AV1 encoder'
            )
            New-BackupGpuCapabilityReport `
                -EncoderNames @($encoderNames) `
                -VideoControllerNames @(
                    'NVIDIA GeForce RTX 4080'
                    'Intel Arc Graphics'
                    'AMD Radeon RX 7900'
                ) `
                -DetectedCommands @('nvidia-smi') `
                -FfmpegPath 'ffmpeg' `
                -Source 'Test'
        }

        $report.ffmpeg.encoderNames | Should -Contain 'av1_nvenc'
        $report.summary.hardwareProviderCount | Should -Be 3
        $report.summary.av1HardwareEncoderAvailable | Should -BeTrue
        $nvidia = @($report.providers | Where-Object { $_.id -eq 'Nvidia' })[0]
        $intel = @($report.providers | Where-Object { $_.id -eq 'IntelQuickSync' })[0]
        $amd = @($report.providers | Where-Object { $_.id -eq 'AMD' })[0]
        $nvidia.codecCapabilities.AV1.usableForAuto | Should -BeTrue
        $intel.codecCapabilities.AV1.encoderName | Should -Be 'av1_qsv'
        $amd.codecCapabilities.AV1.usableForAuto | Should -BeTrue
        $report.recommendations.AV1.device | Should -Be 'Nvidia'
    }

    It 'uses GPU capabilities for automatic encoder selection' {
        $profile = InModuleScope RenderKit {
            $capabilities = New-BackupGpuCapabilityReport `
                -EncoderNames @('h264_nvenc', 'hevc_nvenc', 'av1_nvenc') `
                -VideoControllerNames @('NVIDIA GeForce RTX 4080') `
                -DetectedCommands @('nvidia-smi') `
                -FfmpegPath 'ffmpeg' `
                -Source 'Test'
            Get-BackupEncodingProfile `
                -CompressionPreset Smallest `
                -VideoCodec Auto `
                -EncoderDevice Auto `
                -QualityPreset Smallest `
                -AudioProfile Auto `
                -GpuCapabilities $capabilities
        }

        $profile.videoCodec | Should -Be 'AV1'
        $profile.encoderDevice | Should -Be 'Nvidia'
        $profile.encoderName | Should -Be 'av1_nvenc'
        $profile.encoderSelection.source | Should -Be 'GpuCapabilityAuto'
        $profile.audioProfile | Should -Be 'Opus_96'
    }

    It 'falls back to CPU when Auto has no usable hardware encoder for the codec' {
        $profile = InModuleScope RenderKit {
            $capabilities = New-BackupGpuCapabilityReport `
                -EncoderNames @('h264_qsv', 'hevc_qsv') `
                -VideoControllerNames @('Intel UHD Graphics') `
                -FfmpegPath 'ffmpeg' `
                -Source 'Test'
            Get-BackupEncodingProfile `
                -CompressionPreset Smallest `
                -VideoCodec AV1 `
                -EncoderDevice Auto `
                -QualityPreset Balanced `
                -AudioProfile Auto `
                -GpuCapabilities $capabilities
        }

        $profile.videoCodec | Should -Be 'AV1'
        $profile.encoderDevice | Should -Be 'CPU'
        $profile.encoderName | Should -Be 'libsvtav1'
        $profile.encoderSelection.source | Should -Be 'CpuFallback'
        $profile.encoderSelection.reason | Should -Be 'NoUsableHardwareEncoderDetected'
    }

    It 'persists and reads the GPU capability cache' {
        $cached = InModuleScope RenderKit -Parameters @{
            CachePath = (Join-Path $TestDrive 'gpu-cache\gpu-capabilities.json')
        } {
            $report = New-BackupGpuCapabilityReport `
                -EncoderNames @('h264_nvenc', 'hevc_nvenc', 'av1_nvenc') `
                -VideoControllerNames @('NVIDIA RTX Test Adapter') `
                -DetectedCommands @('nvidia-smi') `
                -FfmpegPath 'ffmpeg' `
                -CachePath $CachePath `
                -Source 'Test'
            Save-BackupGpuCapabilityCache -Report $report -Path $CachePath | Out-Null
            Read-BackupGpuCapabilityCache -Path $CachePath
        }

        $cached | Should -Not -BeNullOrEmpty
        $cached.cache.source | Should -Be 'Cache'
        $cached.recommendations.AV1.device | Should -Be 'Nvidia'
        $cached.providers[0].codecCapabilities.AV1.usableForAuto | Should -BeTrue
    }

    It 'parses ffmpeg progress lines into percentages' {
        $progress = InModuleScope RenderKit {
            ConvertFrom-BackupFfmpegProgressLine `
                -Line 'out_time_us=30000000' `
                -DurationSeconds 60
        }
        $terminal = InModuleScope RenderKit {
            ConvertFrom-BackupFfmpegProgressLine `
                -Line 'progress=end' `
                -DurationSeconds 60
        }

        $progress.seconds | Should -Be 30
        $progress.percent | Should -Be 50
        $terminal.isTerminal | Should -BeTrue
    }

    It 'builds structured progress snapshots with speed and ETA' {
        $snapshot = InModuleScope RenderKit {
            $state = @{}
            Update-BackupFfmpegProgressAccumulator `
                -State $state `
                -Line 'out_time_us=30000000' `
                -DurationSeconds 60 |
                Out-Null
            $ffmpegProgress = Update-BackupFfmpegProgressAccumulator `
                -State $state `
                -Line 'speed=2.0x' `
                -DurationSeconds 60
            $copyProgress = New-BackupCopyProgressSnapshot `
                -BytesCompleted 50MB `
                -BytesTotal 100MB `
                -StartedAtUtc ((Get-Date).ToUniversalTime().AddSeconds(-10))

            [PSCustomObject]@{
                ffmpeg = $ffmpegProgress
                copy = $copyProgress
                snapshot = New-BackupProgressSnapshot `
                    -JobId 'job-progress' `
                    -StageName 'Encoding' `
                    -StageDisplayName 'Encoding chunk' `
                    -Message 'Encoding chunk 1/2: Media/main.mp4' `
                    -Command ([PSCustomObject]@{
                        id = 'encode-chunk-main-000000'
                        type = 'EncodeChunk'
                        assetId = 'asset-main'
                        chunkId = 'chunk-main-000000'
                        relativePath = 'Media/main.mp4'
                        index = 0
                    }) `
                    -Current 0 `
                    -Total 2 `
                    -Percent 25 `
                    -FfmpegProgress $ffmpegProgress
            }
        }

        $snapshot.ffmpeg.percent | Should -Be 50
        $snapshot.ffmpeg.speedX | Should -Be 2.0
        $snapshot.ffmpeg.etaSeconds | Should -Be 15.0
        $snapshot.ffmpeg.speedText | Should -Be '2.00x'
        $snapshot.copy.percent | Should -Be 50
        $snapshot.copy.speedText | Should -Match 'MB/s'
        $snapshot.snapshot.stage.name | Should -Be 'Encoding'
        $snapshot.snapshot.current.chunkId | Should -Be 'chunk-main-000000'
        $snapshot.snapshot.overall.percent | Should -Be 25
        $snapshot.snapshot.overall.etaSeconds | Should -Be 15.0
    }

    It 'runs the BackupProject worker handler when no encoding is required' {
        $projectParent = Join-Path $TestDrive 'worker-projects'
        $projectRoot = Join-Path $projectParent 'WorkerProject'
        $metadataRoot = Join-Path $projectRoot '.renderkit'
        New-Item -ItemType Directory -Path $metadataRoot -Force | Out-Null
        Set-Content `
            -LiteralPath (Join-Path $projectRoot 'notes.txt') `
            -Value 'notes' `
            -Encoding UTF8
        [PSCustomObject]@{
            tool = 'RenderKit'
            schemaVersion = '1.0'
            project = [PSCustomObject]@{
                id = 'worker-project'
                name = 'WorkerProject'
                createdAt = (Get-Date).ToString('o')
            }
            lifecycle = [PSCustomObject]@{
                status = 'Draft'
            }
        } |
            ConvertTo-Json -Depth 8 |
            Set-Content `
                -LiteralPath (Join-Path $metadataRoot 'project.json') `
                -Encoding UTF8

        $queued = Backup-Project `
            -ProjectName WorkerProject `
            -Path $projectParent `
            -Background `
            -KeepSourceProject

        $completed = InModuleScope RenderKit -Parameters @{ JobId = $queued.JobId } {
            Invoke-RenderKitJob -JobId $JobId
        }
        $resumeState = Get-Content `
            -LiteralPath $queued.Payload.resume.statePath `
            -Raw |
            ConvertFrom-Json

        $completed.status | Should -Be 'Succeeded'
        $completed.result.phase | Should -Be 'Encoding'
        $completed.result.skipped | Should -BeTrue
        $completed.result.encodedChunkCount | Should -Be 0
        $resumeState.progress.currentPhase | Should -Be 'EncodingComplete'
        $resumeState.progress.statePath | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $resumeState.progress.statePath |
            Should -BeTrue
        $resumeState.progressSnapshot.stage.name | Should -Be 'EncodingSkipped'
        $resumeState.progressSnapshot.overall.percent | Should -Be 100
    }

    It 'creates a v2 backup manifest with pipeline metadata' {
        $manifest = InModuleScope RenderKit {
            New-BackupManifest `
                -Project ([PSCustomObject]@{
                    Id = 'project-1'
                    Name = 'ClientA'
                    RootPath = 'D:\Projects\ClientA'
                }) `
                -Options @{
                    profiles = @('General')
                    keepSourceProject = $true
                } `
                -Pipeline ([PSCustomObject]@{
                    archiveFormat = 'Zip'
                    encoding = [PSCustomObject]@{
                        videoCodec = 'Auto'
                        encoderDevice = 'Auto'
                        qualityPreset = 'Balanced'
                        audioProfile = 'Auto'
                        gpuDetection = New-BackupGpuDetectionPlan `
                            -VideoCodec Auto `
                            -EncoderDevice Auto `
                            -CompressionPreset Balanced
                    }
                    chunking = [PSCustomObject]@{
                        enabled = $true
                        durationSeconds = 600
                    }
                    merge = [PSCustomObject]@{
                        strategy = 'FfmpegConcatCopy'
                        validation = [PSCustomObject]@{
                            enabled = $true
                            syncPolicy = 'DurationDriftWithinTolerance'
                        }
                    }
                    scheduler = [PSCustomObject]@{
                        enabled = $true
                        mode = 'WorkerPool'
                        maxParallelJobs = 4
                    }
                    progress = [PSCustomObject]@{
                        statePath = 'K:\State\progress.json'
                        metrics = @('StageName', 'EtaSeconds', 'Speed')
                    }
                    control = [PSCustomObject]@{
                        statePath = 'K:\State\control.json'
                        pause = [PSCustomObject]@{
                            enabled = $true
                            mode = 'ProcessSuspendWhenSupported'
                        }
                        resume = [PSCustomObject]@{
                            enabled = $true
                            mode = 'SkipCompletedChunksFromChunkIndex'
                        }
                        cancel = [PSCustomObject]@{
                            enabled = $true
                            mode = 'OrderedStopActiveProcesses'
                        }
                        retry = [PSCustomObject]@{
                            maxAttemptsPerChunk = 3
                        }
                    }
                    background = [PSCustomObject]@{
                        enabled = $true
                        queueName = 'backup'
                        worker = [PSCustomObject]@{
                            mode = 'LocalWorker'
                            startCommand = 'Start-RenderKitJobWorker'
                            statusCommand = 'Get-RenderKitJobStatus'
                            workerStatusCommand = 'Get-RenderKitJobWorkerStatus'
                        }
                        recovery = [PSCustomObject]@{
                            leaseHeartbeat = 'ProgressExtendsLease'
                            staleRunningJobMode = 'RequeueAfterExpiredLease'
                            crashedWorkerState = 'DetectPreviousWorkerPid'
                        }
                        logs = [PSCustomObject]@{
                            persistent = $true
                            format = 'jsonl'
                        }
                    }
                    storageCascade = [PSCustomObject]@{
                        schemaVersion = '1.0'
                        enabled = $true
                        mode = 'Cascading'
                        strategy = 'FastestWritableFirstThenCascade'
                        primaryTierId = 'tier-1'
                        stages = @(
                            [PSCustomObject]@{
                                tierId = 'tier-1'
                                action = 'WritePrimary'
                            }
                            [PSCustomObject]@{
                                tierId = 'tier-2'
                                action = 'CascadeCopy'
                            }
                        )
                    }
                    copyVerify = [PSCustomObject]@{
                        schemaVersion = '1.0'
                        enabled = $true
                        algorithm = 'SHA256'
                        verify = [PSCustomObject]@{
                            afterEveryTier = $true
                            releaseRequires = 'ArchiveIntegrityAndRequiredStorageTiersVerified'
                            requiredTierIds = @('tier-1')
                        }
                        retry = [PSCustomObject]@{
                            maxAttempts = 3
                        }
                    }
                    deduplication = New-BackupDeduplicationPolicy
                    reports = New-BackupReportPlan `
                        -ArchivePath 'E:\Backups\ClientA.zip' `
                        -ReportRoot 'E:\Backups' `
                        -Format @('Json', 'Html', 'Text')
                    safeDelete = New-BackupSafeDeletePolicy `
                        -Mode KeepSource `
                        -RequiredStorageTierIds @('tier-1')
                }) `
                -StorageTiers @(
                    [PSCustomObject]@{
                        name = 'Primary'
                        path = 'E:\Backups'
                    }
                )
        }

        $manifest.schemaVersion | Should -Be '2.0'
        $manifest.profile.configProfile | Should -Be 'legacy'
        $manifest.pipeline.archiveFormat | Should -Be 'Zip'
        $manifest.pipeline.encoding.gpuDetection.mode | Should -Be 'AutoSelectBestAvailable'
        $manifest.pipeline.encoding.gpuDetection.cache.enabled | Should -BeTrue
        $manifest.pipeline.chunking.enabled | Should -BeTrue
        $manifest.pipeline.merge.validation.enabled | Should -BeTrue
        $manifest.pipeline.scheduler.maxParallelJobs | Should -Be 4
        $manifest.pipeline.progress.metrics | Should -Contain 'EtaSeconds'
        $manifest.pipeline.control.resume.mode | Should -Be 'SkipCompletedChunksFromChunkIndex'
        $manifest.pipeline.control.retry.maxAttemptsPerChunk | Should -Be 3
        $manifest.pipeline.background.worker.startCommand | Should -Be 'Start-RenderKitJobWorker'
        $manifest.pipeline.background.recovery.crashedWorkerState | Should -Be 'DetectPreviousWorkerPid'
        $manifest.pipeline.background.logs.persistent | Should -BeTrue
        $manifest.pipeline.storageCascade.mode | Should -Be 'Cascading'
        $manifest.pipeline.storageCascade.stages[1].action | Should -Be 'CascadeCopy'
        $manifest.pipeline.copyVerify.verify.afterEveryTier | Should -BeTrue
        $manifest.pipeline.copyVerify.retry.maxAttempts | Should -Be 3
        $manifest.pipeline.deduplication.enabled | Should -BeTrue
        $manifest.pipeline.deduplication.mode | Should -Be 'ContentHashCanonicalManifest'
        $manifest.pipeline.reports.enabled | Should -BeTrue
        $manifest.pipeline.reports.formats | Should -Contain 'Html'
        $manifest.pipeline.safeDelete.mode | Should -Be 'KeepSource'
        $manifest.pipeline.safeDelete.rules.requiresDecodeValidation | Should -BeTrue
        $manifest.storageTiers[0].name | Should -Be 'Primary'
        $manifest.safety.deletePolicy.mode | Should -Be 'KeepSource'
        $manifest.safety.safeDelete.mode | Should -Be 'KeepSource'
        $manifest.safety.safeDelete.rules.requiresArchiveIntegrity | Should -BeTrue
    }
}
