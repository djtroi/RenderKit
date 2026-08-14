function Register-RenderKitWorkerCrashIfNeeded {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WorkerId,
        [string]$JobType,
        [string]$QueueName,
        [string]$LogPath
    )

    $previous = Read-RenderKitWorkerState -WorkerId $WorkerId
    if (-not $previous -or [string]$previous.status -notin @('Starting', 'Running', 'Idle')) {
        return [PSCustomObject]@{
            crashDetected = $false
            previousState = $previous
        }
    }

    # RS-1515: A PID is scoped to the host that created the worker state. Shared
    # state can contain active workers from another machine, so "not locally
    # alive" must not be interpreted as "crashed" until ownership is explicitly
    # confirmed. Missing machine identity is also unverifiable and is therefore
    # left untouched for compatibility with legacy state files.
    $previousMachine = if ($previous.PSObject.Properties.Name -contains 'machine') {
        [string]$previous.machine
    }
    else {
        $null
    }
    $currentMachine = [System.Environment]::MachineName
    $isLocalState = -not [string]::IsNullOrWhiteSpace($previousMachine) -and
        $previousMachine.Equals(
            $currentMachine,
            [System.StringComparison]::OrdinalIgnoreCase
        )

    if (-not $isLocalState) {
        return [PSCustomObject]@{
            crashDetected = $false
            previousState = $previous
        }
    }

    $previousProcessId = 0
    $hasUsableProcessId = [int]::TryParse(
        [string]$previous.processId,
        [ref]$previousProcessId
    ) -and $previousProcessId -gt 0

    $alive = if ($hasUsableProcessId) {
        Test-RenderKitWorkerProcessAlive `
            -ProcessId $previousProcessId `
            -MachineName $previousMachine
    }
    else {
        $false
    }

    if ($alive) {
        return [PSCustomObject]@{
            crashDetected = $false
            previousState = $previous
        }
    }

    $state = New-RenderKitWorkerState `
        -WorkerId $WorkerId `
        -JobType $JobType `
        -QueueName $QueueName `
        -LogPath $LogPath `
        -Status CrashDetected `
        -ProcessedCount ([int]$previous.processedCount) `
        -IdleTickCount ([int]$previous.idleTickCount) `
        -RecoveredJobIds @($previous.recoveredJobIds) `
        -Capabilities $(if (
            $previous.PSObject.Properties.Name -contains 'capabilities'
        ) { $previous.capabilities } else { $null }) `
        -LastError ([PSCustomObject]@{
            message       = 'Previous worker process is no longer alive.'
            previousPid   = $previous.processId
            detectedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        }) `
        -StartedAtUtc ([string]$previous.startedAtUtc)
    $state.stoppedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    Save-RenderKitWorkerState -State $state | Out-Null
    Write-RenderKitWorkerLogEntry `
        -WorkerId $WorkerId `
        -LogPath $LogPath `
        -Level Warning `
        -Message ("Detected crashed worker process '{0}'." -f $previous.processId) |
        Out-Null

    return [PSCustomObject]@{
        crashDetected = $true
        previousState = $previous
    }
}
