Describe 'RenderKit client registry service' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:RenderKitModuleRoot = $repositoryRoot
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.StorageService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.PersistenceService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Versioning/RenderKit.ArtifactVersionService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Client/RenderKit.ClientRegistryService.ps1')
    }

    BeforeEach {
        $script:RenderKitArtifactVersionCatalog = $null
        $script:RenderKitArtifactMigrations = @{}
        $env:RENDERKIT_HOME = Join-Path $TestDrive 'renderkit-home'
        if (Test-Path -LiteralPath $env:RENDERKIT_HOME) {
            Remove-Item -LiteralPath $env:RENDERKIT_HOME -Recurse -Force
        }
    }

    AfterEach {
        $env:RENDERKIT_HOME = $null
    }

    It 'creates an empty versioned registry when the store is absent' {
        $registry = Read-RenderKitClientRegistry

        $registry.tool | Should -Be 'RenderKit'
        $registry.schemaVersion | Should -Be '1.0'
        @($registry.clients).Count | Should -Be 0
    }

    It 'atomically creates and filters normalized client records' {
        $client = New-RenderKitClientRecord `
            -DisplayName '  Concept MARTON  ' `
            -LegalName ' Concept MARTON GmbH ' `
            -Tags @('Production', 'production', ' Priority ') `
            -Contacts @(
                [PSCustomObject]@{
                    displayName = 'Ada Lovelace'
                    email = 'ada@example.test'
                    isPrimary = $true
                }
            )
        $persisted = Add-RenderKitClientRecord -Client $client

        $persisted.displayName | Should -Be 'Concept MARTON'
        $persisted.revision | Should -Be 1
        @($persisted.tags).Count | Should -Be 2
        $persisted.contacts[0].id | Should -Not -BeNullOrEmpty
        @(Get-RenderKitClientRecordList -Search 'MARTON').Count |
            Should -Be 1
        @(Get-RenderKitClientRecordList -Tag 'priority').Count |
            Should -Be 1
    }

    It 'updates with an expected revision and rejects stale writes' {
        $created = Add-RenderKitClientRecord -Client (
            New-RenderKitClientRecord -DisplayName 'Client A'
        )
        $updated = Update-RenderKitClientRecord `
            -Id $created.id `
            -ExpectedRevision 1 `
            -Changes @{
                DisplayName = 'Client A Updated'
                Status = 'Inactive'
            }

        $updated.revision | Should -Be 2
        $updated.displayName | Should -Be 'Client A Updated'
        $updated.status | Should -Be 'Inactive'
        {
            Update-RenderKitClientRecord `
                -Id $created.id `
                -ExpectedRevision 1 `
                -Changes @{ Status = 'Archived' }
        } | Should -Throw '*changed from revision*'
        (Get-RenderKitClientRecord -Id $created.id).status |
            Should -Be 'Inactive'
    }

    It 'rejects unsafe field bounds and multiple primary contacts' {
        {
            New-RenderKitClientRecord -DisplayName ('x' * 256)
        } | Should -Throw '*255 character limit*'

        {
            New-RenderKitClientRecord `
                -DisplayName 'Client' `
                -Contacts @(
                    @{ displayName = 'One'; isPrimary = $true },
                    @{ displayName = 'Two'; isPrimary = $true }
                )
        } | Should -Throw '*only one primary contact*'
    }

    It 'does not infer clients from project or metadata names' {
        Add-RenderKitClientRecord -Client (
            New-RenderKitClientRecord -DisplayName 'Explicit Client'
        ) | Out-Null

        @(Get-RenderKitClientRecordList -Search 'Unrelated Project').Count |
            Should -Be 0
    }
}
