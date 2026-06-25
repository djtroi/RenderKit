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

        InModuleScope RenderKit {
            $jobs = @((Read-RenderKitJobStore).jobs)
            $jobs.Count | Should -Be 1
            $jobs[0].jobType | Should -Be 'BackupProject'
            $jobs[0].payload.archive.format | Should -Be 'SevenZip'
        }
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
