Describe 'RenderKit discovered project store service' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:RenderKitModuleRoot = $repositoryRoot
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.StorageService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.PersistenceService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Versioning/RenderKit.ArtifactVersionService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Global/Get-RenderKitConfig.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectSearchIndexService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.DiscoveredProjectStoreService.ps1')
    }

    BeforeEach {
        $script:RenderKitArtifactVersionCatalog = $null
        $script:RenderKitArtifactMigrations = @{}
        $script:RenderKitModuleVersion = '0.0.0'
        $env:RENDERKIT_HOME = Join-Path $TestDrive 'renderkit-home'
        if (Test-Path -LiteralPath $env:RENDERKIT_HOME) {
            Remove-Item -LiteralPath $env:RENDERKIT_HOME -Recurse -Force
        }
    }

    AfterEach {
        $env:RENDERKIT_HOME = $null
    }

    It 'creates an empty discovered project store when no store exists' {
        $store = Read-RenderKitDiscoveredProjectStore
        $store.tool | Should -Be 'RenderKit'
        $store.schemaVersion | Should -Be '1.0'
        @($store.projects).Count | Should -Be 0
    }

    It 'upserts a discovered project by id and root path' {
        $configuredRoot = Join-Path $TestDrive 'Projects'
        $projectRoot = Join-Path $configuredRoot 'ClientA'
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null

        Set-RenderKitDiscoveredProjectEntry `
            -ProjectId 'project-1' `
            -ProjectName 'ClientA' `
            -ProjectRoot $projectRoot `
            -ConfiguredProjectRoot $configuredRoot `
            -Source 'Discovery' |
            Out-Null
        Set-RenderKitDiscoveredProjectEntry `
            -ProjectId 'project-1' `
            -ProjectName 'ClientA_Renamed' `
            -ProjectRoot $projectRoot `
            -ConfiguredProjectRoot $configuredRoot `
            -Source 'GetProjectRefresh' |
            Out-Null

        $store = Read-RenderKitDiscoveredProjectStore
        @($store.projects).Count | Should -Be 1
        $store.projects[0].name | Should -Be 'ClientA_Renamed'
        $store.projects[0].locationType | Should -Be 'ProjectRoot'
        [bool]$store.projects[0].isInsideConfiguredProjectRoot | Should -BeTrue
        @($store.projects[0].sources) | Should -Contain 'Discovery'
        @($store.projects[0].sources) | Should -Contain 'GetProjectRefresh'
    }

    It 'classifies projects outside the configured root as custom paths' {
        $configuredRoot = Join-Path $TestDrive 'Projects'
        $customRoot = Join-Path $TestDrive 'External/ClientB'
        New-Item -ItemType Directory -Path $customRoot -Force | Out-Null

        $entry = Set-RenderKitDiscoveredProjectEntry `
            -ProjectId 'project-2' `
            -ProjectName 'ClientB' `
            -ProjectRoot $customRoot `
            -ConfiguredProjectRoot $configuredRoot `
            -Source 'Discovery'

        $entry.locationType | Should -Be 'CustomPath'
        [bool]$entry.isInsideConfiguredProjectRoot | Should -BeFalse
    }

    It 'keeps duplicate project ids when the root path differs' {
        $configuredRoot = Join-Path $TestDrive 'Projects'
        $firstRoot = Join-Path $configuredRoot 'CopyA'
        $secondRoot = Join-Path $configuredRoot 'CopyB'
        New-Item -ItemType Directory -Path $firstRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $secondRoot -Force | Out-Null

        Set-RenderKitDiscoveredProjectEntry `
            -ProjectId 'project-duplicate' `
            -ProjectName 'CopyA' `
            -ProjectRoot $firstRoot `
            -ConfiguredProjectRoot $configuredRoot |
            Out-Null
        Set-RenderKitDiscoveredProjectEntry `
            -ProjectId 'project-duplicate' `
            -ProjectName 'CopyB' `
            -ProjectRoot $secondRoot `
            -ConfiguredProjectRoot $configuredRoot `
            -ConflictStatus 'DuplicateProjectId' |
            Out-Null

        $store = Read-RenderKitDiscoveredProjectStore
        @($store.projects | Where-Object { [string]$_.id -eq 'project-duplicate' }).Count |
            Should -Be 2
    }

    It 'prepares duplicate project id conflict details for future repair' {
        $configuredRoot = Join-Path $TestDrive 'Projects'
        $firstRoot = Join-Path $configuredRoot 'DuplicateA'
        $secondRoot = Join-Path $configuredRoot 'DuplicateB'
        New-Item -ItemType Directory -Path $firstRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $secondRoot -Force | Out-Null

        Set-RenderKitDiscoveredProjectEntry `
            -ProjectId 'duplicate-project' `
            -ProjectName 'DuplicateA' `
            -ProjectRoot $firstRoot `
            -ConfiguredProjectRoot $configuredRoot |
            Out-Null
        Set-RenderKitDiscoveredProjectEntry `
            -ProjectId 'duplicate-project' `
            -ProjectName 'DuplicateB' `
            -ProjectRoot $secondRoot `
            -ConfiguredProjectRoot $configuredRoot |
            Out-Null

        $store = Update-RenderKitDiscoveredProjectConflicts
        $duplicates = @($store.projects | Where-Object {
            [string]$_.conflictStatus -eq 'DuplicateProjectId'
        })

        $duplicates.Count | Should -Be 2
        $duplicates[0].conflictDetails.type | Should -Be 'DuplicateProjectId'
        @($duplicates[0].conflictDetails.rootPaths).Count | Should -Be 2
    }

}