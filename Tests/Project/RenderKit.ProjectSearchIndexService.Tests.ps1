Describe 'RenderKit project search index service' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:RenderKitModuleRoot = $repositoryRoot
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.StorageService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.PersistenceService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Versioning/RenderKit.ArtifactVersionService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectSearchIndexService.ps1')
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

    It 'creates an empty index when no index exists' {
        $index = Read-RenderKitProjectSearchIndex
        $index.tool | Should -Be 'RenderKit'
        $index.schemaVersion | Should -Be '1.0'
        @($index.entries).Count | Should -Be 0
    }

    It 'upserts paths and keeps unique sources' {
        $root = Join-Path $TestDrive 'Projects'

        Set-RenderKitProjectSearchIndexEntry `
            -Path $root `
            -Kind 'CurrentProjectRoot' `
            -Source 'SetProjectRoot' `
            -Priority 100 |
            Out-Null
        Set-RenderKitProjectSearchIndexEntry `
            -Path $root `
            -Kind 'CurrentProjectRoot' `
            -Source 'GetProjectRefresh' `
            -Priority 50 |
            Out-Null

        $index = Read-RenderKitProjectSearchIndex
        @($index.entries).Count | Should -Be 1
        $index.entries[0].path | Should -Be (ConvertTo-RenderKitProjectSearchIndexPathKey -Path $root)
        $index.entries[0].priority | Should -Be 100
        @($index.entries[0].sources) | Should -Contain 'SetProjectRoot'
        @($index.entries[0].sources) | Should -Contain 'GetProjectRefresh'
    }

    It 'stores scan diagnostics for an indexed path' {
        $root = Join-Path $TestDrive 'ClientA'
        Set-RenderKitProjectSearchIndexEntry `
            -Path $root `
            -Kind 'ProjectParentPath' `
            -Source 'NewProject' |
            Out-Null

        $entry = Set-RenderKitProjectSearchIndexScanResult `
            -Path $root `
            -Status 'Succeeded' `
            -HitCountIncrement 2

        $entry.lastScanStatus | Should -Be 'Succeeded'
        $entry.lastScannedAtUtc | Should -Not -BeNullOrEmpty
        $entry.hitCount | Should -Be 2
    }

    It 'creates a diagnostic entry for missing scan result paths' {
        $root = Join-Path $TestDrive 'Missing'

        $entry = Set-RenderKitProjectSearchIndexScanResult `
            -Path $root `
            -Status 'Missing' `
            -ErrorMessage 'Path does not exist.'

        $entry.path | Should -Be (ConvertTo-RenderKitProjectSearchIndexPathKey -Path $root)
        $entry.lastScanStatus | Should -Be 'Missing'
        $entry.lastError | Should -Be 'Path does not exist.'
    }
}