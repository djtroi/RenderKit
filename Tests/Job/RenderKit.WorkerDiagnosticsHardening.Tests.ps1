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

        $result = InModuleScope RenderKit -Parameters @{
            LogPath = $directoryTarget
        } {
            $previousPreference = $WarningPreference
            try {
                $WarningPreference = 'Stop'
                Write-RenderKitWorkerLogEntry `
                    -WorkerId 'strict-warning-worker' `
                    -Message 'diagnostic message' `
                    -LogPath $LogPath `
                    -WarningVariable warningRecord

                [PSCustomObject]@{
                    warningCount = @($warningRecord).Count
                    completed = $true
                }
            }
            finally {
                $WarningPreference = $previousPreference
            }
        }

        $result.completed | Should -BeTrue
        $result.warningCount | Should -Be 1
    }

    It 'documents why worker logging is best-effort' {
        $definition = InModuleScope RenderKit {
            (Get-Command Write-RenderKitWorkerLogEntry).Definition
        }

        $definition | Should -Match 'persisted worker/job state remains the durable source of truth'
        $definition | Should -Match 'ErrorAction Stop'
        $definition | Should -Match 'WarningAction Continue'
    }
}
