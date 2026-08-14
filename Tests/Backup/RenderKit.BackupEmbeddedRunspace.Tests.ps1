Describe 'RenderKit backup hosted-runspace compatibility' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (
            Split-Path -Parent $PSScriptRoot)
        $module = Import-Module `
            (Join-Path $repositoryRoot 'RenderKit.psd1') `
            -PassThru `
            -Force
        $compatibilityPath = Join-Path `
            $repositoryRoot `
            'src/Private/Backup/RenderKit.BackupThreadJobHostCompatibility.ps1'
        $compatibilitySource = Get-Content `
            -LiteralPath $compatibilityPath `
            -Raw
    }

    AfterAll {
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
    }

    It 'loads the hosted-runspace-safe thread-job implementation last' {
        InModuleScope RenderKit {
            $command = Get-Command `
                -Name Start-BackupScheduledThreadJob `
                -CommandType Function
            Split-Path -Leaf $command.ScriptBlock.File |
                Should -Be 'RenderKit.BackupThreadJobHostCompatibility.ps1'
        }
    }

    It 'does not attach PowerShell scriptblocks to async process stderr events' {
        $compatibilitySource | Should -Not -Match 'add_ErrorDataReceived'
        $compatibilitySource | Should -Not -Match 'BeginErrorReadLine'
        $compatibilitySource | Should -Match 'StandardError\.ReadToEndAsync\(\)'
    }

    It 'preserves stdout progress streaming while stderr is drained concurrently' {
        $compatibilitySource | Should -Match 'StandardOutput\.ReadLine\(\)'
        $compatibilitySource | Should -Match 'WaitForExit\(\)'
        $compatibilitySource | Should -Match 'GetAwaiter\(\)\.GetResult\(\)'
    }
}
