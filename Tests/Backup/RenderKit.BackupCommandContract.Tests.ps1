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
        $command.Parameters.Keys | Should -Contain 'MaxParallelJobs'
        $command.Parameters.Keys | Should -Contain 'MaxCpuPercent'
        $command.Parameters.Keys | Should -Contain 'MaxGpuPercent'
        $command.Parameters.Keys | Should -Contain 'RequireIdle'
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
