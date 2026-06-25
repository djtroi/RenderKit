Describe 'Get-Project' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Import-Module (Join-Path $repositoryRoot 'RenderKit.psd1') -Force
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

    It 'exports the public discovered project list command' {
        Get-Command -Module RenderKit -Name Get-Project | Should -Not -BeNullOrEmpty
    }

    It 'returns table-friendly discovered project summaries' {
        $root = Join-Path $TestDrive 'KnownProject'
        New-Item -ItemType Directory -Path $root | Out-Null

        InModuleScope RenderKit -Parameters @{ Root = $root } {
            Set-RenderKitDiscoveredProjectEntry `
                -ProjectId 'known-project-1' `
                -ProjectName 'KnownProject' `
                -ProjectRoot $Root `
                -Version '2.5.0' `
                -Source 'Test' |
                Out-Null
        }

        $project = Get-Project | Select-Object -First 1

        $project.Name | Should -Be 'KnownProject'
        $project.Id | Should -Be 'known-project-1'
        $project.Available | Should -BeTrue
        $project.Version | Should -Be '2.5.0'
        $project.RootPath | Should -Be ([System.IO.Path]::GetFullPath($root))
        $project.MetadataPath | Should -Not -BeNullOrEmpty
        $project.Location | Should -Be 'CustomPath'
        $project.ValidationStatus | Should -Be 'Valid'
        $project.ConflictStatus | Should -Be 'None'
        $project.UpdatedAtUtc | Should -Not -BeNullOrEmpty
    }

    It 'can return only projects marked available in the overview' {
        $availableRoot = Join-Path $TestDrive 'AvailableProject'
        New-Item -ItemType Directory -Path $availableRoot | Out-Null
        $missingRoot = Join-Path $TestDrive 'MissingProject'

        InModuleScope RenderKit -Parameters @{
            AvailableRoot = $availableRoot
            MissingRoot = $missingRoot
        } {
            Set-RenderKitDiscoveredProjectEntry `
                -ProjectId 'available-project' `
                -ProjectName 'AvailableProject' `
                -ProjectRoot $AvailableRoot |
                Out-Null
            Set-RenderKitDiscoveredProjectEntry `
                -ProjectId 'missing-project' `
                -ProjectName 'MissingProject' `
                -ProjectRoot $MissingRoot |
                Out-Null
        }

        $projects = @(Get-Project -AvailableOnly)

        $projects.Name | Should -Contain 'AvailableProject'
        $projects.Name | Should -Not -Contain 'MissingProject'
    }

    It 'refreshes the discovered project overview from the search index' {
        $scanRoot = Join-Path $TestDrive 'ScanRoot'
        $projectRoot = Join-Path $scanRoot 'DiscoveredByRefresh'

        InModuleScope RenderKit -Parameters @{
            ScanRoot = $scanRoot
            ProjectRoot = $projectRoot
        } {
            New-Item -ItemType Directory `
                -Path (Join-Path $ProjectRoot '.renderkit') `
                -Force |
                Out-Null
            Write-RenderKitJsonFileAtomic `
                -Path (Get-RenderKitProjectMetadataPath -ProjectRoot $ProjectRoot) `
                -Depth 6 `
                -Value ([PSCustomObject]@{
                    tool = 'RenderKit'
                    schemaVersion = '1.0'
                    project = [PSCustomObject]@{
                        id = 'refresh-project'
                        name = 'DiscoveredByRefresh'
                    }
                }) |
                Out-Null
            Set-RenderKitProjectSearchIndexEntry `
                -Path $ScanRoot `
                -Kind 'ProjectParentPath' `
                -Source 'Test' |
                Out-Null
        }

        $project = Get-Project -Refresh | Select-Object -First 1

        $project.Name | Should -Be 'DiscoveredByRefresh'
        $project.Id | Should -Be 'refresh-project'
        $project.Available | Should -BeTrue
    }
}