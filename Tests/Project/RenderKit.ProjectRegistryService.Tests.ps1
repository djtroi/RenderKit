Describe 'RenderKit project registry service' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:RenderKitModuleRoot = $repositoryRoot
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.StorageService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.PersistenceService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Versioning/RenderKit.ArtifactVersionService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectRegistryService.ps1')
    }

    BeforeEach {
        $script:RenderKitArtifactVersionCatalog = $null
        $script:RenderKitArtifactMigrations = @{}
        $script:RenderKitModuleVersion = '0.0.0'
        $env:RENDERKIT_HOME = Join-Path $TestDrive 'renderkit-home'
    }

    AfterEach {
        $env:RENDERKIT_HOME = $null
    }

    It 'creates an empty registry when no registry exists' {
        $registry = Read-RenderKitProjectRegistry
        $registry.tool | Should -Be 'RenderKit'
        $registry.schemaVersion | Should -Be '1.0'
        @($registry.projects).Count | Should -Be 0
    }

    It 'upserts projects by id and root path' {
        $root = Join-Path $TestDrive 'ClientA'
        New-Item -ItemType Directory -Path $root | Out-Null

        Set-RenderKitProjectRegistryEntry `
            -ProjectId 'project-1' `
            -ProjectName 'ClientA' `
            -ProjectRoot $root |
            Out-Null
        Set-RenderKitProjectRegistryEntry `
            -ProjectId 'project-1' `
            -ProjectName 'ClientA_Renamed' `
            -ProjectRoot $root |
            Out-Null

        $registry = Read-RenderKitProjectRegistry
        @($registry.projects).Count | Should -Be 1
        $registry.projects[0].name | Should -Be 'ClientA_Renamed'
    }

    It 'resolves a unique project by name' {
        $root = Join-Path $TestDrive 'ClientB'
        New-Item -ItemType Directory -Path $root | Out-Null
        Set-RenderKitProjectRegistryEntry `
            -ProjectId 'project-2' `
            -ProjectName 'ClientB' `
            -ProjectRoot $root |
            Out-Null

        $entry = Resolve-RenderKitProjectRegistryEntry -ProjectName 'ClientB'
        $entry.id | Should -Be 'project-2'
        $entry.rootPath | Should -Be ([System.IO.Path]::GetFullPath($root))
    }

    It 'does not resolve missing project folders' {
        $root = Join-Path $TestDrive 'MissingProject'
        Set-RenderKitProjectRegistryEntry `
            -ProjectId 'project-3' `
            -ProjectName 'MissingProject' `
            -ProjectRoot $root |
            Out-Null

        Resolve-RenderKitProjectRegistryEntry -ProjectName 'MissingProject' |
            Should -Be $null
    }

    It 'marks stale registry entries during repair' {
        $root = Join-Path $TestDrive 'StaleProject'
        New-Item -ItemType Directory -Path $root | Out-Null
        Set-RenderKitProjectRegistryEntry `
            -ProjectId 'project-4' `
            -ProjectName 'StaleProject' `
            -ProjectRoot $root |
            Out-Null
        Remove-Item -LiteralPath $root -Recurse -Force

        $registry = Repair-RenderKitProjectRegistry
        [bool]$registry.projects[0].exists | Should -BeFalse
    }
}