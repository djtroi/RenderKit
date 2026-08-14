Describe 'RS-1515 worker recovery host guard' {
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

    It 'does not classify foreign worker state as a local crash' {
        $result = InModuleScope RenderKit {
            $previous = [PSCustomObject]@{
                status = 'Running'
                machine = 'definitely-not-this-machine'
                processId = $PID
            }
            Mock Read-RenderKitWorkerState { $previous }
            Mock Test-RenderKitWorkerProcessAlive {
                throw 'foreign state must not reach local PID probing'
            }

            $outcome = Register-RenderKitWorkerCrashIfNeeded `
                -WorkerId 'foreign-worker'
            [PSCustomObject]@{
                outcome = $outcome
                pidProbeCalls = (Get-MockCalledCount `
                    -CommandName Test-RenderKitWorkerProcessAlive)
            }
        }

        $result.outcome.crashDetected | Should -BeFalse
        $result.pidProbeCalls | Should -Be 0
    }

    It 'does not classify legacy state without machine identity as a local crash' {
        $result = InModuleScope RenderKit {
            $previous = [PSCustomObject]@{
                status = 'Idle'
                machine = $null
                processId = 2147483647
            }
            Mock Read-RenderKitWorkerState { $previous }
            Mock Test-RenderKitWorkerProcessAlive {
                throw 'unowned legacy state must not reach local PID probing'
            }

            $outcome = Register-RenderKitWorkerCrashIfNeeded `
                -WorkerId 'legacy-worker'
            [PSCustomObject]@{
                outcome = $outcome
                pidProbeCalls = (Get-MockCalledCount `
                    -CommandName Test-RenderKitWorkerProcessAlive)
            }
        }

        $result.outcome.crashDetected | Should -BeFalse
        $result.pidProbeCalls | Should -Be 0
    }

    It 'treats an invalid PID as dead only after local host ownership is confirmed' {
        $result = InModuleScope RenderKit {
            $previous = [PSCustomObject]@{
                status = 'Running'
                machine = [System.Environment]::MachineName
                processId = 'invalid-pid'
                processedCount = 2
                idleTickCount = 1
                recoveredJobIds = @()
                startedAtUtc = (Get-Date).ToUniversalTime().AddMinutes(-5).ToString('o')
            }
            Mock Read-RenderKitWorkerState { $previous }
            Mock Test-RenderKitWorkerProcessAlive { $true }
            Mock New-RenderKitWorkerState {
                [PSCustomObject]@{
                    status = 'CrashDetected'
                    stoppedAtUtc = $null
                }
            }
            Mock Save-RenderKitWorkerState { 'ignored-state-path' }
            Mock Write-RenderKitWorkerLogEntry { $null }

            $outcome = Register-RenderKitWorkerCrashIfNeeded `
                -WorkerId 'local-invalid-pid-worker' `
                -LogPath 'worker.log'
            [PSCustomObject]@{
                outcome = $outcome
                pidProbeCalls = (Get-MockCalledCount `
                    -CommandName Test-RenderKitWorkerProcessAlive)
                saveCalls = (Get-MockCalledCount `
                    -CommandName Save-RenderKitWorkerState)
            }
        }

        $result.outcome.crashDetected | Should -BeTrue
        $result.pidProbeCalls | Should -Be 0
        $result.saveCalls | Should -Be 1
    }

    It 'documents the host ownership boundary in crash recovery' {
        $definition = InModuleScope RenderKit {
            (Get-Command Register-RenderKitWorkerCrashIfNeeded).Definition
        }

        $definition | Should -Match 'RS-1515'
        $definition | Should -Match 'PID is scoped to the host'
        $definition | Should -Match 'isLocalState'
    }
}
