$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:RenderKitModuleRoot = $repositoryRoot
. (Join-Path $repositoryRoot 'src/Private/Versioning/RenderKit.ArtifactVersionService.ps1')

Describe 'RenderKit artifact version service' {
    BeforeEach {
        $script:RenderKitArtifactVersionCatalog = $null
        $script:RenderKitArtifactMigrations = @{}
    }

    It 'loads the central version policy' {
        $policy = Get-RenderKitArtifactVersionPolicy -ArtifactType Template
        $policy.Current | Should -Be '1.1'
        $policy.MinimumReadable | Should -Be '1.0'
    }

    It 'treats artifact type names case-insensitively' {
        (Get-RenderKitArtifactVersionPolicy -ArtifactType mapping).ArtifactType |
            Should -Be 'Mapping'
    }

    It 'reports current, upgradeable, old, and future versions explicitly' {
        (Test-RenderKitArtifactCompatibility Template '1.1').Status |
            Should -Be 'Current'
        (Test-RenderKitArtifactCompatibility Template '1.0').Status |
            Should -Be 'UpgradeAvailable'
        (Test-RenderKitArtifactCompatibility Template '0.9').Status |
            Should -Be 'UpgradeRequired'
        (Test-RenderKitArtifactCompatibility Template '2.0').Status |
            Should -Be 'UnsupportedFutureVersion'
    }

    It 'rejects malformed and unknown version requests' {
        { Test-RenderKitArtifactCompatibility Template 'latest' } |
            Should -Throw
        { Get-RenderKitArtifactVersionPolicy -ArtifactType Unknown } |
            Should -Throw
    }

    It 'finds the shortest registered forward migration path' {
        Register-RenderKitArtifactMigration Template 1.0 1.1 { param($value) $value }
        Register-RenderKitArtifactMigration Template 1.1 2.0 { param($value) $value }
        Register-RenderKitArtifactMigration Template 1.0 2.0 { param($value) $value }

        $path = @(Get-RenderKitArtifactMigrationPath Template 1.0 2.0)
        $path.Count | Should -Be 1
        $path[0].FromVersion | Should -Be '1.0'
        $path[0].ToVersion | Should -Be '2.0'
    }

    It 'returns no path when no migration chain is registered' {
        @(Get-RenderKitArtifactMigrationPath Mapping 1.0 1.1).Count |
            Should -Be 0
    }

    It 'rejects backward migration registrations' {
        { Register-RenderKitArtifactMigration Mapping 1.1 1.0 { } } |
            Should -Throw
    }
}