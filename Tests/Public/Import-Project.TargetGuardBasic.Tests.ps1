Describe 'Import target guard basic path' {
    It 'returns the canonical safe path' {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectImportTargetSecurityService.ps1')
        $root = Join-Path $TestDrive 'ProjectA'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $result = Assert-RenderKitProjectImportTargetPathSafe -TargetRoot $root -Path $root
        $result | Should -Be ([System.IO.Path]::GetFullPath($root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar))
    }
}
