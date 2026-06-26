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
    . (Join-Path $repositoryRoot 'src/Private/Template/RenderKit.TemplateService.ps1')
    . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectService.ps1')
    . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectExportService.ps1')
    . (Join-Path $repositoryRoot 'src/Public/Export-Project.ps1')
}

Describe 'Export-Project' {
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

    It 'exports to a default manifest file inside an existing destination directory' {
        $projectRoot = Join-Path $TestDrive 'ProjectA'
        $destinationRoot = Join-Path $TestDrive 'Exports'
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $projectRoot 'asset.txt') -Value 'test asset'

        $result = Export-Project `
            -ProjectRoot $projectRoot `
            -DestinationPath $destinationRoot

        $expectedPath = Join-Path $destinationRoot 'ProjectA.rkit'
        $result.Path | Should -Be ([System.IO.Path]::GetFullPath($expectedPath))
        Test-Path -LiteralPath $expectedPath -PathType Leaf | Should -BeTrue
    }
}