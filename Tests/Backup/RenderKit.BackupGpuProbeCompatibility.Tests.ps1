Describe 'RS-1508 FFmpeg hardware probe compatibility' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (
            Split-Path -Parent $PSScriptRoot)
        $implementationPath = Join-Path `
            $repositoryRoot `
            'src/Private/Backup/RenderKit.BackupGpuProbeCompatibility.ps1'
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

    It 'documents the compatibility fix under RS-1508' {
        $implementationSource | Should -Match 'RS-1508'
        $implementationSource | Should -Match 'Windows PowerShell 5\.1'
    }

    It 'falls back when ProcessStartInfo.ArgumentList is unavailable' {
        InModuleScope RenderKit {
            $definition = (Get-Command Test-BackupFfmpegEncoderCapability).Definition

            $definition | Should -Match "PSObject\.Properties\.Name -contains 'ArgumentList'"
            $definition | Should -Match 'ConvertTo-BackupProbeArgumentText'
        }
    }

    It 'falls back when process-tree termination is unavailable' {
        InModuleScope RenderKit {
            $definition = (Get-Command Test-BackupFfmpegEncoderCapability).Definition

            $definition | Should -Match 'OverloadDefinitions'
            $definition | Should -Match '\$process\.Kill\(\$true\)'
            $definition | Should -Match '\$process\.Kill\(\)'
        }
    }

    It 'continues draining both redirected streams asynchronously' {
        InModuleScope RenderKit {
            $definition = (Get-Command Test-BackupFfmpegEncoderCapability).Definition

            $definition | Should -Match 'StandardOutput\.ReadToEndAsync\(\)'
            $definition | Should -Match 'StandardError\.ReadToEndAsync\(\)'
            $definition | Should -Match '\$process\.Dispose\(\)'
        }
    }
}
