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
        $result.Payload.chunking.durationSeconds | Should -Be 120
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
                chunkPlan = [PSCustomObject]@{
                    assets = @(
                        [PSCustomObject]@{
                            id = 'asset-main'
                            path = 'D:\Projects\ClientA\Media\main.mp4'
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
        $plan.summary.proxyCommandCount | Should -Be 1
        $plan.summary.previewCommandCount | Should -Be 1
        $plan.commands[0].arguments | Should -Contain '-progress'
        $plan.commands[0].arguments | Should -Contain 'pipe:1'
        $plan.commands[0].arguments | Should -Contain 'libx265'
        $plan.commands[0].arguments | Should -Contain '192k'
        $plan.commands[0].outputPath | Should -Match 'encoded'
        $plan.merges[0].arguments | Should -Contain 'concat'
        $plan.proxyCommands[0].arguments | Should -Contain 'libx264'
        $plan.previewCommands[0].arguments | Should -Contain 'fps=1/30,scale=960:-2'
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
        $manifest.storageTiers[0].name | Should -Be 'Primary'
        $manifest.safety.deletePolicy.mode | Should -Be 'KeepSource'
    }
}
