Describe 'Import target boundary guard surface' {
    It 'exposes the private guard inside the module' {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Import-Module (Join-Path $repositoryRoot 'RenderKit.psd1') -Force
        try {
            InModuleScope RenderKit {
                Get-Command Assert-RenderKitProjectImportTargetPathSafe -ErrorAction Stop | Should -Not -BeNullOrEmpty
            }
        }
        finally {
            Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
        }
    }
}
