Describe 'RenderKit backup cleanup reparse boundary' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $repositoryRoot 'RenderKit.psd1') -Force
    }

    AfterAll {
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
    }

    It 'does not traverse a linked directory while removing project artifacts' {
        $project = Join-Path $TestDrive 'project'
        $outside = Join-Path $TestDrive 'outside'
        $link = Join-Path $project 'linked-outside'
        [void][System.IO.Directory]::CreateDirectory($project)
        [void][System.IO.Directory]::CreateDirectory($outside)
        $insideFile = Join-Path $project 'inside.tmp'
        $outsideFile = Join-Path $outside 'outside.tmp'
        [System.IO.File]::WriteAllText($insideFile, 'inside')
        [System.IO.File]::WriteAllText($outsideFile, 'outside')

        try {
            New-Item `
                -ItemType SymbolicLink `
                -Path $link `
                -Target $outside `
                -ErrorAction Stop |
                Out-Null
        }
        catch {
            Set-ItResult -Skipped -Because "Directory links are unavailable on this runner: $($_.Exception.Message)"
            return
        }

        $result = InModuleScope RenderKit -Parameters @{
            Project = $project
        } {
            Remove-ProjectArtifact `
                -ProjectPath $Project `
                -rules @{ Extensions = @('.tmp'); Folders = @() }
        }

        $result.RemovedFileCount | Should -Be 1
        Test-Path -LiteralPath $insideFile | Should -BeFalse
        Test-Path -LiteralPath $outsideFile | Should -BeTrue
        Test-Path -LiteralPath $link | Should -BeTrue
    }

    It 'excludes reparse directories from the cleanup catalog' {
        $project = Join-Path $TestDrive 'catalog-project'
        $outside = Join-Path $TestDrive 'catalog-outside'
        $link = Join-Path $project 'catalog-link'
        [void][System.IO.Directory]::CreateDirectory($project)
        [void][System.IO.Directory]::CreateDirectory($outside)
        [System.IO.File]::WriteAllText(
            (Join-Path $outside 'external.bin'),
            'external'
        )

        try {
            New-Item `
                -ItemType SymbolicLink `
                -Path $link `
                -Target $outside `
                -ErrorAction Stop |
                Out-Null
        }
        catch {
            Set-ItResult -Skipped -Because "Directory links are unavailable on this runner: $($_.Exception.Message)"
            return
        }

        $catalog = InModuleScope RenderKit -Parameters @{
            Project = $project
        } {
            Get-RenderKitBackupCleanupCatalog -ProjectPath $Project
        }

        @($catalog.Directories | Where-Object FullName -eq $link) |
            Should -HaveCount 0
        @($catalog.Files | Where-Object Name -eq 'external.bin') |
            Should -HaveCount 0
    }
}
