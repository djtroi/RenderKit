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
            }

        $result.JobType | Should -Be 'BackupProject'
        $result.Status | Should -Be 'Queued'
        $result.Payload.profile.configProfile | Should -Be 'smallest'
        $result.Payload.archive.format | Should -Be 'SevenZip'
        $result.Payload.encoding.videoCodec | Should -Be 'AV1'
        $result.Payload.encoding.encoderDevice | Should -Be 'CPU'
        $result.Payload.encoding.audioProfile | Should -Be 'Opus_96'
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

        $pause = Suspend-BackupProjectJob `
            -JobId $queued.JobId `
            -Reason 'test pause'
        $pause.state | Should -Be 'PauseRequested'
        $pause.reason | Should -Be 'test pause'

        $resume = Resume-BackupProjectJob `
            -JobId $queued.JobId `
            -Reason 'test resume'
        $resume.state | Should -Be 'ResumeRequested'
        $resume.reason | Should -Be 'test resume'

        $cancel = Stop-BackupProjectJob `
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
        $manifest.pipeline.chunking.enabled | Should -BeTrue
        $manifest.pipeline.merge.validation.enabled | Should -BeTrue
        $manifest.pipeline.scheduler.maxParallelJobs | Should -Be 4
        $manifest.pipeline.progress.metrics | Should -Contain 'EtaSeconds'
        $manifest.pipeline.control.resume.mode | Should -Be 'SkipCompletedChunksFromChunkIndex'
        $manifest.pipeline.control.retry.maxAttemptsPerChunk | Should -Be 3
        $manifest.pipeline.background.worker.startCommand | Should -Be 'Start-RenderKitJobWorker'
        $manifest.pipeline.background.recovery.crashedWorkerState | Should -Be 'DetectPreviousWorkerPid'
        $manifest.pipeline.background.logs.persistent | Should -BeTrue
        $manifest.storageTiers[0].name | Should -Be 'Primary'
        $manifest.safety.deletePolicy.mode | Should -Be 'KeepSource'
    }
}
