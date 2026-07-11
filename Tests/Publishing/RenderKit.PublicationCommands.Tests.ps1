Describe 'RenderKit publication commands' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:manifestPath = Join-Path $repositoryRoot 'RenderKit.psd1'
    }

    BeforeEach {
        $env:RENDERKIT_HOME = Join-Path $TestDrive 'renderkit-home'
        if (Test-Path -LiteralPath $env:RENDERKIT_HOME) {
            Remove-Item -LiteralPath $env:RENDERKIT_HOME -Recurse -Force
        }
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
        Import-Module $script:manifestPath -Force
    }

    AfterEach {
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
        $env:RENDERKIT_HOME = $null
    }

    It 'exports create, range read, and optimistic update commands' {
        foreach ($name in @(
            'Get-RenderKitPublication',
            'New-RenderKitPublication',
            'Set-RenderKitPublication'
        )) {
            Get-Command $name -Module RenderKit |
                Should -Not -BeNullOrEmpty
        }

        $created = New-RenderKitPublication `
            -Title 'Studio release' `
            -Status Scheduled `
            -StartUtc '2026-07-10T08:00:00Z' `
            -TimeZone UTC `
            -Confirm:$false
        $range = @(Get-RenderKitPublication `
            -FromUtc '2026-07-01T00:00:00Z' `
            -ToUtc '2026-08-01T00:00:00Z')
        $updated = Set-RenderKitPublication `
            -Id $created.id `
            -ExpectedRevision $created.revision `
            -Description 'Release plan' `
            -Confirm:$false

        $range.Count | Should -Be 1
        $range[0].id | Should -Be $created.id
        $updated.description | Should -Be 'Release plan'
        $updated.revision | Should -Be 2
    }
}
