function Test-RenderKitWorkerProcessAlive {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Nullable[int]]$ProcessId,
        [string]$MachineName
    )

    if ($null -eq $ProcessId -or [int]$ProcessId -le 0) {
        return $false
    }

    # A PID is only meaningful inside the process namespace of the machine that
    # created the worker state. Missing/foreign machine identity must never be
    # interpreted as local, otherwise a matching PID can hide a crashed worker
    # or a missing PID can falsely classify a remote worker as dead.
    $currentMachine = [System.Environment]::MachineName
    if ([string]::IsNullOrWhiteSpace($MachineName) -or
        -not $MachineName.Equals(
            $currentMachine,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
        return $false
    }

    return $null -ne (
        Get-Process -Id ([int]$ProcessId) -ErrorAction SilentlyContinue
    )
}

function New-RenderKitWorkerState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WorkerId,
        [string]$JobType,
        [string]$QueueName,
        [string]$LogPath,
        [ValidateSet('Starting', 'Running', 'Idle', 'Stopped', 'Failed', 'CrashDetected')]
        [string]$Status = 'Starting',
        [int]$ProcessedCount = 0,
        [int]$IdleTickCount = 0,
        [string[]]$RecoveredJobIds = @(),
        [object]$LastTick,
        [object]$LastError,
        [object]$Capabilities,
        [string]$StartedAtUtc
    )

    $now = (Get-Date).ToUniversalTime().ToString('o')
    if ([string]::IsNullOrWhiteSpace($StartedAtUtc)) {
        $StartedAtUtc = $now
    }
    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        $LogPath = Get-RenderKitWorkerLogPath -WorkerId $WorkerId
    }

    return [PSCustomObject]@{
        schemaVersion   = '1.0'
        workerId        = $WorkerId
        status          = $Status
        jobType         = $JobType
        queueName       = $QueueName
        processId       = [int]$PID
        machine         = [System.Environment]::MachineName
        startedAtUtc    = $StartedAtUtc
        updatedAtUtc    = $now
        heartbeatAtUtc  = $now
        stoppedAtUtc    = $null
        processedCount  = [int]$ProcessedCount
        idleTickCount   = [int]$IdleTickCount
        recoveredJobIds = @($RecoveredJobIds)
        lastTick        = $LastTick
        lastError       = $LastError
        capabilities    = $Capabilities
        logPath         = $LogPath
    }
}
