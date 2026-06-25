BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:RenderKitModuleRoot = $repositoryRoot

    function Register-RenderKitFunction {
        param([string]$Name)
    }
    function Write-RenderKitLog {
        param([string]$Level, [string]$Message)
    }
    function Initialize-RenderKitLogging {
        param([string]$ProjectRoot)
    }

    . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.StorageService.ps1')
    . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.PersistenceService.ps1')
    . (Join-Path $repositoryRoot 'src/Private/Versioning/RenderKit.ArtifactVersionService.ps1')
    . (Join-Path $repositoryRoot 'src/Private/Global/Get-RenderKitConfig.ps1')
    . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectRegistryService.ps1')
    . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectSearchIndexService.ps1')
    . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.DiscoveredProjectStoreService.ps1')
    . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectService.ps1')
    . (Join-Path $repositoryRoot 'src/Private/Template/RenderKit.TemplateService.ps1')
    . (Join-Path $repositoryRoot 'src/Public/New-Project.ps1')
}

Describe 'New-Project discovery integration' {
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

    It 'indexes absolute project paths and stores the discovered project' {
        $basePath = Join-Path $TestDrive 'AbsoluteProjects'
        New-Item -ItemType Directory -Path $basePath -Force | Out-Null

        New-Project -Name 'ClientA' -Path $basePath | Out-Null

        $projectRoot = Join-Path $basePath 'ClientA'
        $projectKey = ConvertTo-RenderKitProjectSearchIndexPathKey -Path $projectRoot
        $parentKey = ConvertTo-RenderKitProjectSearchIndexPathKey -Path $basePath
        $index = Read-RenderKitProjectSearchIndex
        $projectEntry = @($index.entries | Where-Object {
            [string]$_.path -eq $projectKey
        }) | Select-Object -First 1
        $parentEntry = @($index.entries | Where-Object {
            [string]$_.path -eq $parentKey
        }) | Select-Object -First 1

        $projectEntry.kind | Should -Be 'ProjectPath'
        [bool]$projectEntry.recursive | Should -BeFalse
        $projectEntry.priority | Should -Be 100
        $parentEntry.kind | Should -Be 'ProjectParentPath'
        [bool]$parentEntry.recursive | Should -BeTrue
        $parentEntry.priority | Should -Be 80

        $discovered = Read-RenderKitDiscoveredProjectStore
        @($discovered.projects).Count | Should -Be 1
        $discovered.projects[0].name | Should -Be 'ClientA'
        $discovered.projects[0].rootPath | Should -Be ([System.IO.Path]::GetFullPath($projectRoot))
        $discovered.projects[0].locationType | Should -Be 'CustomPath'
        $discovered.projects[0].validationStatus | Should -Be 'Valid'
        @($discovered.projects[0].sources) | Should -Contain 'NewProject'
    }
}