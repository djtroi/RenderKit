BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectImportTargetSecurityService.ps1')
}

Describe 'Import target canonical boundary security' {
    It 'rejects a path that resolves outside the project root' {
        $root = Join-Path $TestDrive 'ProjectA'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $outside = Join-Path $root '../outside.txt'

        {
            Assert-RenderKitProjectImportTargetPathSafe `
                -TargetRoot $root `
                -Path $outside
        } | Should -Throw '*resolves outside project root*'
    }
}
