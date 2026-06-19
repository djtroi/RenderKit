$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:RenderKitModuleRoot = $repositoryRoot
. (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.StorageService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.PersistenceService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Versioning/RenderKit.ArtifactVersionService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectRegistryService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Event/RenderKit.EventService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Job/RenderKit.JobService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Maintenance/RenderKit.RepairService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Engine/RenderKit.EngineContractService.ps1')

Describe 'RenderKit engine read model operations' {
    BeforeEach {
        $env:RENDERKIT_HOME = Join-Path $TestDrive 'renderkit-home'
        $script:RenderKitArtifactVersionCatalog = $null
        $script:RenderKitModuleVersion = '0.0.0-test'
        $script:actor = New-RenderKitActorContext `
            -ActorId 'user-1' `
            -ActorType User `
            -DisplayName 'Test User' `
            -Source 'LocalBroker'
    }

    AfterEach {
        $env:RENDERKIT_HOME = $null
    }

    It 'returns engine info and facade metadata' {
        $result = Get-RenderKitEngineInfo -Actor $script:actor

        $result.success | Should -BeTrue
        $result.data.name | Should -Be 'RenderKit'
        $result.data.moduleVersion | Should -Not -BeNullOrEmpty
        $result.data.engineSchema.eventStore | Should -Be '1.1'
        $result.data.engineSchema.jobStore | Should -Be '1.1'
        @($result.data.facadeOperations | Where-Object { $_.Name -eq 'GetRenderKitProjectList' }).Count |
            Should -Be 1
    }

    It 'returns engine state health in a result envelope' {
        $result = Get-RenderKitEngineState -Actor $script:actor

        $result.success | Should -BeTrue
        $result.data.Status | Should -Be 'Healthy'
        $result.data.ComponentCount | Should -BeGreaterThan 0
    }

    It 'returns GUI-ready project summaries' {
        $root = Join-Path $TestDrive 'ClientA'
        New-Item -ItemType Directory -Path $root | Out-Null
        Set-RenderKitProjectRegistryEntry `
            -ProjectId 'project-1' `
            -ProjectName 'ClientA' `
            -ProjectRoot $root |
            Out-Null

        $result = Get-RenderKitEngineProjectList `
            -ProjectName 'ClientA' `
            -Exists $true `
            -Actor $script:actor

        $result.success | Should -BeTrue
        @($result.data).Count | Should -Be 1
        $result.data[0].id | Should -Be 'project-1'
        $result.data[0].exists | Should -BeTrue
    }

    It 'returns project detail with metadata when available' {
        $root = Join-Path $TestDrive 'ClientB'
        $metadata = New-RenderKitProjectMetadata `
            -ProjectName 'ClientB' `
            -TemplateName 'Default' `
            -TemplateSource 'Test'
        New-Item -ItemType Directory -Path $root | Out-Null
        Write-RenderKitProjectMetadata `
            -ProjectRoot $root `
            -Metadata $metadata
        Set-RenderKitProjectRegistryEntry `
            -ProjectId ([string]$metadata.project.id) `
            -ProjectName 'ClientB' `
            -ProjectRoot $root `
            -Metadata $metadata |
            Out-Null

        $result = Get-RenderKitEngineProjectDetail `
            -ProjectId ([string]$metadata.project.id) `
            -Actor $script:actor

        $result.success | Should -BeTrue
        $result.data.summary.name | Should -Be 'ClientB'
        $result.data.metadata.project.name | Should -Be 'ClientB'
        $result.data.metadataError | Should -Be $null
    }

    It 'returns not-found for missing project detail' {
        $result = Get-RenderKitEngineProjectDetail `
            -ProjectId 'missing-project' `
            -Actor $script:actor

        $result.success | Should -BeFalse
        $result.error.code | Should -Be 'RK_NOT_FOUND'
        $result.error.details.projectId | Should -Be 'missing-project'
    }
}