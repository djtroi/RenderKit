Describe 'RenderKit targeted worker execution' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:RenderKitModuleRoot = $repositoryRoot
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
        Register-RenderKitJobHandler -JobType 'TargetedJob' -Handler { param($Job) $true }
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
        Register-RenderKitJobHandler -JobType 'TargetedJob' -Handler { param($Job) $true }
        $target = Add-RenderKitJob -Job (New-RenderKitJob -JobType 'TargetedJob' -QueueName 'queue-a')

        $worker = Start-RenderKitJobWorker -WorkerId 'targeted-worker' -JobId $target.id -JobType 'TargetedJob' -QueueName 'queue-b' -RunOnce
        $storedTarget = Get-RenderKitJob -JobId $target.id

        $worker.processedCount | Should -Be 0
        $storedTarget.status | Should -Be 'Queued'
        [int]$storedTarget.attempts | Should -Be 0
    }

    It 'requires targeted workers to be run once' {
        { Start-RenderKitJobWorker -WorkerId 'invalid-targeted-worker' -JobId 'job-1' } |
            Should -Throw '*JobId can only be used with RunOnce workers*'
    }
}
