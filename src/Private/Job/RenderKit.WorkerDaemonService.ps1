function ConvertTo-RenderKitWorkerSafeName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $safe = [System.Text.RegularExpressions.Regex]::Replace(
        $Value,
        '[^a-zA-Z0-9_.-]',
        '_'
    )
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return 'worker'
    }

    return $safe
}

function Get-RenderKitWorkerStateRoot {
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    return New-RenderKitStorageDirectory -Path (
        Join-Path -Path (Get-RenderKitStorageRoot -Kind State -Ensure) -ChildPath 'Workers'
    )
}

function Get-RenderKitWorkerLogRoot {
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    return New-RenderKitStorageDirectory -Path (
        Join-Path -Path (Get-RenderKitStorageRoot -Kind State -Ensure) -ChildPath 'WorkerLogs'
    )
}

function Get-RenderKitWorkerStatePath {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [string]$WorkerId
    )

    $fileName = '{0}.json' -f (ConvertTo-RenderKitWorkerSafeName -Value $WorkerId)
    return Join-Path -Path (Get-RenderKitWorkerStateRoot) -ChildPath $fileName
}

function Get-RenderKitWorkerLogPath {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [string]$WorkerId
    )

    $fileName = '{0}.log' -f (ConvertTo-RenderKitWorkerSafeName -Value $WorkerId)
    return Join-Path -Path (Get-RenderKitWorkerLogRoot) -ChildPath $fileName
}

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
    if (-not [string]::IsNullOrWhiteSpace($MachineName) -and
        [string]$MachineName -ne [string]$env:COMPUTERNAME) {
        return $false
    }

    return $null -ne (Get-Process -Id ([int]$ProcessId) -ErrorAction SilentlyContinue)
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
        machine         = [string]$env:COMPUTERNAME
        startedAtUtc    = $StartedAtUtc
        updatedAtUtc    = $now
        heartbeatAtUtc  = $now
        stoppedAtUtc    = $null
        processedCount  = [int]$ProcessedCount
        idleTickCount   = [int]$IdleTickCount
        recoveredJobIds = @($RecoveredJobIds)
        lastTick        = $LastTick
        lastError       = $LastError
        logPath         = $LogPath
    }
}

function Save-RenderKitWorkerState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$State
    )

    $workerId = [string]$State.workerId
    if ([string]::IsNullOrWhiteSpace($workerId)) {
        throw 'RenderKit worker state must contain a worker id.'
    }

    $State | Add-Member -NotePropertyName updatedAtUtc -NotePropertyValue ((Get-Date).ToUniversalTime().ToString('o')) -Force
    $path = Get-RenderKitWorkerStatePath -WorkerId $workerId
    Write-RenderKitJsonFileAtomic `
        -Value $State `
        -Path $path `
        -Depth 50 |
        Out-Null

    return $path
}

function Read-RenderKitWorkerState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WorkerId
    )

    $path = Get-RenderKitWorkerStatePath -WorkerId $WorkerId
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }

    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Get-RenderKitWorkerStateList {
    [CmdletBinding()]
    param()

    $root = Get-RenderKitWorkerStateRoot
    return @(
        Get-ChildItem -LiteralPath $root -File -Filter '*.json' -ErrorAction SilentlyContinue |
            ForEach-Object {
                try {
                    Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
                }
                catch {
                    [PSCustomObject]@{
                        workerId = $_.BaseName
                        status   = 'Unreadable'
                        statePath = $_.FullName
                        error    = $_.Exception.Message
                    }
                }
            }
    )
}

function Write-RenderKitWorkerLogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WorkerId,
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('Info', 'Debug', 'Warning', 'Error')]
        [string]$Level = 'Info',
        [string]$JobId,
        [string]$LogPath
    )

    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        $LogPath = Get-RenderKitWorkerLogPath -WorkerId $WorkerId
    }
    $logRoot = Split-Path -Path $LogPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($logRoot) -and
        -not (Test-Path -LiteralPath $logRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    }

    $entry = [ordered]@{
        timestampUtc = (Get-Date).ToUniversalTime().ToString('o')
        level        = $Level
        workerId     = $WorkerId
        jobId        = $JobId
        message      = $Message
    }
    Add-Content `
        -LiteralPath $LogPath `
        -Value (($entry | ConvertTo-Json -Compress -Depth 10)) `
        -Encoding UTF8

    return $LogPath
}

function Read-RenderKitWorkerLogTail {
    [CmdletBinding()]
    param(
        [string]$LogPath,
        [ValidateRange(1, 1000)]
        [int]$Tail = 50
    )

    if ([string]::IsNullOrWhiteSpace($LogPath) -or
        -not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
        return @()
    }

    return @(Get-Content -LiteralPath $LogPath -Tail $Tail -ErrorAction SilentlyContinue)
}

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

    $alive = Test-RenderKitWorkerProcessAlive `
        -ProcessId ([int]$previous.processId) `
        -MachineName ([string]$previous.machine)
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

function New-RenderKitJobStatusSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Job,
        [switch]$IncludeLogs,
        [ValidateRange(1, 1000)]
        [int]$Tail = 50
    )

    $now = (Get-Date).ToUniversalTime()
    $leaseUntil = ConvertTo-RenderKitUtcDateTime -Value $Job.leaseUntilUtc
    $workerId = if (-not [string]::IsNullOrWhiteSpace([string]$Job.ownerWorkerId)) {
        [string]$Job.ownerWorkerId
    }
    elseif (@($Job.PSObject.Properties | Where-Object { $_.Name -eq 'lastWorkerId' }).Count -gt 0 -and
        -not [string]::IsNullOrWhiteSpace([string]$Job.lastWorkerId)) {
        [string]$Job.lastWorkerId
    }
    else {
        $null
    }
    $workerLogPath = if (-not [string]::IsNullOrWhiteSpace($workerId)) {
        Get-RenderKitWorkerLogPath -WorkerId $workerId
    }
    else {
        $null
    }

    $payload = $Job.payload
    $payloadProperties = if ($payload) { @($payload.PSObject.Properties | ForEach-Object { $_.Name }) } else { @() }
    $progressStatePath = if ($payloadProperties -contains 'progress' -and $payload.progress -and $payload.progress.statePath) { [string]$payload.progress.statePath } else { $null }
    $resumeStatePath = if ($payloadProperties -contains 'resume' -and $payload.resume -and $payload.resume.statePath) { [string]$payload.resume.statePath } else { $null }
    $controlStatePath = if ($payloadProperties -contains 'control' -and $payload.control -and $payload.control.statePath) { [string]$payload.control.statePath } else { $null }
    $chunkIndexStatePath = if ($payloadProperties -contains 'chunkPlan' -and $payload.chunkPlan -and $payload.chunkPlan.index -and $payload.chunkPlan.index.statePath) { [string]$payload.chunkPlan.index.statePath } else { $null }

    $progressSnapshot = $null
    if (-not [string]::IsNullOrWhiteSpace($progressStatePath) -and
        (Test-Path -LiteralPath $progressStatePath -PathType Leaf)) {
        try {
            $progressSnapshot = Get-Content -LiteralPath $progressStatePath -Raw | ConvertFrom-Json
        }
        catch {
            $progressSnapshot = $null
        }
    }

    return [PSCustomObject]@{
        id              = [string]$Job.id
        jobType         = [string]$Job.jobType
        status          = [string]$Job.status
        queueName       = [string]$Job.queueName
        priority        = [int]$Job.priority
        attempts        = [int]$Job.attempts
        maxAttempts     = [int]$Job.maxAttempts
        createdAtUtc    = [string]$Job.createdAtUtc
        updatedAtUtc    = [string]$Job.updatedAtUtc
        startedAtUtc    = [string]$Job.startedAtUtc
        completedAtUtc  = [string]$Job.completedAtUtc
        progress        = if (@($Job.PSObject.Properties | Where-Object { $_.Name -eq 'progress' }).Count -gt 0) { $Job.progress } else { $null }
        progressSnapshot = $progressSnapshot
        lastError       = $Job.lastError
        result          = $Job.result
        worker          = [PSCustomObject]@{
            id             = $workerId
            ownerWorkerId  = [string]$Job.ownerWorkerId
            lastWorkerId   = if (@($Job.PSObject.Properties | Where-Object { $_.Name -eq 'lastWorkerId' }).Count -gt 0) { [string]$Job.lastWorkerId } else { $null }
            heartbeatAtUtc = [string]$Job.heartbeatAtUtc
            leaseUntilUtc  = [string]$Job.leaseUntilUtc
            leaseExpired   = [bool]($leaseUntil -and [string]$Job.status -eq 'Running' -and $leaseUntil -le $now)
            logPath        = $workerLogPath
        }
        paths           = [PSCustomObject]@{
            progressStatePath = $progressStatePath
            resumeStatePath   = $resumeStatePath
            controlStatePath  = $controlStatePath
            chunkIndexStatePath = $chunkIndexStatePath
        }
        logs            = if ($IncludeLogs) { @(Read-RenderKitWorkerLogTail -LogPath $workerLogPath -Tail $Tail) } else { @() }
    }
}

function Get-RenderKitWorkerStatusSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$State,
        [switch]$IncludeLogs,
        [ValidateRange(1, 1000)]
        [int]$Tail = 50
    )

    $alive = Test-RenderKitWorkerProcessAlive `
        -ProcessId ([int]$State.processId) `
        -MachineName ([string]$State.machine)
    $logPath = if (-not [string]::IsNullOrWhiteSpace([string]$State.logPath)) {
        [string]$State.logPath
    }
    else {
        Get-RenderKitWorkerLogPath -WorkerId ([string]$State.workerId)
    }

    return [PSCustomObject]@{
        workerId       = [string]$State.workerId
        status         = [string]$State.status
        jobType        = [string]$State.jobType
        queueName      = [string]$State.queueName
        processId      = [int]$State.processId
        machine        = [string]$State.machine
        processAlive   = [bool]$alive
        startedAtUtc   = [string]$State.startedAtUtc
        updatedAtUtc   = [string]$State.updatedAtUtc
        heartbeatAtUtc = [string]$State.heartbeatAtUtc
        stoppedAtUtc   = [string]$State.stoppedAtUtc
        processedCount = [int]$State.processedCount
        idleTickCount  = [int]$State.idleTickCount
        recoveredJobIds = @($State.recoveredJobIds)
        lastTick       = $State.lastTick
        lastError      = $State.lastError
        statePath      = Get-RenderKitWorkerStatePath -WorkerId ([string]$State.workerId)
        logPath        = $logPath
        logs           = if ($IncludeLogs) { @(Read-RenderKitWorkerLogTail -LogPath $logPath -Tail $Tail) } else { @() }
    }
}

function Invoke-RenderKitLocalWorkerLoop {
    [CmdletBinding()]
    param(
        [string]$WorkerId,
        [string]$JobType = 'BackupProject',
        [string]$QueueName = 'backup',
        [ValidateRange(1, 3600)]
        [int]$PollIntervalSeconds = 5,
        [ValidateRange(1, 86400)]
        [int]$LeaseSeconds = 300,
        [ValidateRange(0, 1000000)]
        [int]$MaxJobs = 0,
        [switch]$RunOnce,
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
    $state = New-RenderKitWorkerState `
        -WorkerId $normalizedWorkerId `
        -JobType $JobType `
        -QueueName $QueueName `
        -LogPath $LogPath `
        -Status Running
    Save-RenderKitWorkerState -State $state | Out-Null
    Write-RenderKitWorkerLogEntry `
        -WorkerId $normalizedWorkerId `
        -LogPath $LogPath `
        -Message ("Worker started for jobType='{0}', queue='{1}'." -f $JobType, $QueueName) |
        Out-Null

    $processedCount = 0
    $idleTickCount = 0
    $recoveredJobIds = New-Object System.Collections.Generic.List[string]
    $lastTick = $null

    try {
        while ($true) {
            $tick = Invoke-RenderKitWorkerTick `
                -WorkerId $normalizedWorkerId `
                -JobType $JobType `
                -QueueName $QueueName `
                -LeaseSeconds $LeaseSeconds
            $lastTick = $tick
            foreach ($jobId in @($tick.RecoveredJobIds)) {
                $recoveredJobIds.Add([string]$jobId)
            }

            if ($tick.Processed) {
                $processedCount++
                Write-RenderKitWorkerLogEntry `
                    -WorkerId $normalizedWorkerId `
                    -LogPath $LogPath `
                    -JobId ([string]$tick.ClaimedJob.id) `
                    -Message ("Processed job '{0}' with status '{1}'." -f [string]$tick.ClaimedJob.id, [string]$tick.ResultJob.status) |
                    Out-Null
            }
            else {
                $idleTickCount++
                if (@($tick.RecoveredJobIds).Count -gt 0) {
                    Write-RenderKitWorkerLogEntry `
                        -WorkerId $normalizedWorkerId `
                        -LogPath $LogPath `
                        -Level Warning `
                        -Message ("Recovered stale running job(s): {0}." -f (@($tick.RecoveredJobIds) -join ', ')) |
                        Out-Null
                }
            }

            $state = New-RenderKitWorkerState `
                -WorkerId $normalizedWorkerId `
                -JobType $JobType `
                -QueueName $QueueName `
                -LogPath $LogPath `
                -Status $(if ($tick.Processed) { 'Running' } else { 'Idle' }) `
                -ProcessedCount $processedCount `
                -IdleTickCount $idleTickCount `
                -RecoveredJobIds @($recoveredJobIds.ToArray()) `
                -LastTick $tick `
                -StartedAtUtc ([string]$state.startedAtUtc)
            Save-RenderKitWorkerState -State $state | Out-Null

            if ($RunOnce -or ($MaxJobs -gt 0 -and $processedCount -ge $MaxJobs)) {
                break
            }

            Start-Sleep -Seconds $PollIntervalSeconds
        }

        $state.status = 'Stopped'
        $state.stoppedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        Save-RenderKitWorkerState -State $state | Out-Null
        Write-RenderKitWorkerLogEntry `
            -WorkerId $normalizedWorkerId `
            -LogPath $LogPath `
            -Message ("Worker stopped after processing {0} job(s)." -f $processedCount) |
            Out-Null

        return [PSCustomObject]@{
            workerId             = $normalizedWorkerId
            status               = 'Stopped'
            processedCount       = $processedCount
            idleTickCount        = $idleTickCount
            recoveredJobIds      = @($recoveredJobIds.ToArray())
            crashDetectedAtStart = [bool]$crashRecovery.crashDetected
            lastTick             = $lastTick
            statePath            = Get-RenderKitWorkerStatePath -WorkerId $normalizedWorkerId
            logPath              = $LogPath
            detached             = $false
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
            -Level Error `
            -Message $_.Exception.Message |
            Out-Null
        throw
    }
}
