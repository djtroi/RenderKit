Describe 'RenderKit client commands' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $manifestPath = Join-Path $repositoryRoot 'RenderKit.psd1'
        Import-Module $manifestPath -Force
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

    It 'exports create, read, and optimistic update commands' {
        Get-Command -Module RenderKit -Name Get-RenderKitClient |
            Should -Not -BeNullOrEmpty
        Get-Command -Module RenderKit -Name New-RenderKitClient |
            Should -Not -BeNullOrEmpty
        Get-Command -Module RenderKit -Name Set-RenderKitClient |
            Should -Not -BeNullOrEmpty

        $created = New-RenderKitClient `
            -DisplayName 'Studio Client' `
            -Tag @('studio') `
            -Confirm:$false
        $listed = @(Get-RenderKitClient -Tag studio)
        $updated = Set-RenderKitClient `
            -Id $created.id `
            -ExpectedRevision $created.revision `
            -Status Archived `
            -Confirm:$false

        $listed.Count | Should -Be 1
        $listed[0].id | Should -Be $created.id
        $updated.status | Should -Be 'Archived'
        $updated.revision | Should -Be 2
    }
}
