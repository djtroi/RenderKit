Describe 'RenderKit job worker persisted state hardening' {
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

    It 'does not overwrite a state persisted deliberately by a handler' {
        $result = InModuleScope RenderKit {
            Register-RenderKitJobHandler `
                -JobType 'PersistedFailureJob' `
                -Handler {
                    param($Job)
                    Set-RenderKitJobStatus `
                        -JobId ([string]$Job.id) `
                        -Status Failed `
                        -ErrorMessage 'handler persisted failure'
                    throw 'secondary handler exception'
                }

            $job = Add-RenderKitJob -Job (
                New-RenderKitJob -JobType 'PersistedFailureJob'
            )

            Invoke-RenderKitJob -JobId ([string]$job.id)
        }

        $result.status | Should -Be 'Failed'
        $result.lastError.message | Should -Be 'handler persisted failure'
        [int]$result.attempts | Should -Be 1
    }
}
