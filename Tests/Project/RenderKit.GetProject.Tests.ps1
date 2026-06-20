Describe 'Get-Project' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Import-Module (Join-Path $repositoryRoot 'RenderKit.psd1') -Force
        $script:RenderKitModuleRoot = $repositoryRoot
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.StorageService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.PersistenceService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Versioning/RenderKit.ArtifactVersionService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectRegistryService.ps1')
        . (Join-Path $repositoryRoot 'src/Public/Get-Project.ps1')
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

    It 'exports the public project registry list command' {
        Get-Command -Module RenderKit -Name Get-Project | Should -Not -BeNullOrEmpty
    }

    It 'returns table-friendly known project summaries' {
        $root = Join-Path $TestDrive 'KnownProject'
        New-Item -ItemType Directory -Path $root | Out-Null
        $metadata = [PSCustomObject]@{ projectVersion = '2.5.0' }

        Set-RenderKitProjectRegistryEntry `
            -ProjectId 'known-project-1' `
            -ProjectName 'KnownProject' `
            -ProjectRoot $root `
            -Metadata $metadata |
            Out-Null

        $project = Get-Project | Select-Object -First 1

        $project.Name | Should -Be 'KnownProject'
        $project.Id | Should -Be 'known-project-1'
        $project.Available | Should -BeTrue
        $project.Version | Should -Be '2.5.0'
        $project.RootPath | Should -Be ([System.IO.Path]::GetFullPath($root))
        $project.MetadataPath | Should -Not -BeNullOrEmpty
        $project.UpdatedAtUtc | Should -Not -BeNullOrEmpty
    }

    It 'can return only currently available projects' {
        $availableRoot = Join-Path $TestDrive 'AvailableProject'
        New-Item -ItemType Directory -Path $availableRoot | Out-Null
        Set-RenderKitProjectRegistryEntry `
            -ProjectId 'available-project' `
            -ProjectName 'AvailableProject' `
            -ProjectRoot $availableRoot |
            Out-Null

        $missingRoot = Join-Path $TestDrive 'MissingProject'
        Set-RenderKitProjectRegistryEntry `
            -ProjectId 'missing-project' `
            -ProjectName 'MissingProject' `
            -ProjectRoot $missingRoot |
            Out-Null

        $projects = @(Get-Project -AvailableOnly)

        $projects.Name | Should -Contain 'AvailableProject'
        $projects.Name | Should -Not -Contain 'MissingProject'
    }

    It 'refreshes availability markers before listing projects' {
        $root = Join-Path $TestDrive 'RemovedProject'
        New-Item -ItemType Directory -Path $root | Out-Null
        Set-RenderKitProjectRegistryEntry `
            -ProjectId 'removed-project' `
            -ProjectName 'RemovedProject' `
            -ProjectRoot $root |
            Out-Null
        Remove-Item -LiteralPath $root -Recurse -Force

        $project = Get-Project -Refresh | Select-Object -First 1

        $project.Name | Should -Be 'RemovedProject'
        $project.Available | Should -BeFalse
    }
}