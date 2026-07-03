Describe 'RenderKit engine client operations' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:RenderKitModuleRoot = $repositoryRoot
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.StorageService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.PersistenceService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Versioning/RenderKit.ArtifactVersionService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Client/RenderKit.ClientRegistryService.ps1')
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

    It 'creates, pages, and resolves clients through result envelopes' {
        $created = New-RenderKitEngineClient `
            -DisplayName 'Client A' `
            -Tags @('priority') `
            -Actor $script:Actor
        New-RenderKitEngineClient `
            -DisplayName 'Client B' `
            -Actor $script:Actor |
            Out-Null

        $list = Get-RenderKitEngineClientList `
            -Search 'Client' `
            -Offset 0 `
            -Limit 1 `
            -Actor $script:Actor
        $detail = Get-RenderKitEngineClientDetail `
            -ClientId $created.data.id `
            -Actor $script:Actor

        $created.success | Should -BeTrue
        $list.success | Should -BeTrue
        $list.data.total | Should -Be 2
        @($list.data.items).Count | Should -Be 1
        $detail.success | Should -BeTrue
        $detail.data.displayName | Should -Be 'Client A'
    }

    It 'updates and archives clients through an explicit patch' {
        $created = New-RenderKitEngineClient `
            -DisplayName 'Client A' `
            -Actor $script:Actor
        $updated = Set-RenderKitEngineClient `
            -ClientId $created.data.id `
            -ExpectedRevision $created.data.revision `
            -Changes @{
                DisplayName = 'Client A Updated'
                Status = 'Archived'
            } `
            -Actor $script:Actor

        $updated.success | Should -BeTrue
        $updated.data.revision | Should -Be 2
        $updated.data.status | Should -Be 'Archived'
    }

    It 'maps missing and stale client updates to stable errors' {
        $missing = Get-RenderKitEngineClientDetail `
            -ClientId 'missing' `
            -Actor $script:Actor
        $created = New-RenderKitEngineClient `
            -DisplayName 'Client A' `
            -Actor $script:Actor
        Set-RenderKitEngineClient `
            -ClientId $created.data.id `
            -ExpectedRevision 1 `
            -Changes @{ Status = 'Inactive' } `
            -Actor $script:Actor |
            Out-Null
        $conflict = Set-RenderKitEngineClient `
            -ClientId $created.data.id `
            -ExpectedRevision 1 `
            -Changes @{ Status = 'Archived' } `
            -Actor $script:Actor

        $missing.success | Should -BeFalse
        $missing.error.code | Should -Be 'RK_NOT_FOUND'
        $conflict.success | Should -BeFalse
        $conflict.error.code | Should -Be 'RK_CONFLICT'
    }

    It 'requires actor context before creating or updating a client' {
        $rejectedCreate = New-RenderKitEngineClient `
            -DisplayName 'Rejected Client'
        $created = New-RenderKitEngineClient `
            -DisplayName 'Existing Client' `
            -Actor $script:Actor
        $rejectedUpdate = Set-RenderKitEngineClient `
            -ClientId $created.data.id `
            -ExpectedRevision $created.data.revision `
            -Changes @{ Status = 'Archived' }
        $persisted = Get-RenderKitClientRecord -Id $created.data.id

        $rejectedCreate.success | Should -BeFalse
        $rejectedCreate.error.code | Should -Be 'RK_ACCESS_CONTEXT_MISSING'
        $rejectedUpdate.success | Should -BeFalse
        $rejectedUpdate.error.code | Should -Be 'RK_ACCESS_CONTEXT_MISSING'
        @(Get-RenderKitClientRecordList).Count | Should -Be 1
        $persisted.status | Should -Be 'Active'
        $persisted.revision | Should -Be 1
    }
}
