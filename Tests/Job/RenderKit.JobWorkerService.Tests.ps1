$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:RenderKitModuleRoot = $repositoryRoot
. (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.StorageService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.PersistenceService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Versioning/RenderKit.ArtifactVersionService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Logging/Write-RenderKitLog.ps1')
. (Join-Path $repositoryRoot 'src/Private/Job/RenderKit.JobService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Job/RenderKit.JobWorkerService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Engine/RenderKit.EngineContractService.ps1')

Describe 'RenderKit job worker service' {
    BeforeEach {
        $env:RENDERKIT_HOME = Join-Path $TestDrive 'renderkit-home'
        $script:RenderKitArtifactVersionCatalog = $null
        $script:RenderKitJobHandlers = @{}
    }

    AfterEach {
        $env:RENDERKIT_HOME = $null
    }

    It 'registers and resolves job handlers' {
        Register-RenderKitJobHandler `
            -JobType 'TestJob' `
            -HandlerId 'RenderKit.TestJob' `
            -Version '2.0' `
            -Description 'Test handler.' `
            -SupportsCancellation `
            -SupportsProgress `
            -IsIdempotent `
            -RequiredCapabilities @('local-files') `
            -Handler { param($Job) $Job.id }

        Get-RenderKitJobHandler -JobType 'TestJob' |
            Should -Not -BeNullOrEmpty
        $registration = Get-RenderKitJobHandlerRegistration -JobType 'TestJob'
        $registration.handlerId | Should -Be 'RenderKit.TestJob'
        $registration.version | Should -Be '2.0'
    }

    It 'publishes safe handler catalog metadata without scriptblocks' {
        Register-RenderKitJobHandler `
            -JobType 'CatalogJob' `
            -HandlerId 'RenderKit.CatalogJob' `
            -Description 'Catalog visible job.' `
            -SupportsProgress `
            -IsIdempotent `
            -RequiredCapabilities @('worker') `
            -PayloadSchema ([PSCustomObject]@{ type = 'object' }) `
            -Handler { param($Job) $true }

        $catalog = @(Get-RenderKitJobHandlerCatalog -JobType 'CatalogJob')

        $catalog.Count | Should -Be 1
        $catalog[0].jobType | Should -Be 'CatalogJob'
        $catalog[0].handlerId | Should -Be 'RenderKit.CatalogJob'
        $catalog[0].supportsProgress | Should -BeTrue
        $catalog[0].isIdempotent | Should -BeTrue
        $catalog[0].requiredCapabilities[0] | Should -Be 'worker'
        $catalog[0].PSObject.Properties.Name | Should -Not -Contain 'handler'

        $engineCatalog = Get-RenderKitEngineJobHandlerCatalog -JobType 'CatalogJob'
        $engineCatalog.success | Should -BeTrue
        $engineCatalog.data[0].handlerId | Should -Be 'RenderKit.CatalogJob'
    }

    It 'runs a queued job successfully' {
        Register-RenderKitJobHandler `
            -JobType 'TestJob' `
            -Handler { param($Job) $true }
        $job = Add-RenderKitJob -Job (New-RenderKitJob -JobType 'TestJob')

        $result = Invoke-RenderKitJob -JobId $job.id

        $result.status | Should -Be 'Succeeded'
        [int]$result.attempts | Should -Be 1
    }

    It 'requeues failed jobs while retry attempts remain' {
        Register-RenderKitJobHandler `
            -JobType 'FailingJob' `
            -Handler { throw 'temporary failure' }
        $job = Add-RenderKitJob -Job (New-RenderKitJob -JobType 'FailingJob')

        $result = Invoke-RenderKitJob -JobId $job.id

        $result.status | Should -Be 'Queued'
        [int]$result.attempts | Should -Be 1
    }

    It 'marks failed jobs after max attempts' {
        Register-RenderKitJobHandler `
            -JobType 'AlwaysFailingJob' `
            -Handler { throw 'permanent failure' }
        $job = Add-RenderKitJob -Job (New-RenderKitJob -JobType 'AlwaysFailingJob')

        Invoke-RenderKitJob -JobId $job.id | Out-Null
        Invoke-RenderKitJob -JobId $job.id | Out-Null
        $result = Invoke-RenderKitJob -JobId $job.id

        $result.status | Should -Be 'Failed'
        $result.lastError.message | Should -Be 'permanent failure'
        $result.lastError.code | Should -Be 'RK_INTERNAL_ERROR'
    }



    It 'starts queued job leases with worker ownership and lease metadata' {
        $job = Add-RenderKitJob -Job (New-RenderKitJob -JobType 'ClaimJob')

        $claimed = Start-RenderKitQueuedJobLease `
            -WorkerId 'worker-1' `
            -JobType 'ClaimJob' `
            -LeaseSeconds 60

        $claimed.id | Should -Be $job.id
        $claimed.status | Should -Be 'Running'
        $claimed.ownerWorkerId | Should -Be 'worker-1'
        $claimed.leaseUntilUtc | Should -Not -BeNullOrEmpty
        [int]$claimed.attempts | Should -Be 1
    }

    It 'renews heartbeats only for the owning worker' {
        $job = Add-RenderKitJob -Job (New-RenderKitJob -JobType 'HeartbeatJob')
        Start-RenderKitQueuedJobLease `
            -WorkerId 'worker-1' `
            -JobType 'HeartbeatJob' |
            Out-Null

        $renewed = Update-RenderKitJobHeartbeat `
            -JobId $job.id `
            -WorkerId 'worker-1' `
            -LeaseSeconds 120

        $renewed.ownerWorkerId | Should -Be 'worker-1'
        $renewed.heartbeatAtUtc | Should -Not -BeNullOrEmpty
        { Update-RenderKitJobHeartbeat -JobId $job.id -WorkerId 'worker-2' } |
            Should -Throw
    }

    It 'recovers stale running jobs back to the queue' {
        $job = Add-RenderKitJob -Job (New-RenderKitJob -JobType 'StaleJob')
        Start-RenderKitQueuedJobLease `
            -WorkerId 'worker-1' `
            -JobType 'StaleJob' `
            -LeaseSeconds 1 |
            Out-Null

        $recovery = Reset-RenderKitStaleRunningJob `
            -NowUtc ([DateTime]::UtcNow.AddMinutes(5))
        $recovered = Get-RenderKitJob -JobId $job.id

        $recovery.RecoveredCount | Should -Be 1
        $recovered.status | Should -Be 'Queued'
        $recovered.ownerWorkerId | Should -BeNullOrEmpty
        $recovered.leaseUntilUtc | Should -BeNullOrEmpty
    }

    It 'runs a worker tick without double-counting attempts' {
        Register-RenderKitJobHandler `
            -JobType 'TickJob' `
            -Handler { param($Job) $true }
        Add-RenderKitJob -Job (New-RenderKitJob -JobType 'TickJob') |
            Out-Null

        $tick = Invoke-RenderKitWorkerTick `
            -WorkerId 'worker-1' `
            -JobType 'TickJob'

        $tick.Processed | Should -BeTrue
        $tick.WorkerId | Should -Be 'worker-1'
        $tick.ClaimedJob.ownerWorkerId | Should -Be 'worker-1'
        $tick.ResultJob.status | Should -Be 'Succeeded'
        [int]$tick.ResultJob.attempts | Should -Be 1
    }

    It 'uses the default lifecycle automation handler' {
        Initialize-RenderKitDefaultJobHandlers
        $catalog = @(Get-RenderKitJobHandlerCatalog -JobType 'ProjectLifecycleAutomation')
        $catalog[0].handlerId | Should -Be 'RenderKit.ProjectLifecycleAutomation'
        $catalog[0].isIdempotent | Should -BeTrue
        $job = Add-RenderKitJob -Job (
            New-RenderKitJob -JobType 'ProjectLifecycleAutomation'
        )

        $result = Invoke-RenderKitJob -JobId $job.id

        $result.status | Should -Be 'Succeeded'
    }
}