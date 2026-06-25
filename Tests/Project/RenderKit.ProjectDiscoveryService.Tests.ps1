Describe 'RenderKit project discovery service' {
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
        . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectDiscoveryService.ps1')

        function script:New-TestRenderKitProjectFolder {
            param(
                [Parameter(Mandatory)]
                [string]$ProjectRoot,
                [Parameter(Mandatory)]
                [string]$ProjectId,
                [Parameter(Mandatory)]
                [string]$ProjectName
            )

            New-Item -ItemType Directory `
                -Path (Join-Path $ProjectRoot '.renderkit') `
                -Force |
                Out-Null
            Write-RenderKitJsonFileAtomic `
                -Path (Get-RenderKitProjectMetadataPath -ProjectRoot $ProjectRoot) `
                -Depth 6 `
                -Value ([PSCustomObject]@{
                    tool = 'RenderKit'
                    schemaVersion = '1.0'
                    project = [PSCustomObject]@{
                        id = $ProjectId
                        name = $ProjectName
                    }
                }) |
                Out-Null
        }
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
    It 'discovers valid projects from indexed roots' {
        $scanRoot = Join-Path $TestDrive 'ScanRoot'
        $projectRoot = Join-Path $scanRoot 'ClientA'
        New-TestRenderKitProjectFolder `
            -ProjectRoot $projectRoot `
            -ProjectId 'project-1' `
            -ProjectName 'ClientA'
        Set-RenderKitProjectSearchIndexEntry `
            -Path $scanRoot `
            -Kind 'ProjectParentPath' `
            -Source 'Test' `
            -Priority 80 `
            -Recursive $true |
            Out-Null

        $summary = Invoke-RenderKitProjectDiscovery

        $summary.projectsDiscovered | Should -Be 1
        $store = Read-RenderKitDiscoveredProjectStore
        @($store.projects).Count | Should -Be 1
        $store.projects[0].id | Should -Be 'project-1'
        $store.projects[0].name | Should -Be 'ClientA'
        $store.projects[0].conflictStatus | Should -Be 'None'
        @($store.projects[0].sources) | Should -Contain 'Discovery'
    }

    It 'marks missing indexed roots as diagnostics' {
        $missingRoot = Join-Path $TestDrive 'MissingRoot'
        Set-RenderKitProjectSearchIndexEntry `
            -Path $missingRoot `
            -Kind 'ProjectParentPath' `
            -Source 'Test' |
            Out-Null

        $summary = Invoke-RenderKitProjectDiscovery

        $summary.rootsMissing | Should -Be 1
        $index = Read-RenderKitProjectSearchIndex
        $entry = @($index.entries) | Select-Object -First 1
        $entry.lastScanStatus | Should -Be 'Missing'
        $entry.lastError | Should -Be 'Path does not exist.'
    }

    It 'marks duplicate project ids as conflicts' {
        $scanRoot = Join-Path $TestDrive 'Duplicates'
        New-TestRenderKitProjectFolder `
            -ProjectRoot (Join-Path $scanRoot 'CopyA') `
            -ProjectId 'duplicate-id' `
            -ProjectName 'CopyA'
        New-TestRenderKitProjectFolder `
            -ProjectRoot (Join-Path $scanRoot 'CopyB') `
            -ProjectId 'duplicate-id' `
            -ProjectName 'CopyB'
        Set-RenderKitProjectSearchIndexEntry `
            -Path $scanRoot `
            -Kind 'ProjectParentPath' `
            -Source 'Test' |
            Out-Null

        $summary = Invoke-RenderKitProjectDiscovery

        $summary.duplicateProjectIds | Should -Be 1
        $store = Read-RenderKitDiscoveredProjectStore
        @($store.projects).Count | Should -Be 2
        @($store.projects | Where-Object {
            [string]$_.conflictStatus -eq 'DuplicateProjectId'
        }).Count | Should -Be 2
    }
}