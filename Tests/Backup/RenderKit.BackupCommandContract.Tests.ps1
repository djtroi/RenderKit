Describe 'RenderKit backup command contracts' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (
            Split-Path -Parent $PSScriptRoot)
        $module = Import-Module `
            (Join-Path $repositoryRoot 'RenderKit.psd1') `
            -PassThru `
            -Force

        $backupProjectPath = Join-Path `
            $repositoryRoot `
            'src/Public/Backup-Project.ps1'
        $tokens = $null
        $parseErrors = $null
        $backupProjectAst = [System.Management.Automation.Language.Parser]::ParseFile(
            $backupProjectPath,
            [ref]$tokens,
            [ref]$parseErrors)

        if ($parseErrors.Count -gt 0) {
            throw (
                'Backup-Project.ps1 contains parser errors: ' +
                (($parseErrors.Message | Sort-Object -Unique) -join '; '))
        }
    }

    AfterAll {
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
    }

    It 'exposes Preset as the cleanup selection parameter' {
        $command = Get-Command -Module RenderKit -Name Backup-Project

        $command.Parameters.Keys | Should -Contain 'Preset'
        $command.Parameters['Preset'].Aliases | Should -Contain 'Software'
        $command.Parameters.Keys | Should -Not -Contain 'Profile'
    }

    It 'exposes the upgraded backup job planning parameters' {
        $command = Get-Command -Module RenderKit -Name Backup-Project

        $command.Parameters.Keys | Should -Contain 'Background'
        $command.Parameters['Background'].Aliases | Should -Contain 'AsJob'
        $command.Parameters.Keys | Should -Contain 'StartWorker'
        $command.Parameters.Keys | Should -Contain 'Watch'
        $command.Parameters.Keys | Should -Contain 'PollIntervalSeconds'
        $command.Parameters.Keys | Should -Contain 'NoProgressBar'
        $command.Parameters.Keys | Should -Contain 'ConfigProfile'
        $command.Parameters.Keys | Should -Contain 'ArchiveFormat'
        $command.Parameters.Keys | Should -Contain 'CompressionMode'
        $command.Parameters.Keys | Should -Contain 'CompressionPreset'
        $command.Parameters.Keys | Should -Contain 'VideoCodec'
        $command.Parameters.Keys | Should -Contain 'EncoderDevice'
        $command.Parameters.Keys | Should -Contain 'QualityPreset'
        $command.Parameters.Keys | Should -Contain 'AudioProfile'
        $command.Parameters.Keys | Should -Contain 'CreateProxy'
        $command.Parameters.Keys | Should -Contain 'CreatePreview'
        $command.Parameters.Keys | Should -Contain 'ChunkDurationSeconds'
        $command.Parameters.Keys | Should -Contain 'StorageTier'
        $command.Parameters.Keys | Should -Contain 'StorageTierProfile'
        $command.Parameters.Keys | Should -Contain 'StorageTierPath'
        $command.Parameters.Keys | Should -Contain 'ConfigureStorageTiers'
        $command.Parameters.Keys | Should -Contain 'MaxParallelJobs'
        $command.Parameters.Keys | Should -Contain 'MaxCpuPercent'
        $command.Parameters.Keys | Should -Contain 'MaxGpuPercent'
        $command.Parameters.Keys | Should -Contain 'RequireIdle'
        $command.Parameters.Keys | Should -Contain 'ReportFormat'
        $command.Parameters.Keys | Should -Contain 'ReportRoot'
        $command.Parameters.Keys | Should -Contain 'SimulateFailure'
        $command.Parameters.Keys | Should -Contain 'MaxChunkRetryAttempts'
        $command.Parameters.Keys | Should -Contain 'ChunkRetryDelaySeconds'
        $command.Parameters.Keys | Should -Contain 'SimulatedFailureCount'
    }

    It 'exposes backup job control commands' {
        Get-Command -Module RenderKit -Name Get-BackupJob |
            Should -Not -BeNullOrEmpty
        Get-Command -Module RenderKit -Name Pause-BackupJob |
            Should -Not -BeNullOrEmpty
        Get-Command -Module RenderKit -Name Resume-BackupJob |
            Should -Not -BeNullOrEmpty
        Get-Command -Module RenderKit -Name Stop-BackupJob |
            Should -Not -BeNullOrEmpty
        Get-Command -Module RenderKit -Name Suspend-BackupProjectJob |
            Should -Not -BeNullOrEmpty
        Get-Command -Module RenderKit -Name Resume-BackupProjectJob |
            Should -Not -BeNullOrEmpty
        Get-Command -Module RenderKit -Name Stop-BackupProjectJob |
            Should -Not -BeNullOrEmpty
        Get-Command -Module RenderKit -Name Start-RenderKitJobWorker |
            Should -Not -BeNullOrEmpty
        Get-Command -Module RenderKit -Name Get-RenderKitJobStatus |
            Should -Not -BeNullOrEmpty
        Get-Command -Module RenderKit -Name Get-RenderKitJobWorkerStatus |
            Should -Not -BeNullOrEmpty

        (Get-Command -Module RenderKit -Name Get-BackupJob).Parameters.Keys |
            Should -Contain 'Watch'
        (Get-Command -Module RenderKit -Name Pause-BackupJob).Parameters.Keys |
            Should -Contain 'JobId'
        (Get-Command -Module RenderKit -Name Resume-BackupJob).Parameters.Keys |
            Should -Contain 'Reason'
        (Get-Command -Module RenderKit -Name Stop-BackupJob).Parameters.Keys |
            Should -Contain 'JobId'
        (Get-Command -Module RenderKit -Name Suspend-BackupProjectJob).Parameters.Keys |
            Should -Contain 'JobId'
        (Get-Command -Module RenderKit -Name Resume-BackupProjectJob).Parameters.Keys |
            Should -Contain 'Reason'
        (Get-Command -Module RenderKit -Name Stop-BackupProjectJob).Parameters.Keys |
            Should -Contain 'JobId'
        (Get-Command -Module RenderKit -Name Start-RenderKitJobWorker).Parameters.Keys |
            Should -Contain 'Detached'
        (Get-Command -Module RenderKit -Name Get-RenderKitJobStatus).Parameters.Keys |
            Should -Contain 'IncludeLogs'
        (Get-Command -Module RenderKit -Name Get-RenderKitJobWorkerStatus).Parameters.Keys |
            Should -Contain 'WorkerId'
    }

    It 'uses only parameters supported by Get-CleanupRule' {
        $cleanupCommandParameters = @(
            $module.Invoke({
                (Get-Command `
                    -Name Get-CleanupRule `
                    -CommandType Function `
                    -ErrorAction Stop).Parameters.Keys
            })
        )
        $cleanupInvocations = @(
            $backupProjectAst.FindAll(
                {
                    param($ast)

                    $ast -is [System.Management.Automation.Language.CommandAst] -and
                    $ast.GetCommandName() -eq 'Get-CleanupRule'
                },
                $true)
        )

        $cleanupInvocations.Count | Should -Be 1

        $usedParameters = @(
            $cleanupInvocations[0].CommandElements |
                Where-Object {
                    $_ -is [System.Management.Automation.Language.CommandParameterAst]
                } |
                ForEach-Object ParameterName
        )

        foreach ($parameter in $usedParameters) {
            $cleanupCommandParameters | Should -Contain $parameter
        }
        $usedParameters | Should -Contain 'Preset'
    }
}
