function Get-RenderKitJobStatus {
    [CmdletBinding()]
    param(
        [string]$JobId,
        [string]$JobType,
        [string]$QueueName,
        [ValidateSet('Queued', 'Running', 'RetryScheduled', 'Succeeded', 'Failed', 'Cancelled')]
        [string]$Status,
        [switch]$IncludeLogs,
        [ValidateRange(1, 1000)]
        [int]$Tail = 50
    )

    $jobs = if (-not [string]::IsNullOrWhiteSpace($JobId)) {
        $job = Get-RenderKitJob -JobId $JobId
        if (-not $job) {
            throw "RenderKit job '$JobId' was not found."
        }
        @($job)
    }
    else {
        @(Get-RenderKitJobList `
                -Status $Status `
                -JobType $JobType `
                -QueueName $QueueName)
    }

    return @($jobs | ForEach-Object {
            New-RenderKitJobStatusSnapshot `
                -Job $_ `
                -IncludeLogs:$IncludeLogs `
                -Tail $Tail
        })
}

Register-RenderKitFunction -Name 'Get-RenderKitJobStatus'
