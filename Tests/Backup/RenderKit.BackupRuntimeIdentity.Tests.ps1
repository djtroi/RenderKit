Describe 'RenderKit backup runtime identity' {
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

    It 'uses portable runtime identity in backup manifests' {
        $manifest = InModuleScope RenderKit {
            New-BackupManifest `
                -Project ([PSCustomObject]@{
                    id = 'identity-project'
                    Name = 'Identity Project'
                    RootPath = $TestDrive
                }) `
                -Options @{
                    profiles = @()
                    keepSourceProject = $true
                } `
                -Statistics @{} `
                -Archive @{} `
                -CleanupSummary @() `
                -Job ([PSCustomObject]@{}) `
                -Profile ([PSCustomObject]@{}) `
                -Pipeline ([PSCustomObject]@{}) `
                -StorageTiers @() `
                -Safety ([PSCustomObject]@{})
        }

        $manifest.backup.createdBy | Should -Be ([System.Environment]::UserName)
        $manifest.backup.machine | Should -Be ([System.Environment]::MachineName)
    }
}
