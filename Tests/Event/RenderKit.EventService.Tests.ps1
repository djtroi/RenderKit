Describe 'RenderKit event service' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:RenderKitModuleRoot = $repositoryRoot
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.StorageService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.PersistenceService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Versioning/RenderKit.ArtifactVersionService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Event/RenderKit.EventService.ps1')
    }
    BeforeEach {
        $env:RENDERKIT_HOME = Join-Path $TestDrive 'renderkit-home'
        if (Test-Path -LiteralPath $env:RENDERKIT_HOME) {
            Remove-Item -LiteralPath $env:RENDERKIT_HOME -Recurse -Force
        }
        $script:RenderKitArtifactVersionCatalog = $null
    }

    AfterEach {
        $env:RENDERKIT_HOME = $null
    }

    It 'creates an empty event store when none exists' {
        $store = Read-RenderKitEventStore
        $store.tool | Should -Be 'RenderKit'
        $store.schemaVersion | Should -Be '1.1'
        @($store.events).Count | Should -Be 0
    }

    It 'appends pending domain events' {
        $event = New-RenderKitDomainEvent `
            -EventType 'ProjectLifecycleStatusChanged' `
            -AggregateType 'Project' `
            -AggregateId 'project-1' `
            -Payload ([PSCustomObject]@{ toStatus = 'Active' })

        Add-RenderKitDomainEvent -Event $event | Out-Null

        $pending = @(Get-RenderKitPendingDomainEvent)
        $pending.Count | Should -Be 1
        $pending[0].eventType | Should -Be 'ProjectLifecycleStatusChanged'
        $pending[0].eventId | Should -Be $pending[0].id
        $pending[0].eventSchemaVersion | Should -Be '1.0'
        $pending[0].category | Should -Be 'Domain'
        $pending[0].data.toStatus | Should -Be 'Active'
    }

    It 'normalizes legacy events into the vNext envelope' {
        $legacy = [PSCustomObject]@{
            id            = [guid]::NewGuid().ToString()
            eventType     = 'LegacyEvent'
            aggregateType = 'Project'
            aggregateId   = 'project-legacy'
            occurredAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            correlationId = [guid]::NewGuid().ToString()
            status        = 'Pending'
            payload       = [PSCustomObject]@{ value = 1 }
        }

        $normalized = ConvertTo-RenderKitDomainEventVNext -Event $legacy

        $normalized.eventId | Should -Be $legacy.id
        $normalized.eventSchemaVersion | Should -Be '1.0'
        $normalized.category | Should -Be 'Domain'
        $normalized.retention | Should -Be 'Indefinite'
        $normalized.data.value | Should -Be 1
        $normalized.payload.value | Should -Be 1
    }

    It 'filters event lists by aggregate and category' {
        Add-RenderKitDomainEvent -Event (
            New-RenderKitDomainEvent `
                -EventType 'RenderKitDiagnostic' `
                -AggregateType 'System' `
                -AggregateId 'renderkit' `
                -Category Diagnostic
        ) | Out-Null
        Add-RenderKitDomainEvent -Event (
            New-RenderKitDomainEvent `
                -EventType 'ProjectLifecycleStatusChanged' `
                -AggregateType 'Project' `
                -AggregateId 'project-1'
        ) | Out-Null

        $events = @(Get-RenderKitDomainEventList `
                -AggregateType Project `
                -AggregateId 'project-1' `
                -Category Domain)

        $events.Count | Should -Be 1
        $events[0].aggregateId | Should -Be 'project-1'
    }

    It 'filters pending domain events by type' {
        Add-RenderKitDomainEvent -Event (
            New-RenderKitDomainEvent `
                -EventType 'ProjectLifecycleStatusChanged' `
                -AggregateType 'Project' `
                -AggregateId 'project-1'
        ) | Out-Null
        Add-RenderKitDomainEvent -Event (
            New-RenderKitDomainEvent `
                -EventType 'RenderKitDiagnostic' `
                -AggregateType 'System' `
                -AggregateId 'renderkit'
        ) | Out-Null

        @(Get-RenderKitPendingDomainEvent `
            -EventType 'ProjectLifecycleStatusChanged').Count |
            Should -Be 1
    }

    It 'marks events as processed' {
        $event = Add-RenderKitDomainEvent -Event (
            New-RenderKitDomainEvent `
                -EventType 'ProjectLifecycleStatusChanged' `
                -AggregateType 'Project' `
                -AggregateId 'project-2'
        )

        Set-RenderKitDomainEventStatus `
            -EventId $event.id `
            -Status Processed

        @(Get-RenderKitPendingDomainEvent).Count | Should -Be 0
        $stored = Get-RenderKitDomainEvent -EventId $event.eventId
        $stored.processedAtUtc | Should -Not -BeNullOrEmpty
    }

    It 'emits project lifecycle events' {
        $metadata = [PSCustomObject]@{
            project = @{
                id = 'project-3'
                name = 'ClientA'
            }
        }

        Write-RenderKitProjectLifecycleEvent `
            -Metadata $metadata `
            -ProjectRoot $TestDrive `
            -FromStatus Draft `
            -ToStatus Active `
            -Reason 'Media imported' `
            -Source 'Test' |
            Out-Null

        $event = @(Get-RenderKitPendingDomainEvent)[0]
        $event.payload.toStatus | Should -Be 'Active'
        $event.data.toStatus | Should -Be 'Active'
        $event.payload.source | Should -Be 'Test'
    }
}