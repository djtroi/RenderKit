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
            Assert-MockCalled `
                -CommandName Test-RenderKitWorkerProcessAlive `
                -Times 0 `
                -Exactly
            $outcome
        }

        $result.crashDetected | Should -BeFalse
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
            Assert-MockCalled `
                -CommandName Test-RenderKitWorkerProcessAlive `
                -Times 0 `
                -Exactly
            $outcome
        }

        $result.crashDetected | Should -BeFalse
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
            Assert-MockCalled `
                -CommandName Test-RenderKitWorkerProcessAlive `
                -Times 0 `
                -Exactly
            Assert-MockCalled `
                -CommandName Save-RenderKitWorkerState `
                -Times 1 `
                -Exactly
            $outcome
        }

        $result.crashDetected | Should -BeTrue
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
