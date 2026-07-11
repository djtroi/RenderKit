Describe 'RenderKit engine publication operations' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:RenderKitModuleRoot = $repositoryRoot
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.StorageService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.PersistenceService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Versioning/RenderKit.ArtifactVersionService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Publishing/RenderKit.PublishingScheduleService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Engine/RenderKit.EngineContractService.ps1')
    }

    BeforeEach {
        $env:RENDERKIT_HOME = Join-Path $TestDrive 'renderkit-home'
        if (Test-Path -LiteralPath $env:RENDERKIT_HOME) {
            Remove-Item -LiteralPath $env:RENDERKIT_HOME -Recurse -Force
        }
        $script:RenderKitArtifactVersionCatalog = $null
        $script:Actor = New-RenderKitActorContext `
            -ActorId 'user-1' `
            -ActorType User `
            -DisplayName 'Studio User' `
            -Source 'LocalBroker'
    }

    AfterEach {
        $env:RENDERKIT_HOME = $null
    }

    It 'creates, pages, and resolves publication details' {
        $created = New-RenderKitEnginePublication `
            -Title 'Release trailer' `
            -Description 'Private detail' `
            -Status Scheduled `
            -StartUtc '2026-07-10T18:00:00Z' `
            -TimeZone 'Europe/Berlin' `
            -Actor $script:Actor
        $list = Get-RenderKitEnginePublicationList `
            -FromUtc '2026-07-01T00:00:00Z' `
            -ToUtc '2026-08-01T00:00:00Z' `
            -Limit 1
        $detail = Get-RenderKitEnginePublicationDetail `
            -PublicationId $created.data.id

        $created.success | Should -BeTrue
        $list.success | Should -BeTrue
        $list.data.total | Should -Be 1
        @($list.data.items).Count | Should -Be 1
        $list.data.items[0].PSObject.Properties.Name |
            Should -Not -Contain 'description'
        $detail.data.description | Should -Be 'Private detail'
    }

    It 'updates, cancels, and reports stale revisions as conflicts' {
        $created = New-RenderKitEnginePublication `
            -Title 'Release trailer' `
            -Status Scheduled `
            -StartUtc '2026-07-10T18:00:00Z' `
            -TimeZone UTC `
            -Actor $script:Actor
        $cancelled = Set-RenderKitEnginePublication `
            -PublicationId $created.data.id `
            -ExpectedRevision 1 `
            -Changes @{ Status = 'Cancelled' } `
            -Actor $script:Actor
        $conflict = Set-RenderKitEnginePublication `
            -PublicationId $created.data.id `
            -ExpectedRevision 1 `
            -Changes @{ Title = 'Stale title' } `
            -Actor $script:Actor

        $cancelled.success | Should -BeTrue
        $cancelled.data.status | Should -Be 'Cancelled'
        $conflict.success | Should -BeFalse
        $conflict.error.code | Should -Be 'RK_CONFLICT'
    }

    It 'requires actor context before creating or updating a publication' {
        $rejectedCreate = New-RenderKitEnginePublication `
            -Title 'Rejected' `
            -StartUtc '2026-07-10T18:00:00Z' `
            -TimeZone UTC
        $created = New-RenderKitEnginePublication `
            -Title 'Allowed' `
            -StartUtc '2026-07-10T18:00:00Z' `
            -TimeZone UTC `
            -Actor $script:Actor
        $rejectedUpdate = Set-RenderKitEnginePublication `
            -PublicationId $created.data.id `
            -ExpectedRevision 1 `
            -Changes @{ Status = 'Cancelled' }
        $persisted = Get-RenderKitPublicationRecord -Id $created.data.id

        $rejectedCreate.error.code | Should -Be 'RK_ACCESS_CONTEXT_MISSING'
        $rejectedUpdate.error.code | Should -Be 'RK_ACCESS_CONTEXT_MISSING'
        @(Get-RenderKitPublicationRecordList `
            -FromUtc '2026-07-01T00:00:00Z' `
            -ToUtc '2026-08-01T00:00:00Z').Count | Should -Be 1
        $persisted.status | Should -Be 'Draft'
        $persisted.revision | Should -Be 1
    }

    It 'maps invalid ranges and missing detail to stable errors' {
        $invalid = Get-RenderKitEnginePublicationList `
            -FromUtc '2026-08-01T00:00:00Z' `
            -ToUtc '2026-07-01T00:00:00Z'
        $missing = Get-RenderKitEnginePublicationDetail `
            -PublicationId missing

        $invalid.error.code | Should -Be 'RK_VALIDATION_FAILED'
        $missing.error.code | Should -Be 'RK_NOT_FOUND'
    }
}
