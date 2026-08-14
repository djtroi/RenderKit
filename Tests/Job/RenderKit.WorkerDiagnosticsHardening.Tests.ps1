Describe 'RenderKit worker diagnostic hardening' {
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

    It 'does not fail worker control flow when the log target is unwritable' {
        $directoryTarget = Join-Path $TestDrive 'worker-log-directory'
        New-Item -ItemType Directory -Path $directoryTarget -Force | Out-Null

        $result = InModuleScope RenderKit -Parameters @{
            LogPath = $directoryTarget
        } {
            Write-RenderKitWorkerLogEntry `
                -WorkerId 'diagnostic-worker' `
                -Message 'diagnostic message' `
                -LogPath $LogPath `
                -WarningAction SilentlyContinue
        }

        $result | Should -BeNullOrEmpty
    }

    It 'remains best-effort when the caller treats warnings as terminating' {
        $directoryTarget = Join-Path $TestDrive 'strict-warning-log-directory'
        New-Item -ItemType Directory -Path $directoryTarget -Force | Out-Null

        InModuleScope RenderKit -Parameters @{
            LogPath = $directoryTarget
        } {
            $previousPreference = $WarningPreference
            try {
                $WarningPreference = 'Stop'

                {
                    Write-RenderKitWorkerLogEntry `
                        -WorkerId 'strict-warning-worker' `
                        -Message 'diagnostic message' `
                        -LogPath $LogPath |
                        Out-Null
                } | Should -Not -Throw
            }
            finally {
                $WarningPreference = $previousPreference
            }
        }
    }

    It 'does not fail when default log-path resolution itself fails' {
        InModuleScope RenderKit {
            Mock Get-RenderKitWorkerLogPath {
                throw 'worker log root is unavailable'
            }

            {
                Write-RenderKitWorkerLogEntry `
                    -WorkerId 'resolver-failure-worker' `
                    -Message 'diagnostic message' |
                    Out-Null
            } | Should -Not -Throw

            Assert-MockCalled Get-RenderKitWorkerLogPath -Times 1 -Exactly
        }
    }

    It 'documents why worker logging is best-effort' {
        $definition = InModuleScope RenderKit {
            (Get-Command Write-RenderKitWorkerLogEntry).Definition
        }

        $definition | Should -Match 'RS-1513'
        $definition | Should -Match 'Path resolution belongs inside the same protected'
        $definition | Should -Match 'ErrorAction Stop'
        $definition | Should -Match 'WarningAction Continue'
    }
}
