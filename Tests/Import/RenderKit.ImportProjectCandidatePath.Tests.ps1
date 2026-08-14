Describe 'RenderKit import project discovery path handling' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (
            Split-Path -Parent $PSScriptRoot)
        Import-Module `
            (Join-Path $repositoryRoot 'RenderKit.psd1') `
            -Force
    }

    AfterAll {
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
    }

    It 'discovers project metadata through platform-native path segments' {
        $basePath = Join-Path $TestDrive 'projects'
        $projectRoot = Join-Path $basePath 'PortableProject'
        $metadataRoot = Join-Path $projectRoot '.renderkit'
        New-Item -ItemType Directory -Path $metadataRoot -Force | Out-Null

        [PSCustomObject]@{
            tool = 'RenderKit'
            project = [PSCustomObject]@{
                name = 'Portable Project'
                createdAt = '2026-08-14T00:00:00Z'
            }
            template = [PSCustomObject]@{
                name = 'default'
            }
        } |
            ConvertTo-Json -Depth 10 |
            Set-Content `
                -LiteralPath (Join-Path $metadataRoot 'project.json') `
                -Encoding UTF8

        $result = InModuleScope RenderKit -Parameters @{
            BasePath = $basePath
        } {
            [PSCustomObject]@{
                candidates = @(Get-RenderKitImportProjectCandidate -BasePath $BasePath)
                definition = (Get-Command Get-RenderKitImportProjectCandidate).Definition
            }
        }

        $result.candidates.Count | Should -Be 1
        $result.candidates[0].Name | Should -Be 'Portable Project'
        $result.candidates[0].ProjectRoot | Should -Be $projectRoot
        $result.definition | Should -Match "ChildPath '.renderkit'"
        $result.definition | Should -Match "ChildPath 'project.json'"
        $result.definition | Should -Not -Match '\.renderkit\\project\.json'
    }
}
