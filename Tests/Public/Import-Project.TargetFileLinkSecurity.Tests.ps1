BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectImportTargetSecurityService.ps1')
}

Describe 'Import target file-link security' {
    It 'rejects an existing symbolic-link file before overwrite' {
        $root = Join-Path $TestDrive 'ProjectA'
        $outside = Join-Path $TestDrive 'outside-file.txt'
        $link = Join-Path $root 'clip.mov'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        Set-Content -LiteralPath $outside -Value 'protected'

        try {
            New-Item -ItemType SymbolicLink -Path $link -Target $outside -ErrorAction Stop | Out-Null
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

        (Get-Content -LiteralPath $outside -Raw).Trim() | Should -Be 'protected'
    }
}
