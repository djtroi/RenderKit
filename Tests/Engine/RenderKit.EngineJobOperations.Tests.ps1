Describe 'RenderKit engine job operations' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:RenderKitModuleRoot = $repositoryRoot
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.StorageService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.PersistenceService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Versioning/RenderKit.ArtifactVersionService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Job/RenderKit.JobService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Engine/RenderKit.EngineContractService.ps1')
    }

    BeforeEach {
        $env:RENDERKIT_HOME = Join-Path $TestDrive 'renderkit-home'
        if (Test-Path -LiteralPath $env:RENDERKIT_HOME) {
            Remove-Item -LiteralPath $env:RENDERKIT_HOME -Recurse -Force
        }
        $script:RenderKitArtifactVersionCatalog = $null
        $script:Actor = New-RenderKitActorContext `
            -ActorId 'user-1' `
            -ActorType User `
            -DisplayName 'Alice' `
            -Source 'LocalBroker'
    }

    AfterEach {
        $env:RENDERKIT_HOME = $null
    }

    It 'creates broker-facing jobs with actor and result metadata' {
        $result = New-RenderKitEngineJob `
            -JobType 'SendProjectDeliverable' `
            -Payload ([PSCustomObject]@{ projectId = 'project-1' }) `
            -QueueName 'deliveries' `
            -Priority 7 `
            -Actor $script:Actor

        $result.success | Should -BeTrue
        $result.data.jobType | Should -Be 'SendProjectDeliverable'
        $result.data.queueName | Should -Be 'deliveries'
        $result.data.priority | Should -Be 7
        $result.data.requestedBy.actorId | Should -Be 'user-1'
        $result.actor.actorId | Should -Be 'user-1'
    }

    It 'lists and returns details through result envelopes' {
        $created = New-RenderKitEngineJob `
            -JobType 'RenderKitMaintenance' `
            -QueueName 'maintenance' `
            -Actor $script:Actor

        $list = Get-RenderKitEngineJobList `
            -QueueName 'maintenance' `
            -Actor $script:Actor
        $detail = Get-RenderKitEngineJobDetail `
            -JobId $created.data.id `
            -Actor $script:Actor

        $list.success | Should -BeTrue
        @($list.data).Count | Should -Be 1
        $detail.success | Should -BeTrue
        $detail.data.id | Should -Be $created.data.id
    }

    It 'returns a not-found result for unknown job details' {
        $result = Get-RenderKitEngineJobDetail `
            -JobId ([guid]::NewGuid().ToString()) `
            -Actor $script:Actor

        $result.success | Should -BeFalse
        $result.error.code | Should -Be 'RK_JOB_NOT_FOUND'
    }

    It 'cancels queued jobs with actor context' {
        $created = New-RenderKitEngineJob `
            -JobType 'RenderKitMaintenance' `
            -Actor $script:Actor

        $cancelled = Request-RenderKitEngineJobCancellation `
            -JobId $created.data.id `
            -Reason 'User requested cancellation.' `
            -Actor $script:Actor

        $cancelled.success | Should -BeTrue
        $cancelled.data.status | Should -Be 'Cancelled'
        $cancelled.data.cancelReason | Should -Be 'User requested cancellation.'
        $cancelled.data.requestedBy.actorId | Should -Be 'user-1'
    }

    It 'updates progress and marks running jobs as succeeded' {
        $created = New-RenderKitEngineJob `
            -JobType 'RenderKitMaintenance' `
            -Actor $script:Actor
        Start-RenderKitQueuedJob | Out-Null

        $progress = Update-RenderKitEngineJobProgress `
            -JobId $created.data.id `
            -Phase 'Copying' `
            -Message 'Copying files' `
            -Current 5 `
            -Total 10 `
            -Actor $script:Actor
        $succeeded = Set-RenderKitEngineJobSucceeded `
            -JobId $created.data.id `
            -Result ([PSCustomObject]@{ artifact = 'deliverable.zip' }) `
            -Actor $script:Actor

        $progress.success | Should -BeTrue
        $progress.data.progress.percent | Should -Be 50
        $succeeded.success | Should -BeTrue
        $succeeded.data.status | Should -Be 'Succeeded'
        $succeeded.data.result.artifact | Should -Be 'deliverable.zip'
    }

    It 'requires actor context before mutating job progress or terminal state' {
        $created = New-RenderKitEngineJob `
            -JobType 'RenderKitMaintenance' `
            -Actor $script:Actor
        Start-RenderKitQueuedJob | Out-Null

        $progress = Update-RenderKitEngineJobProgress `
            -JobId $created.data.id `
            -Phase 'Copying' `
            -Message 'Copying files' `
            -Current 5 `
            -Total 10
        $succeeded = Set-RenderKitEngineJobSucceeded `
            -JobId $created.data.id `
            -Result ([PSCustomObject]@{ artifact = 'deliverable.zip' })
        $failed = Set-RenderKitEngineJobFailed `
            -JobId $created.data.id `
            -Message 'Maintenance failed.'
        $job = Get-RenderKitJob -JobId $created.data.id

        $progress.success | Should -BeFalse
        $progress.error.code | Should -Be 'RK_ACCESS_CONTEXT_MISSING'
        $succeeded.success | Should -BeFalse
        $succeeded.error.code | Should -Be 'RK_ACCESS_CONTEXT_MISSING'
        $failed.success | Should -BeFalse
        $failed.error.code | Should -Be 'RK_ACCESS_CONTEXT_MISSING'
        $job.status | Should -Be 'Running'
        $job.progress.percent | Should -Be 0
        $job.result | Should -BeNullOrEmpty
        $job.lastError | Should -BeNullOrEmpty
    }
    
    It 'marks jobs as failed and retries failed jobs' {
        $created = New-RenderKitEngineJob `
            -JobType 'RenderKitMaintenance' `
            -Actor $script:Actor

        $failed = Set-RenderKitEngineJobFailed `
            -JobId $created.data.id `
            -Message 'Maintenance failed.' `
            -Actor $script:Actor
        $retried = Retry-RenderKitEngineJob `
            -JobId $created.data.id `
            -Actor $script:Actor

        $failed.success | Should -BeTrue
        $failed.data.status | Should -Be 'Failed'
        $failed.data.lastError.message | Should -Be 'Maintenance failed.'
        $retried.success | Should -BeTrue
        $retried.data.status | Should -Be 'Queued'
        $retried.data.lastError | Should -BeNullOrEmpty
    }
}