Describe 'RenderKit project export source security' {
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

    It 'accepts a regular archive source file' {
        $path = Join-Path $TestDrive 'regular.txt'
        Set-Content -LiteralPath $path -Value 'regular' -Encoding UTF8

        $result = InModuleScope RenderKit -Parameters @{ Path = $path } {
            Get-RenderKitProjectExportArchiveSourceFile -SourcePath $Path
        }

        $result.FullName | Should -Be (Get-Item -LiteralPath $path).FullName
    }

    It 'rejects a symbolic-link archive source before file contents are read' {
        $outside = Join-Path $TestDrive 'outside-secret.txt'
        $link = Join-Path $TestDrive 'linked-project-file.txt'
        Set-Content -LiteralPath $outside -Value 'must-not-be-exported' -Encoding UTF8

        $created = $true
        try {
            New-Item `
                -ItemType SymbolicLink `
                -Path $link `
                -Target $outside `
                -ErrorAction Stop |
                Out-Null
        }
        catch {
            $created = $false
        }

        if (-not $created) {
            Set-ItResult -Skipped -Because 'Symbolic link creation is not available on this runner.'
            return
        }

        {
            InModuleScope RenderKit -Parameters @{ Path = $link } {
                Get-RenderKitProjectExportArchiveSourceFile -SourcePath $Path
            }
        } | Should -Throw '*symbolic link or reparse point*'
    }

    It 'loads the security override after the base export implementation' {
        $definition = InModuleScope RenderKit {
            (Get-Command Add-RenderKitFileToZipArchive).Definition
        }

        $definition | Should -Match 'Get-RenderKitProjectExportArchiveSourceFile'
        $definition | Should -Match 'CreateEntryFromFile'
    }
}
