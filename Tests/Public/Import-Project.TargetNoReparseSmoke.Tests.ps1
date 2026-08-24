Describe 'Import target guard smoke' {
    It 'keeps regular paths usable' {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectImportTargetSecurityService.ps1')
        $root = Join-Path $TestDrive 'RegularProject'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        {
            Assert-RenderKitProjectImportTargetPathSafe -TargetRoot $root -Path $root
        } | Should -Not -Throw
    }
}
