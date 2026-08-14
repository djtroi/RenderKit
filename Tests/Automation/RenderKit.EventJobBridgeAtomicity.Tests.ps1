Describe 'RenderKit event/job bridge atomicity' {
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

    It 'adds an event-derived job only once through the transactional helper' {
        $result = InModuleScope RenderKit {
            $event = New-RenderKitDomainEvent `
                -EventType 'ProjectLifecycleStatusChanged' `
                -AggregateType 'Project' `
                -AggregateId 'atomic-project'
            $subscription = @(Get-RenderKitEventJobSubscription `
                -EventType 'ProjectLifecycleStatusChanged')[0]
            $job = New-RenderKitJobFromDomainEvent `
                -Event $event `
                -Subscription $subscription

            $first = Add-RenderKitEventJobIfMissing -Job $job
            $second = Add-RenderKitEventJobIfMissing -Job $job

            [PSCustomObject]@{
                first = $first
                second = $second
                count = @((Read-RenderKitJobStore).jobs).Count
                definition = (Get-Command Add-RenderKitEventJobIfMissing).Definition
            }
        }

        $result.first | Should -Not -BeNullOrEmpty
        $result.second | Should -BeNullOrEmpty
        $result.count | Should -Be 1
        $result.definition | Should -Match 'Invoke-RenderKitJsonFileTransaction'
        $result.definition | Should -Match 'duplicate check and append must share the same file transaction'
    }
}
