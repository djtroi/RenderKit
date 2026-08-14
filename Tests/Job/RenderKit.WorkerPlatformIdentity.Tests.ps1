Describe 'RenderKit worker platform identity' {
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

    It 'stores the portable machine identity in worker state' {
        $state = InModuleScope RenderKit {
            New-RenderKitWorkerState -WorkerId 'platform-worker'
        }

        $state.machine | Should -Be ([System.Environment]::MachineName)
    }

    It 'checks a PID only when worker state identifies the current machine' {
        $result = InModuleScope RenderKit {
            [PSCustomObject]@{
                local = Test-RenderKitWorkerProcessAlive `
                    -ProcessId $PID `
                    -MachineName ([System.Environment]::MachineName)
                missingMachine = Test-RenderKitWorkerProcessAlive `
                    -ProcessId $PID `
                    -MachineName $null
                foreignMachine = Test-RenderKitWorkerProcessAlive `
                    -ProcessId $PID `
                    -MachineName 'definitely-not-this-machine'
            }
        }

        $result.local | Should -BeTrue
        $result.missingMachine | Should -BeFalse
        $result.foreignMachine | Should -BeFalse
    }
}
