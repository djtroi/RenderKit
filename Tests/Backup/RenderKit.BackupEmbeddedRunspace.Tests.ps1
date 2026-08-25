Describe 'RS-1508 embedded backup worker process handling' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (
            Split-Path -Parent $PSScriptRoot)
        $implementationPath = Join-Path `
            $repositoryRoot `
            'src/Private/Backup/RenderKit.BackupProcessExecution.ps1'
        $implementationSource = Get-Content `
            -LiteralPath $implementationPath `
            -Raw

        Import-Module `
            (Join-Path $repositoryRoot 'RenderKit.psd1') `
            -Force
    }

    AfterAll {
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
    }

    It 'documents the ticket context on the hosted-runspace fix' {
        $implementationSource | Should -Match 'RS-1508'
        $implementationSource | Should -Match 'DefaultRunspace'
    }

    It 'uses the hosted-runspace-safe backup worker implementation' {
        InModuleScope RenderKit {
            $definition = (Get-Command Start-BackupScheduledThreadJob).Definition

            $definition | Should -Not -Match 'add_ErrorDataReceived'
            $definition | Should -Not -Match 'BeginErrorReadLine'
            $definition | Should -Not -Match 'ReadToEndAsync'
            $definition | Should -Match 'StandardError\.ReadLineAsync'
            $definition | Should -Match 'StandardOutput\.ReadLineAsync'
            $definition | Should -Match 'Task\]::WhenAny'
            $definition | Should -Match '\$process\.Dispose\(\)'
        }
    }
}
