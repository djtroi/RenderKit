Describe 'Import target guard no-op behavior' {
    It 'does not mutate a regular existing directory' {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectImportTargetSecurityService.ps1')
        $root = Join-Path $TestDrive 'ProjectA'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $before = (Get-Item -LiteralPath $root).LastWriteTimeUtc
        Assert-RenderKitProjectImportTargetPathSafe -TargetRoot $root -Path $root | Out-Null
        Test-Path -LiteralPath $root -PathType Container | Should -BeTrue
    }
}
