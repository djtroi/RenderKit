Describe 'RS-1508 backup notifier host safety' {
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

    It 'records JobFailed without emitting a PowerShell ErrorRecord' {
        $result = InModuleScope RenderKit {
            $Error.Clear()
            $notification = Invoke-BackupLogNotifierAdapter `
                -Context ([PSCustomObject]@{
                    eventName = 'JobFailed'
                    job = [PSCustomObject]@{ id = 'host-safe-failure' }
                })

            [PSCustomObject]@{
                notification = $notification
                errorCount = $Error.Count
            }
        }

        $result.notification.delivered | Should -BeTrue
        $result.notification.channel | Should -Be 'RenderKitLog'
        $result.errorCount | Should -Be 0
    }
}
