function Register-RenderKitJobHandler {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobType,
        [Parameter(Mandatory)]
        [scriptblock]$Handler
    )

    if (-not $script:RenderKitJobHandlers) {
        $script:RenderKitJobHandlers = @{}
    }

    $script:RenderKitJobHandlers[$JobType] = $Handler
}

function Get-RenderKitJobHandler {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobType
    )

    if (-not $script:RenderKitJobHandlers) {
        $script:RenderKitJobHandlers = @{}
    }

    if (-not $script:RenderKitJobHandlers.ContainsKey($JobType)) {
        return $null
    }

    return $script:RenderKitJobHandlers[$JobType]
}

function Get-RenderKitJobById {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId
    )

    $store = Read-RenderKitJobStore
    return @($store.jobs |
        Where-Object { [string]$_.id -eq $JobId } |
        Select-Object -First 1)
}

function Complete-RenderKitJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId
    )

    Set-RenderKitJobStatus -JobId $JobId -Status Succeeded
    return Get-RenderKitJobById -JobId $JobId
}

function Fail-RenderKitJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [Parameter(Mandatory)]
        [string]$ErrorMessage
    )

    $job = Get-RenderKitJobById -JobId $JobId
    if (-not $job) {
        throw "RenderKit job '$JobId' was not found."
    }

    if ([int]$job.attempts -lt [int]$job.maxAttempts) {
        Set-RenderKitJobStatus -JobId $JobId -Status Queued
    }
    else {
        Set-RenderKitJobStatus `
            -JobId $JobId `
            -Status Failed `
            -ErrorMessage $ErrorMessage
    }

    return Get-RenderKitJobById -JobId $JobId
}

function Invoke-RenderKitJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId
    )

    $job = Get-RenderKitJobById -JobId $JobId
    if (-not $job) {
        throw "RenderKit job '$JobId' was not found."
    }
    if ([string]$job.status -eq 'Cancelled') {
        return $job
    }

    $handler = Get-RenderKitJobHandler -JobType ([string]$job.jobType)
    if (-not $handler) {
        Set-RenderKitJobStatus `
            -JobId $JobId `
            -Status Failed `
            -ErrorMessage "No RenderKit job handler is registered for '$($job.jobType)'."
        return Get-RenderKitJobById -JobId $JobId
    }

    Set-RenderKitJobStatus -JobId $JobId -Status Running
    $runningJob = Get-RenderKitJobById -JobId $JobId

    try {
        & $handler $runningJob | Out-Null
        return Complete-RenderKitJob -JobId $JobId
    }
    catch {
        return Fail-RenderKitJob `
            -JobId $JobId `
            -ErrorMessage $_.Exception.Message
    }
}

function Invoke-RenderKitNextQueuedJob {
    [CmdletBinding()]
    param(
        [string]$JobType
    )

    $job = @(Get-RenderKitQueuedJob -JobType $JobType | Select-Object -First 1)
    if (-not $job) {
        return $null
    }

    return Invoke-RenderKitJob -JobId ([string]$job[0].id)
}

function Initialize-RenderKitDefaultJobHandlers {
    [CmdletBinding()]
    param()

    Register-RenderKitJobHandler `
        -JobType 'ProjectLifecycleAutomation' `
        -Handler {
            param($Job)
            Write-RenderKitLog `
                -Level Debug `
                -Message "Processed ProjectLifecycleAutomation job '$($Job.id)'."
        }
}

Initialize-RenderKitDefaultJobHandlers