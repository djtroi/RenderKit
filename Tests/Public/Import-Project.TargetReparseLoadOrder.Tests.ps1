Describe 'Import target security helper load order' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Import-Module (Join-Path $repositoryRoot 'RenderKit.psd1') -Force
    }

    AfterAll {
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
    }

    It 'loads the target guard used by Import-Project' {
        $definition = InModuleScope RenderKit {
            (Get-Command Import-Project).Definition
        }

        $definition | Should -Match 'Assert-RenderKitProjectImportTargetPathSafe'
        $definition | Should -Match 'New-RenderKitProjectImportDirectorySafe'
    }
}
