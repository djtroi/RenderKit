function Start-RenderKitQueuedJobLeaseById {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [string]$WorkerId,
        [string]$JobType,
        [string]$QueueName,
        [ValidateRange(1, 86400)]
        [int]$LeaseSeconds = 300
    )

    $normalizedWorkerId = New-RenderKitWorkerId -WorkerId $WorkerId
    $claimState = [PSCustomObject]@{ Claimed = $false }
    $path = Get-RenderKitJobStorePath

    Invoke-RenderKitJsonFileTransaction `
        -Path $path `
        -DefaultValue (New-RenderKitJobStore) `
        -Depth 30 `
        -Validator { param($value) Test-RenderKitJobStore $value } `
        -Update {
            param($store)

            $store = ConvertTo-RenderKitJobStoreVNext -Store $store
            $job = @($store.jobs | Where-Object {
                [string]$_.id -eq $JobId
            } | Select-Object -First 1)
            if ($job.Count -eq 0) {
                return $store
            }

            $candidate = $job[0]
            if ([string]$candidate.status -ne 'Queued') {
                return $store
            }
            if (-not [string]::IsNullOrWhiteSpace($JobType) -and
                [string]$candidate.jobType -ne $JobType) {
                return $store
            }
            if (-not [string]::IsNullOrWhiteSpace($QueueName) -and
                [string]$candidate.queueName -ne $QueueName) {
                return $store
            }

            $now = (Get-Date).ToUniversalTime()
            $candidate.status = 'Running'
            $candidate.updatedAtUtc = $now.ToString('o')
            $candidate.startedAtUtc = $now.ToString('o')
            $candidate.claimedAtUtc = $now.ToString('o')
            $candidate.heartbeatAtUtc = $now.ToString('o')
            $candidate.leaseUntilUtc = $now.AddSeconds($LeaseSeconds).ToString('o')
            $candidate.ownerWorkerId = $normalizedWorkerId
            $candidate.lastWorkerId = $normalizedWorkerId
            $candidate.retryAfterUtc = $null
            $candidate.attempts = [int]$candidate.attempts + 1
            if ($candidate.progress) {
                $candidate.progress.phase = 'Running'
                $candidate.progress.updatedAtUtc = $now.ToString('o')
            }

            $claimState.Claimed = $true
            $store.updatedAtUtc = $now.ToString('o')
            return $store
        } |
        Out-Null

    if (-not [bool]$claimState.Claimed) {
        return $null
    }

    return Get-RenderKitJob -JobId $JobId
}

function Invoke-RenderKitTargetedWorkerRunOnce {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [string]$WorkerId,
        [string]$JobType = 'BackupProject',
        [string]$QueueName = 'backup',
        [ValidateRange(1, 86400)]
        [int]$LeaseSeconds = 300,
        [string]$LogPath
    )

    $normalizedWorkerId = New-RenderKitWorkerId -WorkerId $WorkerId
    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        $LogPath = Get-RenderKitWorkerLogPath -WorkerId $normalizedWorkerId
    }

    $crashRecovery = Register-RenderKitWorkerCrashIfNeeded `
        -WorkerId $normalizedWorkerId `
        -JobType $JobType `
        -QueueName $QueueName `
        -LogPath $LogPath
    $capabilityCommand = Get-Command `
        -Name Get-BackupWorkerCapabilitySnapshot `
        -CommandType Function `
        -ErrorAction SilentlyContinue
    $workerCapabilities = if ($capabilityCommand) {
        Get-BackupWorkerCapabilitySnapshot -WorkerId $normalizedWorkerId
    }
    else {
        $null
    }

    $state = New-RenderKitWorkerState `
        -WorkerId $normalizedWorkerId `
        -JobType $JobType `
        -QueueName $QueueName `
        -LogPath $LogPath `
        -Capabilities $workerCapabilities `
        -Status Running
    Save-RenderKitWorkerState -State $state | Out-Null
    Write-RenderKitWorkerLogEntry `
        -WorkerId $normalizedWorkerId `
        -LogPath $LogPath `
        -JobId $JobId `
        -Message ("Targeted worker started for jobId='{0}', jobType='{1}', queue='{2}'." -f $JobId, $JobType, $QueueName) |
        Out-Null

    try {
        $recovery = Reset-RenderKitStaleRunningJob
        $claimed = Start-RenderKitQueuedJobLeaseById `
            -JobId $JobId `
            -WorkerId $normalizedWorkerId `
            -JobType $JobType `
            -QueueName $QueueName `
            -LeaseSeconds $LeaseSeconds

        $resultJob = $null
        $processed = $false
        if ($claimed) {
            $resultJob = Invoke-RenderKitJob -JobId $JobId
            $processed = $true
            Write-RenderKitWorkerLogEntry `
                -WorkerId $normalizedWorkerId `
                -LogPath $LogPath `
                -JobId $JobId `
                -Message ("Processed targeted job '{0}' with status '{1}'." -f $JobId, [string]$resultJob.status) |
                Out-Null
        }
        else {
            Write-RenderKitWorkerLogEntry `
                -WorkerId $normalizedWorkerId `
                -LogPath $LogPath `
                -JobId $JobId `
                -Level Debug `
                -Message ("Targeted job '{0}' was not claimable by this worker." -f $JobId) |
                Out-Null
        }

        $state = New-RenderKitWorkerState `
            -WorkerId $normalizedWorkerId `
            -JobType $JobType `
            -QueueName $QueueName `
            -LogPath $LogPath `
            -Status Stopped `
            -ProcessedCount $(if ($processed) { 1 } else { 0 }) `
            -IdleTickCount $(if ($processed) { 0 } else { 1 }) `
            -RecoveredJobIds @($recovery.RecoveredJobIds) `
            -LastTick ([PSCustomObject]@{
                WorkerId = $normalizedWorkerId
                ClaimedJob = $claimed
                ResultJob = $resultJob
                RecoveredJobIds = @($recovery.RecoveredJobIds)
                Processed = $processed
            }) `
            -Capabilities $workerCapabilities `
            -StartedAtUtc ([string]$state.startedAtUtc)
        $state.stoppedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        Save-RenderKitWorkerState -State $state | Out-Null

        return [PSCustomObject]@{
            workerId             = $normalizedWorkerId
            status               = 'Stopped'
            processedCount       = $(if ($processed) { 1 } else { 0 })
            idleTickCount        = $(if ($processed) { 0 } else { 1 })
            recoveredJobIds      = @($recovery.RecoveredJobIds)
            crashDetectedAtStart = [bool]$crashRecovery.crashDetected
            lastTick             = $state.lastTick
            statePath            = Get-RenderKitWorkerStatePath -WorkerId $normalizedWorkerId
            logPath              = $LogPath
            detached             = $false
            targetedJobId        = $JobId
        }
    }
    catch {
        $state.status = 'Failed'
        $state.lastError = [PSCustomObject]@{
            message       = $_.Exception.Message
            occurredAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        }
        $state.stoppedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        Save-RenderKitWorkerState -State $state | Out-Null
        Write-RenderKitWorkerLogEntry `
            -WorkerId $normalizedWorkerId `
            -LogPath $LogPath `
            -JobId $JobId `
            -Level Error `
            -Message $_.Exception.Message |
            Out-Null
        throw
    }
}
