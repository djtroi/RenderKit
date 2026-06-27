Describe 'RenderKit backup config profile creator' {
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

    It 'creates, persists, lists, and validates a user profile' {
        $created = New-BackupConfigProfile `
            -Name 'Client Compact' `
            -DisplayName 'Client Compact Delivery' `
            -Description 'Compact client archive' `
            -BaseProfile smallest `
            -Settings @{
                MaxCpuPercent = 70
                EncoderDevice = 'CPU'
            } `
            -Tag @('client', 'compact') `
            -Author 'RenderKit Test'

        $created.Name | Should -Be 'client-compact'
        $created.Source | Should -Be 'User'
        $created.BaseProfile | Should -Be 'smallest'
        $created.SchemaVersion | Should -Be '1.1'
        $created.Settings.VideoCodec | Should -Be 'AV1'
        $created.Settings.MaxCpuPercent | Should -Be 70
        $created.Settings.EncoderDevice | Should -Be 'CPU'
        Test-Path -LiteralPath $created.Path | Should -BeTrue
        $policy = InModuleScope RenderKit {
            Get-RenderKitArtifactVersionPolicy -ArtifactType BackupConfigProfile
        }
        $policy.Current | Should -Be '1.1'
        $policy.MinimumReadable | Should -Be '1.0'

        $listed = @(Get-BackupConfigProfile -Source User)
        $listed.Count | Should -Be 1
        $listed[0].Name | Should -Be 'client-compact'

        $validation = Test-BackupConfigProfile `
            -Name client-compact `
            -CheckAdapters
        $validation.IsValid | Should -BeTrue
        $validation.Errors.Count | Should -Be 0
        $validation.Compatibility | Should -Be 'Current'
    }

    It 'edits and versions a user profile' {
        New-BackupConfigProfile `
            -Name editable `
            -BaseProfile balanced |
            Out-Null

        $updated = Set-BackupConfigProfile `
            -Name editable `
            -Settings @{
                VideoCodec = 'H265'
                MaxParallelJobs = 5
            } `
            -Description 'Updated profile' `
            -BumpVersion Minor

        $updated.ProfileVersion | Should -Be '1.1.0'
        $updated.Description | Should -Be 'Updated profile'
        $updated.Settings.VideoCodec | Should -Be 'H265'
        $updated.Settings.MaxParallelJobs | Should -Be 5

        $stored = Get-Content -LiteralPath $updated.Path -Raw | ConvertFrom-Json
        $stored.PSObject.Properties.Name | Should -Not -Contain 'path'
        $stored.PSObject.Properties.Name | Should -Not -Contain 'requiresBackground'
        $stored.revision.generation | Should -Be 2
    }

    It 'uses a user profile directly in Backup-Project' {
        New-BackupConfigProfile `
            -Name studio-fast `
            -BaseProfile fastest `
            -Settings @{
                EncoderDevice = 'CPU'
                MaxCpuPercent = 61
                MaxParallelJobs = 3
            } |
            Out-Null

        $projectParent = Join-Path $TestDrive 'projects'
        $projectRoot = Join-Path $projectParent 'ProfileProject'
        $metadataRoot = Join-Path $projectRoot '.renderkit'
        New-Item -ItemType Directory -Path $metadataRoot -Force | Out-Null
        [PSCustomObject]@{
            tool = 'RenderKit'
            schemaVersion = '1.0'
            project = [PSCustomObject]@{
                id = 'profile-project'
                name = 'ProfileProject'
                createdAt = (Get-Date).ToString('o')
            }
            lifecycle = [PSCustomObject]@{ status = 'Draft' }
        } |
            ConvertTo-Json -Depth 8 |
            Set-Content `
                -LiteralPath (Join-Path $metadataRoot 'project.json') `
                -Encoding UTF8

        $queued = Backup-Project `
            -ProjectName ProfileProject `
            -Path $projectParent `
            -ConfigProfile studio-fast `
            -Background `
            -KeepSourceProject

        $queued.Payload.profile.configProfile | Should -Be 'studio-fast'
        $queued.Payload.profile.configProfileResolution.source | Should -Be 'User'
        $queued.Payload.archive.mode | Should -Be 'TranscodeAndArchive'
        $queued.Payload.encoding.videoCodec | Should -Be 'H264'
        $queued.Payload.encoding.encoderDevice | Should -Be 'CPU'
        $queued.Payload.scheduler.maxParallelJobs | Should -Be 3
        $queued.Payload.scheduler.resourceLimits.maxCpuPercent | Should -Be 61
    }

    It 'exports, removes, and imports a portable profile' {
        New-BackupConfigProfile `
            -Name portable `
            -BaseProfile archive-safe `
            -Settings @{ MaxDiskActivePercent = 65 } |
            Out-Null
        $exportRoot = Join-Path $TestDrive 'exports'
        New-Item -ItemType Directory -Path $exportRoot -Force | Out-Null

        $export = Export-BackupConfigProfile `
            -Name portable `
            -Path $exportRoot
        $export.Path | Should -Match '\.rkprofile\.json$'
        $export.SHA256 | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $export.Path | Should -BeTrue

        $removed = Remove-BackupConfigProfile `
            -Name portable `
            -Confirm:$false
        $removed.Removed | Should -BeTrue
        { Get-BackupConfigProfile portable } | Should -Throw

        $imported = Import-BackupConfigProfile -Path $export.Path
        $imported.Name | Should -Be 'portable'
        $imported.SchemaVersion | Should -Be '1.1'
        $imported.Profile.Settings.MaxDiskActivePercent | Should -Be 65
        (Test-BackupConfigProfile portable).IsValid | Should -BeTrue
    }

    It 'renames imported profiles on conflict' {
        New-BackupConfigProfile -Name duplicate -BaseProfile balanced | Out-Null
        $export = Export-BackupConfigProfile `
            -Name duplicate `
            -Path (Join-Path $TestDrive 'duplicate-export')

        $imported = Import-BackupConfigProfile `
            -Path $export.Path `
            -ConflictAction Rename

        $imported.Name | Should -Be 'duplicate-2'
        @(Get-BackupConfigProfile -Source User).Name |
            Should -Contain 'duplicate-2'
    }

    It 'upgrades a legacy schema and fills settings introduced by the module' {
        $profileRoot = InModuleScope RenderKit {
            Get-RenderKitBackupConfigProfilesRoot
        }
        $legacyPath = Join-Path $profileRoot 'legacy-profile.rkprofile.json'
        [PSCustomObject]@{
            schemaVersion = '1.0'
            name = 'legacy-profile'
            displayName = 'Legacy Profile'
            description = 'Legacy import'
            profileVersion = '1.0.0'
            baseProfile = 'balanced'
            settings = [PSCustomObject]@{
                MaxCpuPercent = 55
            }
        } |
            ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath $legacyPath -Encoding UTF8

        $before = Test-BackupConfigProfile -Path $legacyPath
        $before.IsValid | Should -BeTrue
        $before.SchemaVersion | Should -Be '1.1'
        $before.EffectiveSettings.MaxCpuPercent | Should -Be 55
        $before.EffectiveSettings.EncoderAdapter | Should -Be 'FFmpeg'

        $upgrade = Update-BackupConfigProfile -Name legacy-profile
        $upgrade.PreviousSchemaVersion | Should -Be '1.0'
        $upgrade.SchemaVersion | Should -Be '1.1'
        $upgrade.ModuleVersion | Should -Be '1.0.0'

        $stored = Get-Content -LiteralPath $legacyPath -Raw | ConvertFrom-Json
        $stored.kind | Should -Be 'RenderKit.BackupConfigProfile'
        $stored.schemaVersion | Should -Be '1.1'
        $stored.settings.VerifierAdapter | Should -Be 'SHA256'
        $stored.compatibility.previousSchemaVersion | Should -Be '1.0'
    }

    It 'supports interactive creation while preserving blank defaults' {
        Mock -ModuleName RenderKit -CommandName Read-Host -MockWith { '' }

        $created = New-BackupConfigProfile `
            -Name interactive-profile `
            -BaseProfile no-transcode `
            -Interactive

        $created.Name | Should -Be 'interactive-profile'
        $created.Settings.CompressionMode | Should -Be 'ArchiveOnly'
        $created.Settings.VideoCodec | Should -Be 'Auto'
        Should -Invoke -ModuleName RenderKit -CommandName Read-Host -Times 21
    }

    It 'reports invalid profile combinations without persisting them' {
        $invalid = InModuleScope RenderKit {
            $document = New-BackupUserConfigProfileDocument `
                -Name invalid-proxy `
                -BaseProfile proxy-only
            $document.settings.VideoCodec = 'AV1'
            $document
        }

        $result = $invalid | Test-BackupConfigProfile
        $result.IsValid | Should -BeFalse
        $result.Errors -join ';' | Should -Match 'ProxyOnly'
    }

    It 'validates an unsaved Studio draft against its base profile' {
        $result = Test-BackupConfigProfile `
            -BaseProfile proxy-only `
            -DraftName studio-preview `
            -Settings @{
                VideoCodec = 'AV1'
                MaxCpuPercent = 64
            }

        $result.Name | Should -Be 'studio-preview'
        $result.Source | Should -Be 'Draft'
        $result.IsValid | Should -BeFalse
        $result.Errors -join ';' | Should -Match 'ProxyOnly'
        $result.EffectiveSettings.MaxCpuPercent | Should -Be 64
        @(Get-BackupConfigProfile -Source User).Count | Should -Be 0
    }

    It 'rebases an existing user profile while applying explicit settings' {
        New-BackupConfigProfile `
            -Name rebase-me `
            -BaseProfile fastest |
            Out-Null

        $updated = Set-BackupConfigProfile `
            -Name rebase-me `
            -BaseProfile archive-safe `
            -Settings @{ MaxCpuPercent = 63 }

        $updated.BaseProfile | Should -Be 'archive-safe'
        $updated.Settings.ArchiveFormat | Should -Be 'TarZstd'
        $updated.Settings.CompressionMode | Should -Be 'ArchiveOnly'
        $updated.Settings.MaxCpuPercent | Should -Be 63
    }

    It 'rejects stale profile updates using the expected generation' {
        $created = New-BackupConfigProfile `
            -Name concurrent-profile `
            -BaseProfile balanced
        $loadedGeneration = [int]$created.Revision.generation

        Set-BackupConfigProfile `
            -Name concurrent-profile `
            -Settings @{ MaxCpuPercent = 70 } `
            -ExpectedGeneration $loadedGeneration |
            Out-Null

        {
            Set-BackupConfigProfile `
                -Name concurrent-profile `
                -Settings @{ MaxCpuPercent = 55 } `
                -ExpectedGeneration $loadedGeneration
        } | Should -Throw -ErrorId 'RK_PROFILE_CONFLICT*'

        $stored = Get-BackupConfigProfile concurrent-profile
        $stored.Settings.MaxCpuPercent | Should -Be 70
        $stored.Revision.generation | Should -Be ($loadedGeneration + 1)
    }
}
