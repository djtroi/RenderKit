Describe 'RS-1511 job worker persisted state hardening' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (
            Split-Path -Parent $PSScriptRoot)
        Import-Module `
            (Join-Path $repositoryRoot 'RenderKit.psd1') `
            -Force
    }

    BeforeEach {
        $env:RENDERKIT_HOME = Join-Path $TestDrive 'renderkit-home'
        if (Test-Path -LiteralPath $env:RENDERKIT_HOME) {
            Remove-Item -LiteralPath $env:RENDERKIT_HOME -Recurse -Force
        }
    }

    AfterEach {
        $env:RENDERKIT_HOME = $null
    }

    AfterAll {
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
    }

    It 'preserves a failure persisted by a handler that returns normally' {
        $result = InModuleScope RenderKit {
            Register-RenderKitJobHandler `
                -JobType 'RS1511PersistedFailureReturn' `
                -Handler {
                    param($Job)
                    Set-RenderKitJobStatus `
                        -JobId ([string]$Job.id) `
                        -Status Failed `
                        -ErrorMessage 'handler persisted failure'
                }

            $job = Add-RenderKitJob -Job (
                New-RenderKitJob -JobType 'RS1511PersistedFailureReturn'
            )

            Invoke-RenderKitJob -JobId ([string]$job.id)
        }

        $result.status | Should -Be 'Failed'
        $result.lastError.message | Should -Be 'handler persisted failure'
        [int]$result.attempts | Should -Be 1
    }

    It 'preserves a failure persisted before the handler throws' {
        $result = InModuleScope RenderKit {
            Register-RenderKitJobHandler `
                -JobType 'RS1511PersistedFailureThrow' `
                -Handler {
                    param($Job)
                    Set-RenderKitJobStatus `
                        -JobId ([string]$Job.id) `
                        -Status Failed `
                        -ErrorMessage 'authoritative handler failure'
                    throw 'secondary handler exception'
                }

            $job = Add-RenderKitJob -Job (
                New-RenderKitJob -JobType 'RS1511PersistedFailureThrow'
            )

            Invoke-RenderKitJob -JobId ([string]$job.id)
        }

        $result.status | Should -Be 'Failed'
        $result.lastError.message | Should -Be 'authoritative handler failure'
        [int]$result.attempts | Should -Be 1
    }

    It 'still auto-completes a handler that leaves the job running' {
        $result = InModuleScope RenderKit {
            Register-RenderKitJobHandler `
                -JobType 'RS1511NormalCompletion' `
                -Handler {
                    param($Job)
                }

            $job = Add-RenderKitJob -Job (
                New-RenderKitJob -JobType 'RS1511NormalCompletion'
            )

            Invoke-RenderKitJob -JobId ([string]$job.id)
        }

        $result.status | Should -Be 'Succeeded'
        [int]$result.attempts | Should -Be 1
    }

    It 'still applies generic retry handling when a running handler throws' {
        $result = InModuleScope RenderKit {
            Register-RenderKitJobHandler `
                -JobType 'RS1511GenericFailure' `
                -Handler {
                    param($Job)
                    throw 'unhandled handler failure'
                }

            $job = Add-RenderKitJob -Job (
                New-RenderKitJob -JobType 'RS1511GenericFailure'
            )

            Invoke-RenderKitJob -JobId ([string]$job.id)
        }

        $result.status | Should -Be 'Queued'
        [int]$result.attempts | Should -Be 1
    }

    It 'documents the authoritative persisted-state policy in the worker implementation' {
        $definition = InModuleScope RenderKit {
            (Get-Command Invoke-RenderKitJob).Definition
        }

        $definition | Should -Match 'RS-1511'
        $definition | Should -Match 'Handler-owned persisted state is authoritative'
        $definition | Should -Match "status -ne 'Running'"
    }
}
