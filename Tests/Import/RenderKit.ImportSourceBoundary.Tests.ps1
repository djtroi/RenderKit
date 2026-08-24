Describe 'RenderKit import source boundary' {
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

    It 'catalogs normal source files' {
        $source = Join-Path $TestDrive 'source-normal'
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'clip.txt') -Value 'media' -Encoding UTF8

        $catalog = InModuleScope RenderKit -Parameters @{ Source = $source } {
            @(Get-RenderKitImportFileCatalog -SourcePath $Source)
        }

        $catalog.Count | Should -Be 1
        $catalog[0].Name | Should -Be 'clip.txt'
        $catalog[0].RelativePath | Should -Be 'clip.txt'
    }

    It 'does not traverse a symbolic-link directory outside the source root' {
        $source = Join-Path $TestDrive 'source-directory-link'
        $outside = Join-Path $TestDrive 'outside-directory'
        $link = Join-Path $source 'linked'
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $outside 'secret.txt') -Value 'secret' -Encoding UTF8

        try {
            New-Item -ItemType SymbolicLink -Path $link -Target $outside -ErrorAction Stop | Out-Null
        }
        catch {
            Set-ItResult -Skipped -Because 'Symbolic link creation is not available on this runner.'
            return
        }

        $catalog = InModuleScope RenderKit -Parameters @{ Source = $source } {
            @(Get-RenderKitImportFileCatalog -SourcePath $Source)
        }
        $names = @($catalog | ForEach-Object { $_.Name })

        $names | Should -Not -Contain 'secret.txt'
    }

    It 'does not catalog a symbolic-link file outside the source root' {
        $source = Join-Path $TestDrive 'source-file-link'
        $outside = Join-Path $TestDrive 'outside-file.txt'
        $link = Join-Path $source 'linked.txt'
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        Set-Content -LiteralPath $outside -Value 'secret' -Encoding UTF8

        try {
            New-Item -ItemType SymbolicLink -Path $link -Target $outside -ErrorAction Stop | Out-Null
        }
        catch {
            Set-ItResult -Skipped -Because 'Symbolic link creation is not available on this runner.'
            return
        }

        $catalog = InModuleScope RenderKit -Parameters @{ Source = $source } {
            @(Get-RenderKitImportFileCatalog -SourcePath $Source)
        }
        $names = @($catalog | ForEach-Object { $_.Name })

        $names | Should -Not -Contain 'linked.txt'
    }

    It 'loads the hardened catalog implementation after the base import service' {
        $definition = InModuleScope RenderKit {
            (Get-Command Get-RenderKitImportFileCatalog).Definition
        }

        $definition | Should -Match 'FileAttributes.*ReparsePoint'
        $definition | Should -Match 'TrimStart'
    }
}
