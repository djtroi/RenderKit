$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:RenderKitModuleRoot = $repositoryRoot
. (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.StorageService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.PersistenceService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Versioning/RenderKit.ArtifactVersionService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Job/RenderKit.JobService.ps1')

Describe 'RenderKit job service' {
    BeforeEach {
        $env:RENDERKIT_HOME = Join-Path $TestDrive 'renderkit-home'
        $script:RenderKitArtifactVersionCatalog = $null
    }

    AfterEach {
        $env:RENDERKIT_HOME = $null
    }

    It 'creates an empty job store when none exists' {
        $store = Read-RenderKitJobStore
        $store.tool | Should -Be 'RenderKit'
        $store.schemaVersion | Should -Be '1.0'
        @($store.jobs).Count | Should -Be 0
    }

    It 'adds queued jobs' {
        $job = Add-RenderKitJob -Job (
            New-RenderKitJob `
                -JobType 'SendProjectDeliverable' `
                -Payload ([PSCustomObject]@{ projectId = 'project-1' })
        )

        $queued = @(Get-RenderKitQueuedJob)
        $queued.Count | Should -Be 1
        $queued[0].id | Should -Be $job.id
    }

    It 'filters queued jobs by type' {
        Add-RenderKitJob -Job (
            New-RenderKitJob -JobType 'SendProjectDeliverable'
        ) | Out-Null
        Add-RenderKitJob -Job (
            New-RenderKitJob -JobType 'RenderKitMaintenance'
        ) | Out-Null

        @(Get-RenderKitQueuedJob -JobType 'SendProjectDeliverable').Count |
            Should -Be 1
    }

    It 'starts the oldest queued job' {
        $job = Add-RenderKitJob -Job (
            New-RenderKitJob -JobType 'SendProjectDeliverable'
        )

        $running = Start-RenderKitQueuedJob
        $running.id | Should -Be $job.id
        $running.status | Should -Be 'Running'
        [int]$running.attempts | Should -Be 1
    }

    It 'marks jobs as failed with an error message' {
        $job = Add-RenderKitJob -Job (
            New-RenderKitJob -JobType 'SendProjectDeliverable'
        )

        Set-RenderKitJobStatus `
            -JobId $job.id `
            -Status Failed `
            -ErrorMessage 'Cloud upload failed.'

        $store = Read-RenderKitJobStore
        $storedJob = @($store.jobs | Where-Object { $_.id -eq $job.id })[0]
        $storedJob.status | Should -Be 'Failed'
        $storedJob.lastError | Should -Be 'Cloud upload failed.'
    }
}