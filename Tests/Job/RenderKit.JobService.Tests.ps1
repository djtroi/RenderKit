Describe 'RenderKit job service' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:RenderKitModuleRoot = $repositoryRoot
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.StorageService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.PersistenceService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Versioning/RenderKit.ArtifactVersionService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Job/RenderKit.JobService.ps1')
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

    It 'creates an empty job store when none exists' {
        $store = Read-RenderKitJobStore
        $store.tool | Should -Be 'RenderKit'
        $store.schemaVersion | Should -Be '1.1'
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
        $queued[0].jobSchemaVersion | Should -Be '1.1'
        $queued[0].payloadSchemaVersion | Should -Be '1.0'
        $queued[0].queueName | Should -Be 'default'
        $queued[0].progress.phase | Should -Be 'Queued'
    }

    It 'defines supported job statuses and transitions' {
        $statuses = @((Get-RenderKitJobStatusCatalog).Name)

        $statuses | Should -Contain 'Queued'
        $statuses | Should -Contain 'RetryScheduled'
        Test-RenderKitJobStatusTransition -FromStatus Queued -ToStatus Running |
            Should -BeTrue
        Test-RenderKitJobStatusTransition -FromStatus Succeeded -ToStatus Running |
            Should -BeFalse
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

    It 'filters job lists by queue and correlation id' {
        $correlationId = [guid]::NewGuid().ToString()
        Add-RenderKitJob -Job (
            New-RenderKitJob `
                -JobType 'SendProjectDeliverable' `
                -QueueName 'deliveries' `
                -Priority 5 `
                -CorrelationId $correlationId
        ) | Out-Null
        Add-RenderKitJob -Job (
            New-RenderKitJob `
                -JobType 'RenderKitMaintenance' `
                -QueueName 'maintenance'
        ) | Out-Null

        $jobs = @(Get-RenderKitJobList `
                -QueueName 'deliveries' `
                -CorrelationId $correlationId)

        $jobs.Count | Should -Be 1
        $jobs[0].queueName | Should -Be 'deliveries'
        $jobs[0].priority | Should -Be 5
    }

    It 'normalizes legacy jobs into the vNext shape' {
        $legacy = [PSCustomObject]@{
            id             = [guid]::NewGuid().ToString()
            jobType        = 'LegacyJob'
            status         = 'Queued'
            createdAtUtc   = (Get-Date).ToUniversalTime().ToString('o')
            updatedAtUtc   = (Get-Date).ToUniversalTime().ToString('o')
            attempts       = 0
            maxAttempts    = 3
            correlationId  = [guid]::NewGuid().ToString()
            lastError      = 'legacy error'
            payload        = [PSCustomObject]@{ value = 1 }
        }

        $normalized = ConvertTo-RenderKitJobVNext -Job $legacy

        $normalized.jobSchemaVersion | Should -Be '1.1'
        $normalized.payloadSchemaVersion | Should -Be '1.0'
        $normalized.ownerWorkerId | Should -BeNullOrEmpty
        $normalized.progress.phase | Should -Be 'Queued'
        $normalized.lastError.message | Should -Be 'legacy error'
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
        $storedJob.lastError.message | Should -Be 'Cloud upload failed.'
        $storedJob.lastError.code | Should -Be 'RK_INTERNAL_ERROR'
        $storedJob.progress.phase | Should -Be 'Failed'
    }
}