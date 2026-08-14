Describe 'RenderKit backup runtime identity' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (
            Split-Path -Parent $PSScriptRoot)
        Import-Module `
            (Join-Path $repositoryRoot 'RenderKit.psd1') `
            -Force
    }

    BeforeEach {
        $env:RENDERKIT_HOME = Join-Path $TestDrive 'renderkit-home'
        if (Test-Path -LiteralPath $env:RENDERKIT_HOME) {
            Remove-Item -LiteralPath $env:RENDERKIT_HOME -Recurse -Force
        }
    }

    AfterEach {
        $env:RENDERKIT_HOME = $null
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

    It 'normalizes missing background job audit identity at the job boundary' {
        $job = InModuleScope RenderKit {
            New-BackupProjectJob `
                -Payload ([PSCustomObject]@{
                    schemaVersion = '1.0'
                }) `
                -RequestedBy ([PSCustomObject]@{
                    user = $null
                    machine = $null
                })
        }

        $job.requestedBy.user | Should -Be ([System.Environment]::UserName)
        $job.requestedBy.machine | Should -Be ([System.Environment]::MachineName)
    }
}
