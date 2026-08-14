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

        # RS-1511: Handler-owned persisted state is authoritative. A handler may
        # atomically fail, cancel, complete, or re-queue its own work, so generic
        # auto-completion is only valid while the persisted status is Running.
        if ($currentJob -and [string]$currentJob.status -ne 'Running') {
            return $currentJob
        }

        return Complete-RenderKitJob -JobId $JobId
    }
    catch {
        $currentJob = Get-RenderKitJobById -JobId $JobId

        # RS-1511: Generic retry/failure policy must not overwrite a state the
        # handler already committed before throwing. The persisted state is the
        # durable outcome; retry policy applies only while the job remains Running.
        if ($currentJob -and [string]$currentJob.status -ne 'Running') {
            return $currentJob
        }

        return Fail-RenderKitJob `
            -JobId $JobId `
            -ErrorMessage $_.Exception.Message
    }
}
