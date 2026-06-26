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
    . (Join-Path $repositoryRoot 'src/Public/Add-FolderToTemplate.ps1')
}

Describe 'Add-FolderToTemplate' {
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

    It 'ignores leading path separators when adding nested folders' {
        $templatePath = Get-RenderKitUserTemplatePath -TemplateName 'omid'
        Write-RenderKitTemplateFile `
            -Path $templatePath `
            -Template ([PSCustomObject]@{
                Version = '1.1'
                Name = 'omid'
                Mappings = @()
                Deliverables = @()
                Folders = @()
            })

        Add-FolderToTemplate -TemplateName 'omid' -FolderPath '\test1\test2\test3'

        $template = Read-RenderKitTemplateFile -Path $templatePath
        @($template.Folders).Count | Should -Be 1
        $template.Folders[0].Name | Should -Be 'test1'
        $template.Folders[0].SubFolders[0].Name | Should -Be 'test2'
        $template.Folders[0].SubFolders[0].SubFolders[0].Name | Should -Be 'test3'
    }
}