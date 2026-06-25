BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:RenderKitModuleRoot = $repositoryRoot

    function Register-RenderKitFunction {
        param([string]$Name)
    }
    function Write-RenderKitLog {
        param([string]$Level, [string]$Message)
    }

    . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.StorageService.ps1')
    . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.PersistenceService.ps1')
    . (Join-Path $repositoryRoot 'src/Private/Versioning/RenderKit.ArtifactVersionService.ps1')
    . (Join-Path $repositoryRoot 'src/Private/Global/Get-RenderKitConfig.ps1')
    . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectSearchIndexService.ps1')
    . (Join-Path $repositoryRoot 'src/Public/Set-ProjectRoot.ps1')
}

Describe 'Set-ProjectRoot search index integration' {
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

    It 'indexes the newly configured project root' {
        $root = Join-Path $TestDrive 'Projects'
        New-Item -ItemType Directory -Path $root -Force | Out-Null

        Set-ProjectRoot -Path $root | Out-Null

        $index = Read-RenderKitProjectSearchIndex
        @($index.entries).Count | Should -Be 1
        $entry = $index.entries[0]
        $entry.path | Should -Be (ConvertTo-RenderKitProjectSearchIndexPathKey -Path $root)
        $entry.kind | Should -Be 'CurrentProjectRoot'
        $entry.priority | Should -Be 100
        [bool]$entry.recursive | Should -BeTrue
        @($entry.sources) | Should -Contain 'SetProjectRoot'
    }

    It 'indexes the previous and new project roots when the root changes' {
        $oldRoot = Join-Path $TestDrive 'OldProjects'
        $newRoot = Join-Path $TestDrive 'NewProjects'
        New-Item -ItemType Directory -Path $oldRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $newRoot -Force | Out-Null

        Set-ProjectRoot -Path $oldRoot | Out-Null
        Set-ProjectRoot -Path $newRoot | Out-Null

        $index = Read-RenderKitProjectSearchIndex
        $oldEntry = @($index.entries | Where-Object {
            [string]$_.path -eq (ConvertTo-RenderKitProjectSearchIndexPathKey -Path $oldRoot)
        }) | Select-Object -First 1
        $newEntry = @($index.entries | Where-Object {
            [string]$_.path -eq (ConvertTo-RenderKitProjectSearchIndexPathKey -Path $newRoot)
        }) | Select-Object -First 1

        $oldEntry.kind | Should -Be 'PreviousProjectRoot'
        $oldEntry.priority | Should -Be 70
        $newEntry.kind | Should -Be 'CurrentProjectRoot'
        $newEntry.priority | Should -Be 100
        @($index.entries).Count | Should -Be 2
    }
}