Describe 'RenderKit project lifecycle service' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:RenderKitModuleRoot = $repositoryRoot
        $script:RenderKitModuleVersion = '0.0.0'
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.StorageService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.PersistenceService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Versioning/RenderKit.ArtifactVersionService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectLifecycleService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectRegistryService.ps1')
    }

    BeforeEach {
        $env:RENDERKIT_HOME = Join-Path $TestDrive 'renderkit-home'
        if (Test-Path -LiteralPath $env:RENDERKIT_HOME) {
            Remove-Item -LiteralPath $env:RENDERKIT_HOME -Recurse -Force
        }
    }

    AfterEach {
        $env:RENDERKIT_HOME = $null
    }

    It 'creates new project metadata in Draft status' {
        $metadata = New-RenderKitProjectMetadata `
            -ProjectName 'ClientA' `
            -TemplateName 'default' `
            -TemplateSource 'system'

        Get-RenderKitProjectStatus -Metadata $metadata | Should -Be 'Draft'
    }

    It 'allows Draft to Active and records history' {
        $metadata = New-RenderKitProjectMetadata `
            -ProjectName 'ClientB' `
            -TemplateName 'default' `
            -TemplateSource 'system'

        $metadata = Set-RenderKitProjectMetadataStatus `
            -Metadata $metadata `
            -Status 'Active' `
            -Reason 'Media imported' `
            -Source 'Test'

        Get-RenderKitProjectStatus -Metadata $metadata | Should -Be 'Active'
        @($metadata.lifecycle.history).Count | Should -Be 1
    }

    It 'treats same-status transitions as no-op' {
        $metadata = New-RenderKitProjectMetadata `
            -ProjectName 'ClientC' `
            -TemplateName 'default' `
            -TemplateSource 'system'

        $metadata = Set-RenderKitProjectMetadataStatus `
            -Metadata $metadata `
            -Status 'Draft'

        @($metadata.lifecycle.history).Count | Should -Be 0
    }

    It 'blocks terminal cancelled projects from becoming active' {
        $metadata = [PSCustomObject]@{
            tool = 'RenderKit'
            project = @{ id = 'project-1'; name = 'ClientD' }
            lifecycle = @{
                status = 'Cancelled'
                history = @()
            }
        }

        { Set-RenderKitProjectMetadataStatus -Metadata $metadata -Status 'Active' } |
            Should -Throw
    }

    It 'blocks archived projects from becoming active' {
        $metadata = [PSCustomObject]@{
            tool = 'RenderKit'
            project = @{ id = 'project-2'; name = 'ClientE' }
            lifecycle = @{
                status = 'Archived'
                history = @()
            }
        }

        { Set-RenderKitProjectMetadataStatus -Metadata $metadata -Status 'Active' } |
            Should -Throw
    }

    It 'allows delivered projects to move down to active' {
        $result = Test-RenderKitProjectStatusTransition `
            -FromStatus 'Delivered' `
            -ToStatus 'Active'

        $result.Allowed | Should -BeTrue
    }
}