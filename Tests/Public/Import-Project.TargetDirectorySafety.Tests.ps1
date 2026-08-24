BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectImportTargetSecurityService.ps1')
}

Describe 'Safe import directory creation' {
    It 'creates a normal directory below the target root' {
        $root = Join-Path $TestDrive 'ProjectA'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $nested = Join-Path $root 'media/subfolder'

        $result = New-RenderKitProjectImportDirectorySafe `
            -TargetRoot $root `
            -Path $nested

        Test-Path -LiteralPath $result -PathType Container | Should -BeTrue
    }
}
