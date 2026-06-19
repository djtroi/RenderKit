$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:RenderKitModuleRoot = $repositoryRoot
. (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.StorageService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.PersistenceService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Versioning/RenderKit.ArtifactVersionService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Logging/Write-RenderKitLog.ps1')
. (Join-Path $repositoryRoot 'src/Private/Job/RenderKit.JobService.ps1')
. (Join-Path $repositoryRoot 'src/Private/Job/RenderKit.JobWorkerService.ps1')

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
            -Handler { param($Job) $Job.id }

        Get-RenderKitJobHandler -JobType 'TestJob' |
            Should -Not -BeNullOrEmpty
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
        $result.lastError | Should -Be 'permanent failure'
    }

    It 'uses the default lifecycle automation handler' {
        Initialize-RenderKitDefaultJobHandlers
        $job = Add-RenderKitJob -Job (
            New-RenderKitJob -JobType 'ProjectLifecycleAutomation'
        )

        $result = Invoke-RenderKitJob -JobId $job.id

        $result.status | Should -Be 'Succeeded'
    }
}
