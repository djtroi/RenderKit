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

    if ([string]$job.status -eq 'Queued') {
        Set-RenderKitJobStatus -JobId $JobId -Status Running
    }
    $runningJob = Get-RenderKitJobById -JobId $JobId

    try {
        & $handler $runningJob | Out-Null
        $currentJob = Get-RenderKitJobById -JobId $JobId

        # Handler-owned persisted state wins over generic worker policy. This
        # matters for handlers that atomically cancel, fail, or re-queue their
        # own work: automatic completion is only valid while status is Running.
        if ($currentJob -and [string]$currentJob.status -ne 'Running') {
            return $currentJob
        }

        return Complete-RenderKitJob -JobId $JobId
    }
    catch {
        $currentJob = Get-RenderKitJobById -JobId $JobId

        # Apply retry policy only when the handler left the job Running. If the
        # handler already persisted another state before throwing, mutating it
        # again here can erase the real outcome or schedule an unintended retry.
        if ($currentJob -and [string]$currentJob.status -ne 'Running') {
            return $currentJob
        }

        return Fail-RenderKitJob `
            -JobId $JobId `
            -ErrorMessage $_.Exception.Message
    }
}
