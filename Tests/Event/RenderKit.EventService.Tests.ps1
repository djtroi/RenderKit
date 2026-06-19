$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:RenderKitModuleRoot = $repositoryRoot
. (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.StorageService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.PersistenceService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Versioning/RenderKit.ArtifactVersionService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Event/RenderKit.EventService.ps1')

Describe 'RenderKit event service' {
    BeforeEach {
        $env:RENDERKIT_HOME = Join-Path $TestDrive 'renderkit-home'
        $script:RenderKitArtifactVersionCatalog = $null
    }

    AfterEach {
        $env:RENDERKIT_HOME = $null
    }

    It 'creates an empty event store when none exists' {
        $store = Read-RenderKitEventStore
        $store.tool | Should -Be 'RenderKit'
        $store.schemaVersion | Should -Be '1.0'
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
        $event.payload.source | Should -Be 'Test'
    }
}