Describe 'RenderKit event/job bridge service' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:RenderKitModuleRoot = $repositoryRoot
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.StorageService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.PersistenceService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Versioning/RenderKit.ArtifactVersionService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Event/RenderKit.EventService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Job/RenderKit.JobService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Automation/RenderKit.EventJobBridgeService.ps1')
    }
    BeforeEach {
        $env:RENDERKIT_HOME = Join-Path $TestDrive 'renderkit-home'
        if (Test-Path -LiteralPath $env:RENDERKIT_HOME) {
            Remove-Item -LiteralPath $env:RENDERKIT_HOME -Recurse -Force
        }
        $script:RenderKitArtifactVersionCatalog = $null
        $script:RenderKitEventJobSubscriptionCatalog = $null
    }

    AfterEach {
        $env:RENDERKIT_HOME = $null
    }

    It 'loads enabled lifecycle subscriptions' {
        $subscriptions = @(Get-RenderKitEventJobSubscription `
            -EventType 'ProjectLifecycleStatusChanged')

        $subscriptions.Count | Should -Be 1
        $subscriptions[0].JobType | Should -Be 'ProjectLifecycleAutomation'
    }

    It 'creates jobs for pending matching events' {
        $event = New-RenderKitDomainEvent `
            -EventType 'ProjectLifecycleStatusChanged' `
            -AggregateType 'Project' `
            -AggregateId 'project-1' `
            -Payload ([PSCustomObject]@{ toStatus = 'Active' })
        Add-RenderKitDomainEvent -Event $event | Out-Null

        $result = Invoke-RenderKitEventJobBridge

        $result.ProcessedEventCount | Should -Be 1
        $result.CreatedJobCount | Should -Be 1
        $job = @(Get-RenderKitQueuedJob)[0]
        $job.jobType | Should -Be 'ProjectLifecycleAutomation'
        $job.triggerEventId | Should -Be $event.id
    }

    It 'marks processed events as no longer pending' {
        Add-RenderKitDomainEvent -Event (
            New-RenderKitDomainEvent `
                -EventType 'ProjectLifecycleStatusChanged' `
                -AggregateType 'Project' `
                -AggregateId 'project-2'
        ) | Out-Null

        Invoke-RenderKitEventJobBridge | Out-Null

        @(Get-RenderKitPendingDomainEvent).Count | Should -Be 0
    }

    It 'does not duplicate jobs for the same trigger event' {
        $event = Add-RenderKitDomainEvent -Event (
            New-RenderKitDomainEvent `
                -EventType 'ProjectLifecycleStatusChanged' `
                -AggregateType 'Project' `
                -AggregateId 'project-3'
        )

        Invoke-RenderKitEventJobBridge | Out-Null
        Set-RenderKitDomainEventStatus -EventId $event.id -Status Pending
        $secondResult = Invoke-RenderKitEventJobBridge

        $secondResult.CreatedJobCount | Should -Be 0
        @((Read-RenderKitJobStore).jobs).Count | Should -Be 1
    }
}