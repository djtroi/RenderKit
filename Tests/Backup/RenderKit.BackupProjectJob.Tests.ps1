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
        $result.Payload.chunking.enabled | Should -BeTrue
        $result.Payload.chunking.durationSeconds | Should -Be 120
        $result.Payload.execution.requireIdle | Should -BeTrue
        $result.Payload.storageTiers[0].name | Should -Be 'Fast SSD'
        $result.Payload.mediaAnalysis.summary.mediaFileCount | Should -Be 1
        $result.Payload.resume.jobId | Should -Be $result.JobId
        Test-Path -LiteralPath $result.Payload.resume.statePath |
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
