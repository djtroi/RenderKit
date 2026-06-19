Describe 'RenderKit repair service' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:RenderKitModuleRoot = $repositoryRoot
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.StorageService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.PersistenceService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Versioning/RenderKit.ArtifactVersionService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectRegistryService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Event/RenderKit.EventService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Job/RenderKit.JobService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Maintenance/RenderKit.RepairService.ps1')
    }

    BeforeEach {
        $env:RENDERKIT_HOME = Join-Path $TestDrive 'renderkit-home'
        if (Test-Path -LiteralPath $env:RENDERKIT_HOME) {
            Remove-Item -LiteralPath $env:RENDERKIT_HOME -Recurse -Force
        }
        $script:RenderKitArtifactVersionCatalog = $null
    }

    AfterEach {
        $env:RENDERKIT_HOME = $null
    }

    It 'checks core storage and state stores' {
        $result = Invoke-RenderKitStateRepair

        $result.Status | Should -Be 'Healthy'
        $result.ComponentCount | Should -BeGreaterThan 0
        @($result.Components | Where-Object { $_.Name -eq 'EventStore' }).Count |
            Should -Be 1
        @($result.Components | Where-Object { $_.Name -eq 'JobStore' }).Count |
            Should -Be 1
    }

    It 'marks stale project registry entries during repair' {
        $root = Join-Path $TestDrive 'StaleProject'
        New-Item -ItemType Directory -Path $root | Out-Null
        Set-RenderKitProjectRegistryEntry `
            -ProjectId 'project-1' `
            -ProjectName 'StaleProject' `
            -ProjectRoot $root |
            Out-Null
        Remove-Item -LiteralPath $root -Recurse -Force

        Invoke-RenderKitStateRepair | Out-Null

        $registry = Read-RenderKitProjectRegistry
        [bool]$registry.projects[0].exists | Should -BeFalse
    }

    It 'reports failed corrupted stores without restore mode' {
        $jobPath = Get-RenderKitJobStorePath
        New-Item -ItemType Directory -Path (Split-Path $jobPath -Parent) `
            -Force |
            Out-Null
        Set-Content -LiteralPath $jobPath -Value '{ invalid json' -NoNewline

        $result = Invoke-RenderKitStateRepair

        $result.Status | Should -Be 'Failed'
        @($result.Components |
            Where-Object { $_.Name -eq 'JobStore' -and $_.Status -eq 'Failed' }).Count |
            Should -Be 1
    }
}