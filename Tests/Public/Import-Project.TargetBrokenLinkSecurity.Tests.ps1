BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectImportTargetSecurityService.ps1')
}

Describe 'Import target broken-link security' {
    It 'rejects a broken symbolic-link leaf before a file create can follow it' {
        $root = Join-Path $TestDrive 'ProjectA'
        $missingOutside = Join-Path $TestDrive 'missing-outside/created-by-follow.txt'
        $link = Join-Path $root 'clip.mov'
        New-Item -ItemType Directory -Path $root -Force | Out-Null

        try {
            New-Item -ItemType SymbolicLink -Path $link -Target $missingOutside -ErrorAction Stop | Out-Null
        }
        catch {
            Set-ItResult -Skipped -Because 'Symbolic link creation is not available on this runner.'
            return
        }

        {
            Assert-RenderKitProjectImportTargetPathSafe `
                -TargetRoot $root `
                -Path $link
        } | Should -Throw '*symbolic link or reparse point*'

        Test-Path -LiteralPath $missingOutside -PathType Leaf | Should -BeFalse
    }
}
