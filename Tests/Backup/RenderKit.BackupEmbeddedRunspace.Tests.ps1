Describe 'RS-1508 embedded backup worker process handling' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (
            Split-Path -Parent $PSScriptRoot)
        Import-Module `
            (Join-Path $repositoryRoot 'RenderKit.psd1') `
            -Force
    }

    AfterAll {
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
    }

    It 'uses the hosted-runspace-safe backup worker implementation' {
        InModuleScope RenderKit {
            $definition = (Get-Command Start-BackupScheduledThreadJob).Definition

            $definition | Should -Match 'RS-1508'
            $definition | Should -Not -Match 'add_ErrorDataReceived'
            $definition | Should -Not -Match 'BeginErrorReadLine'
            $definition | Should -Match 'StandardError\.ReadToEndAsync'
            $definition | Should -Match 'StandardOutput\.ReadLine'
            $definition | Should -Match '\$process\.Dispose\(\)'
        }
    }
}
