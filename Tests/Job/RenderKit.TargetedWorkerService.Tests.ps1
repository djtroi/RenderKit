Describe 'RenderKit targeted worker execution' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:RenderKitModuleRoot = $repositoryRoot
        function Register-RenderKitFunction {
            param([string]$Name)
            $null = $Name
        }
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.StorageService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.PersistenceService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Versioning/RenderKit.ArtifactVersionService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Logging/Write-RenderKitLog.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Job/RenderKit.JobService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Job/RenderKit.JobWorkerService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Job/RenderKit.WorkerDaemonService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Job/RenderKit.TargetedWorkerService.ps1')
        . (Join-Path $repositoryRoot 'src/Public/Start-RenderKitJobWorker.ps1')
    }

    BeforeEach {
        $env:RENDERKIT_HOME = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:RenderKitArtifactVersionCatalog = $null
        $script:RenderKitJobHandlers = @{}
    }

    AfterEach {
        $env:RENDERKIT_HOME = $null
    }

    It 'runs the requested job without claiming an older queued job' {
        Register-RenderKitJobHandler -JobType 'TargetedJob' -Handler {
            param($Job)
            $null = $Job
            $true
        }
        $older = Add-RenderKitJob -Job (New-RenderKitJob -JobType 'TargetedJob' -QueueName 'targeted-test')
        Start-Sleep -Milliseconds 10
        $target = Add-RenderKitJob -Job (New-RenderKitJob -JobType 'TargetedJob' -QueueName 'targeted-test')

        $worker = Start-RenderKitJobWorker -WorkerId 'targeted-worker' -JobId $target.id -JobType 'TargetedJob' -QueueName 'targeted-test' -RunOnce
        $storedOlder = Get-RenderKitJob -JobId $older.id
        $storedTarget = Get-RenderKitJob -JobId $target.id

        $worker.status | Should -Be 'Stopped'
        $worker.processedCount | Should -Be 1
        $worker.targetedJobId | Should -Be $target.id
        $storedTarget.status | Should -Be 'Succeeded'
        [int]$storedTarget.attempts | Should -Be 1
        $storedTarget.lastWorkerId | Should -Be 'targeted-worker'
        $storedOlder.status | Should -Be 'Queued'
        [int]$storedOlder.attempts | Should -Be 0
    }

    It 'does not claim a target from a different queue' {
        Register-RenderKitJobHandler -JobType 'TargetedJob' -Handler {
            param($Job)
            $null = $Job
            $true
        }
        $target = Add-RenderKitJob -Job (New-RenderKitJob -JobType 'TargetedJob' -QueueName 'queue-a')

        $worker = Start-RenderKitJobWorker -WorkerId 'targeted-worker' -JobId $target.id -JobType 'TargetedJob' -QueueName 'queue-b' -RunOnce
        $storedTarget = Get-RenderKitJob -JobId $target.id

        $worker.processedCount | Should -Be 0
        $storedTarget.status | Should -Be 'Queued'
        [int]$storedTarget.attempts | Should -Be 0
    }

    It 'does not claim a target with a different job type' {
        Register-RenderKitJobHandler -JobType 'TargetedJob' -Handler {
            param($Job)
            $null = $Job
            $true
        }
        $target = Add-RenderKitJob -Job (New-RenderKitJob -JobType 'TargetedJob' -QueueName 'targeted-test')

        $worker = Start-RenderKitJobWorker -WorkerId 'targeted-worker' -JobId $target.id -JobType 'OtherJob' -QueueName 'targeted-test' -RunOnce
        $storedTarget = Get-RenderKitJob -JobId $target.id

        $worker.processedCount | Should -Be 0
        $storedTarget.status | Should -Be 'Queued'
        [int]$storedTarget.attempts | Should -Be 0
    }

    It 'does not steal an already running target from another worker' {
        Register-RenderKitJobHandler -JobType 'TargetedJob' -Handler {
            param($Job)
            $null = $Job
            $true
        }
        $target = Add-RenderKitJob -Job (New-RenderKitJob -JobType 'TargetedJob' -QueueName 'targeted-test')
        $claimed = Start-RenderKitQueuedJobLease -WorkerId 'existing-worker' -JobType 'TargetedJob' -QueueName 'targeted-test' -LeaseSeconds 300

        $worker = Start-RenderKitJobWorker -WorkerId 'targeted-worker' -JobId $target.id -JobType 'TargetedJob' -QueueName 'targeted-test' -RunOnce
        $storedTarget = Get-RenderKitJob -JobId $target.id

        $claimed.id | Should -Be $target.id
        $worker.processedCount | Should -Be 0
        $storedTarget.status | Should -Be 'Running'
        $storedTarget.ownerWorkerId | Should -Be 'existing-worker'
        [int]$storedTarget.attempts | Should -Be 1
    }

    It 'does not execute a terminal target twice' {
        $script:targetExecutionCount = 0
        Register-RenderKitJobHandler -JobType 'TargetedJob' -Handler {
            param($Job)
            $null = $Job
            $script:targetExecutionCount++
            $true
        }
        $target = Add-RenderKitJob -Job (New-RenderKitJob -JobType 'TargetedJob' -QueueName 'targeted-test')

        $first = Start-RenderKitJobWorker -WorkerId 'targeted-worker-1' -JobId $target.id -JobType 'TargetedJob' -QueueName 'targeted-test' -RunOnce
        $second = Start-RenderKitJobWorker -WorkerId 'targeted-worker-2' -JobId $target.id -JobType 'TargetedJob' -QueueName 'targeted-test' -RunOnce
        $storedTarget = Get-RenderKitJob -JobId $target.id

        $first.processedCount | Should -Be 1
        $second.processedCount | Should -Be 0
        $script:targetExecutionCount | Should -Be 1
        $storedTarget.status | Should -Be 'Succeeded'
        [int]$storedTarget.attempts | Should -Be 1
        $storedTarget.lastWorkerId | Should -Be 'targeted-worker-1'
    }

    It 'does not execute a cancelled queued target' {
        Register-RenderKitJobHandler -JobType 'TargetedJob' -Handler {
            param($Job)
            throw "Cancelled target must not execute: $($Job.id)"
        }
        $target = Add-RenderKitJob -Job (New-RenderKitJob -JobType 'TargetedJob' -QueueName 'targeted-test')
        Request-RenderKitJobCancellation -JobId $target.id -Reason 'RS-1563 cancellation boundary' | Out-Null

        $worker = Start-RenderKitJobWorker -WorkerId 'targeted-worker' -JobId $target.id -JobType 'TargetedJob' -QueueName 'targeted-test' -RunOnce
        $storedTarget = Get-RenderKitJob -JobId $target.id

        $worker.processedCount | Should -Be 0
        $storedTarget.status | Should -Be 'Cancelled'
        [int]$storedTarget.attempts | Should -Be 0
    }

    It 'requires targeted workers to be run once' {
        { Start-RenderKitJobWorker -WorkerId 'invalid-targeted-worker' -JobId 'job-1' } |
            Should -Throw '*JobId can only be used with RunOnce workers*'
    }
}