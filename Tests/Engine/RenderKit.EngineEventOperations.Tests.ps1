$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:RenderKitModuleRoot = $repositoryRoot
. (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.StorageService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.PersistenceService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Versioning/RenderKit.ArtifactVersionService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Event/RenderKit.EventService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Job/RenderKit.JobService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Automation/RenderKit.EventJobBridgeService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Engine/RenderKit.EngineContractService.ps1')

Describe 'RenderKit engine event operations' {
    BeforeEach {
        $env:RENDERKIT_HOME = Join-Path $TestDrive 'renderkit-home'
        $script:RenderKitArtifactVersionCatalog = $null
        $script:RenderKitEventJobSubscriptionCatalog = $null
        $script:actor = New-RenderKitActorContext `
            -ActorId 'user-1' `
            -ActorType User `
            -DisplayName 'Test User' `
            -Source 'LocalBroker'
    }

    AfterEach {
        $env:RENDERKIT_HOME = $null
    }

    It 'returns event list results in a RenderKitResult envelope' {
        Add-RenderKitDomainEvent -Event (
            New-RenderKitDomainEvent `
                -EventType 'ProjectLifecycleStatusChanged' `
                -AggregateType 'Project' `
                -AggregateId 'project-1' `
                -Payload ([PSCustomObject]@{ toStatus = 'Active' })
        ) | Out-Null

        $result = Get-RenderKitEngineEventList `
            -AggregateType Project `
            -AggregateId 'project-1' `
            -Actor $script:actor

        $result.success | Should -BeTrue
        @($result.data).Count | Should -Be 1
        $result.data[0].eventType | Should -Be 'ProjectLifecycleStatusChanged'
        $result.data[0].data.toStatus | Should -Be 'Active'
        $result.actor.actorId | Should -Be 'user-1'
    }

    It 'returns event detail by event id alias' {
        $event = Add-RenderKitDomainEvent -Event (
            New-RenderKitDomainEvent `
                -EventType 'ProjectLifecycleStatusChanged' `
                -AggregateType 'Project' `
                -AggregateId 'project-2'
        )

        $result = Get-RenderKitEngineEventDetail `
            -EventId $event.eventId `
            -Actor $script:actor

        $result.success | Should -BeTrue
        $result.data.id | Should -Be $event.id
    }

    It 'returns a stable not-found error for missing event detail' {
        $result = Get-RenderKitEngineEventDetail `
            -EventId 'missing-event' `
            -Actor $script:actor

        $result.success | Should -BeFalse
        $result.error.code | Should -Be 'RK_NOT_FOUND'
        $result.error.details.eventId | Should -Be 'missing-event'
    }

    It 'requires an actor for event bridge invocation' {
        $result = Invoke-RenderKitEngineEventBridge

        $result.success | Should -BeFalse
        $result.error.code | Should -Be 'RK_ACCESS_CONTEXT_MISSING'
    }

    It 'invokes the event bridge and returns created job metadata' {
        $event = Add-RenderKitDomainEvent -Event (
            New-RenderKitDomainEvent `
                -EventType 'ProjectLifecycleStatusChanged' `
                -AggregateType 'Project' `
                -AggregateId 'project-3'
        )

        $result = Invoke-RenderKitEngineEventBridge -Actor $script:actor

        $result.success | Should -BeTrue
        $result.data.ProcessedEventCount | Should -Be 1
        $result.data.CreatedJobCount | Should -Be 1
        $result.data.ProcessedEventIds[0] | Should -Be $event.id
    }
}