function Get-RenderKitJobStoreSchemaVersion {
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    return '1.1'
}

function Get-RenderKitJobStatusCatalog {
    [CmdletBinding()]
    param()

    return @(
        [PSCustomObject]@{ Name = 'Queued'; Terminal = $false; Description = 'The job is waiting for a worker.' }
        [PSCustomObject]@{ Name = 'Running'; Terminal = $false; Description = 'The job is currently owned by a worker.' }
        [PSCustomObject]@{ Name = 'RetryScheduled'; Terminal = $false; Description = 'The job failed but is scheduled for a later retry.' }
        [PSCustomObject]@{ Name = 'Succeeded'; Terminal = $true; Description = 'The job completed successfully.' }
        [PSCustomObject]@{ Name = 'Failed'; Terminal = $true; Description = 'The job exhausted retries or failed permanently.' }
        [PSCustomObject]@{ Name = 'Cancelled'; Terminal = $true; Description = 'The job was cancelled.' }
    )
}

function Test-RenderKitJobStatus {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory)]
        [string]$Status
    )

    return [bool](@(Get-RenderKitJobStatusCatalog | Where-Object {
        [string]$_.Name -eq $Status
    }).Count -gt 0)
}

function Test-RenderKitJobStatusTransition {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory)]
        [string]$FromStatus,
        [Parameter(Mandatory)]
        [string]$ToStatus
    )

    if (-not (Test-RenderKitJobStatus -Status $FromStatus) -or
        -not (Test-RenderKitJobStatus -Status $ToStatus)) {
        return $false
    }

    if ($FromStatus -eq $ToStatus) {
        return $true
    }

    $allowedTransitions = @{
        Queued = @('Running', 'Failed', 'Cancelled')
        Running = @('Queued', 'RetryScheduled', 'Succeeded', 'Failed', 'Cancelled')
        RetryScheduled = @('Queued', 'Cancelled')
        Succeeded = @()
        Failed = @('Queued')
        Cancelled = @()
    }

    return [bool]($allowedTransitions[$FromStatus] -contains $ToStatus)
}

function Set-RenderKitObjectProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,
        [Parameter(Mandatory)]
        [string]$Name,
        [object]$Value
    )

    $InputObject | Add-Member `
        -NotePropertyName $Name `
        -NotePropertyValue $Value `
        -Force
}

function New-RenderKitJobProgress {
    [CmdletBinding()]
    param(
        [string]$Phase = 'Queued',
        [string]$Message,
        [int]$Current = 0,
        [int]$Total = 0,
        [Nullable[double]]$Percent
    )

    if ($null -eq $Percent -and $Total -gt 0) {
        $Percent = [math]::Round(($Current / $Total) * 100, 2)
    }

    return [PSCustomObject]@{
        phase        = $Phase
        message      = $Message
        current      = $Current
        total        = $Total
        percent      = $Percent
        updatedAtUtc = $null
    }
}

function New-RenderKitJobError {
    [CmdletBinding()]
    param(
        [string]$Code = 'RK_INTERNAL_ERROR',
        [Parameter(Mandatory)]
        [string]$Message,
        [object]$Details,
        [int]$Attempt = 0
    )

    return [PSCustomObject]@{
        code          = $Code
        message       = $Message
        details       = $Details
        attempt       = $Attempt
        occurredAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function New-RenderKitJobStore {
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        tool          = 'RenderKit'
        schemaVersion = Get-RenderKitJobStoreSchemaVersion
        updatedAtUtc  = (Get-Date).ToUniversalTime().ToString('o')
        jobs          = @()
    }
}

function Test-RenderKitJobStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Store
    )

    if ($Store.tool -ne 'RenderKit') {
        return $false
    }
    if ([string]::IsNullOrWhiteSpace([string]$Store.schemaVersion)) {
        return $false
    }

    $compatibility = Test-RenderKitArtifactCompatibility `
        -ArtifactType JobStore `
        -Version ([string]$Store.schemaVersion)

    return [bool]($compatibility.CanRead -and $compatibility.CanWrite)
}

function ConvertTo-RenderKitJobVNext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Job
    )

    $now = (Get-Date).ToUniversalTime().ToString('o')

    if ([string]::IsNullOrWhiteSpace([string]$Job.id)) {
        Set-RenderKitObjectProperty -InputObject $Job -Name id -Value ([guid]::NewGuid().ToString())
    }
    if ([string]::IsNullOrWhiteSpace([string]$Job.status)) {
        Set-RenderKitObjectProperty -InputObject $Job -Name status -Value 'Queued'
    }
    if (-not (Test-RenderKitJobStatus -Status ([string]$Job.status))) {
        throw "RenderKit job '$($Job.id)' has unsupported status '$($Job.status)'."
    }
    if ([string]::IsNullOrWhiteSpace([string]$Job.createdAtUtc)) {
        Set-RenderKitObjectProperty -InputObject $Job -Name createdAtUtc -Value $now
    }
    if ([string]::IsNullOrWhiteSpace([string]$Job.updatedAtUtc)) {
        Set-RenderKitObjectProperty -InputObject $Job -Name updatedAtUtc -Value $now
    }
    if ($null -eq $Job.attempts) {
        Set-RenderKitObjectProperty -InputObject $Job -Name attempts -Value 0
    }
    if ($null -eq $Job.maxAttempts) {
        Set-RenderKitObjectProperty -InputObject $Job -Name maxAttempts -Value 3
    }
    if ([string]::IsNullOrWhiteSpace([string]$Job.correlationId)) {
        Set-RenderKitObjectProperty -InputObject $Job -Name correlationId -Value ([guid]::NewGuid().ToString())
    }
    if ($null -eq $Job.payload) {
        Set-RenderKitObjectProperty -InputObject $Job -Name payload -Value ([PSCustomObject]@{})
    }

    $propertyDefaults = @{
        jobSchemaVersion = '1.1'
        payloadSchemaVersion = '1.0'
        ownerWorkerId = $null
        leaseUntilUtc = $null
        claimedAtUtc = $null
        heartbeatAtUtc = $null
        retryAfterUtc = $null
        cancelRequestedAtUtc = $null
        cancelReason = $null
        priority = 0
        queueName = 'default'
        requestedBy = $null
        result = $null
    }

    foreach ($key in $propertyDefaults.Keys) {
        if (-not ($Job.PSObject.Properties.Name -contains $key)) {
            Set-RenderKitObjectProperty `
                -InputObject $Job `
                -Name $key `
                -Value $propertyDefaults[$key]
        }
    }

    if (-not ($Job.PSObject.Properties.Name -contains 'progress') -or
        $null -eq $Job.progress) {
        Set-RenderKitObjectProperty `
            -InputObject $Job `
            -Name progress `
            -Value (New-RenderKitJobProgress -Phase ([string]$Job.status))
    }

    if ($Job.lastError -is [string]) {
        if ([string]::IsNullOrWhiteSpace([string]$Job.lastError)) {
            Set-RenderKitObjectProperty -InputObject $Job -Name lastError -Value $null
        }
        else {
            Set-RenderKitObjectProperty `
                -InputObject $Job `
                -Name lastError `
                -Value (New-RenderKitJobError `
                    -Message ([string]$Job.lastError) `
                    -Attempt ([int]$Job.attempts))
        }
    }
    elseif (-not ($Job.PSObject.Properties.Name -contains 'lastError')) {
        Set-RenderKitObjectProperty -InputObject $Job -Name lastError -Value $null
    }

    return $Job
}

function ConvertTo-RenderKitJobStoreVNext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Store
    )

    if (-not ($Store.PSObject.Properties.Name -contains 'jobs') -or
        $null -eq $Store.jobs) {
        Set-RenderKitObjectProperty `
            -InputObject $Store `
            -Name jobs `
            -Value @()
    }

    $normalizedJobs = @()
    foreach ($job in @($Store.jobs)) {
        $normalizedJobs += ConvertTo-RenderKitJobVNext -Job $job
    }

    Set-RenderKitObjectProperty `
        -InputObject $Store `
        -Name schemaVersion `
        -Value (Get-RenderKitJobStoreSchemaVersion)
    Set-RenderKitObjectProperty `
        -InputObject $Store `
        -Name jobs `
        -Value $normalizedJobs

    return $Store
}

function Read-RenderKitJobStore {
    [CmdletBinding()]
    param()

    $path = Get-RenderKitJobStorePath
    $store = Read-RenderKitJsonFile `
        -Path $path `
        -AllowMissing `
        -Validator { param($value) Test-RenderKitJobStore $value }

    if (-not $store) {
        return New-RenderKitJobStore
    }

    return ConvertTo-RenderKitJobStoreVNext -Store $store
}

function New-RenderKitJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobType,
        [object]$Payload,
        [string]$TriggerEventId,
        [string]$CorrelationId,
        [string]$PayloadSchemaVersion = '1.0',
        [string]$QueueName = 'default',
        [int]$Priority = 0,
        [object]$RequestedBy
    )

    if ([string]::IsNullOrWhiteSpace($CorrelationId)) {
        $CorrelationId = [guid]::NewGuid().ToString()
    }

    if ([string]::IsNullOrWhiteSpace($PayloadSchemaVersion)) {
        $PayloadSchemaVersion = '1.0'
    }
    if ([string]::IsNullOrWhiteSpace($QueueName)) {
        $QueueName = 'default'
    }

    $now = (Get-Date).ToUniversalTime().ToString('o')
    return [PSCustomObject]@{
        id                   = [guid]::NewGuid().ToString()
        jobType              = $JobType
        jobSchemaVersion     = '1.1'
        payloadSchemaVersion = $PayloadSchemaVersion
        status               = 'Queued'
        queueName            = $QueueName
        priority             = $Priority
        createdAtUtc         = $now
        updatedAtUtc         = $now
        startedAtUtc         = $null
        completedAtUtc       = $null
        attempts             = 0
        maxAttempts          = 3
        ownerWorkerId        = $null
        leaseUntilUtc        = $null
        claimedAtUtc         = $null
        heartbeatAtUtc       = $null
        retryAfterUtc        = $null
        cancelRequestedAtUtc = $null
        cancelReason         = $null
        triggerEventId       = $TriggerEventId
        correlationId        = $CorrelationId
        requestedBy          = $RequestedBy
        progress             = New-RenderKitJobProgress -Phase 'Queued'
        lastError            = $null
        result               = $null
        payload              = $Payload
    }
}

function Add-RenderKitJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Job
    )

    $normalizedJob = ConvertTo-RenderKitJobVNext -Job $Job
    $path = Get-RenderKitJobStorePath
    Invoke-RenderKitJsonFileTransaction `
        -Path $path `
        -DefaultValue (New-RenderKitJobStore) `
        -Depth 30 `
        -Validator { param($value) Test-RenderKitJobStore $value } `
        -Update {
            param($store)

            $store = ConvertTo-RenderKitJobStoreVNext -Store $store
            $store.jobs = @($store.jobs) + @($normalizedJob)
            $store.updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            return $store
        } |
        Out-Null

    return $normalizedJob
}

function Get-RenderKitJobList {
    [CmdletBinding()]
    param(
        [string]$Status,
        [string]$JobType,
        [string]$QueueName,
        [string]$CorrelationId
    )

    if (-not [string]::IsNullOrWhiteSpace($Status) -and
        -not (Test-RenderKitJobStatus -Status $Status)) {
        throw "RenderKit job status '$Status' is not supported."
    }

    $store = Read-RenderKitJobStore
    $jobs = @($store.jobs)
    if (-not [string]::IsNullOrWhiteSpace($Status)) {
        $jobs = @($jobs | Where-Object { [string]$_.status -eq $Status })
    }
    if (-not [string]::IsNullOrWhiteSpace($JobType)) {
        $jobs = @($jobs | Where-Object { [string]$_.jobType -eq $JobType })
    }
    if (-not [string]::IsNullOrWhiteSpace($QueueName)) {
        $jobs = @($jobs | Where-Object { [string]$_.queueName -eq $QueueName })
    }
    if (-not [string]::IsNullOrWhiteSpace($CorrelationId)) {
        $jobs = @($jobs | Where-Object { [string]$_.correlationId -eq $CorrelationId })
    }

    return @($jobs | Sort-Object `
            @{ Expression = 'priority'; Descending = $true },
            createdAtUtc,
            id)
}

function Get-RenderKitJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId
    )

    return @(Get-RenderKitJobList | Where-Object {
        [string]$_.id -eq $JobId
    } | Select-Object -First 1)
}

function Get-RenderKitQueuedJob {
    [CmdletBinding()]
    param(
        [string]$JobType
    )

    return Get-RenderKitJobList -Status Queued -JobType $JobType
}

function Set-RenderKitJobStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [Parameter(Mandatory)]
        [ValidateSet('Queued', 'Running', 'RetryScheduled', 'Succeeded', 'Failed', 'Cancelled')]
        [string]$Status,
        [string]$ErrorMessage,
        [string]$ErrorCode = 'RK_INTERNAL_ERROR',
        [Nullable[DateTime]]$RetryAfterUtc
    )

    $path = Get-RenderKitJobStorePath
    Invoke-RenderKitJsonFileTransaction `
        -Path $path `
        -DefaultValue (New-RenderKitJobStore) `
        -Depth 30 `
        -Validator { param($value) Test-RenderKitJobStore $value } `
        -Update {
            param($store)

            $store = ConvertTo-RenderKitJobStoreVNext -Store $store
            $found = $false
            foreach ($job in @($store.jobs)) {
                if ([string]$job.id -eq $JobId) {
                    if (-not (Test-RenderKitJobStatusTransition `
                            -FromStatus ([string]$job.status) `
                            -ToStatus $Status)) {
                        throw "RenderKit job '$JobId' cannot transition from '$($job.status)' to '$Status'."
                    }

                    $now = (Get-Date).ToUniversalTime().ToString('o')
                    $job.status = $Status
                    $job.updatedAtUtc = $now
                    if ($Status -eq 'Running') {
                        $job.startedAtUtc = $now
                        $job.attempts = [int]$job.attempts + 1
                        $job.claimedAtUtc = $now
                        $job.heartbeatAtUtc = $now
                        $job.retryAfterUtc = $null
                    }
                    if ($Status -eq 'Queued') {
                        $job.ownerWorkerId = $null
                        $job.leaseUntilUtc = $null
                        $job.claimedAtUtc = $null
                        $job.heartbeatAtUtc = $null
                        $job.retryAfterUtc = $null
                    }
                    if ($Status -eq 'RetryScheduled') {
                        if ($null -ne $RetryAfterUtc) {
                            $job.retryAfterUtc = ([DateTime]$RetryAfterUtc).ToUniversalTime().ToString('o')
                        }
                        elseif ([string]::IsNullOrWhiteSpace([string]$job.retryAfterUtc)) {
                            $job.retryAfterUtc = $now
                        }
                    }
                    if ($Status -in @('Succeeded', 'Failed', 'Cancelled')) {
                        $job.completedAtUtc = $now
                        $job.ownerWorkerId = $null
                        $job.leaseUntilUtc = $null
                    }
                    if ($Status -eq 'Cancelled' -and
                        [string]::IsNullOrWhiteSpace([string]$job.cancelRequestedAtUtc)) {
                        $job.cancelRequestedAtUtc = $now
                    }
                    if ($Status -eq 'Failed') {
                        if ([string]::IsNullOrWhiteSpace($ErrorMessage)) {
                            $ErrorMessage = 'The RenderKit job failed.'
                        }
                        $job.lastError = New-RenderKitJobError `
                            -Code $ErrorCode `
                            -Message $ErrorMessage `
                            -Attempt ([int]$job.attempts)
                    }
                    elseif ($Status -ne 'RetryScheduled') {
                        $job.lastError = $null
                    }
                    if ($job.progress) {
                        $job.progress.phase = $Status
                        $job.progress.updatedAtUtc = $now
                    }
                    $found = $true
                    break
                }
            }
            if (-not $found) {
                throw "RenderKit job '$JobId' was not found."
            }

            $store.updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            return $store
        } |
        Out-Null
}

function Start-RenderKitQueuedJob {
    [CmdletBinding()]
    param(
        [string]$JobType
    )

    $job = @(Get-RenderKitQueuedJob -JobType $JobType | Select-Object -First 1)
    if ($job.Count -eq 0) {
        return $null
    }

    Set-RenderKitJobStatus `
        -JobId ([string]$job[0].id) `
        -Status Running

    return Get-RenderKitJob -JobId ([string]$job[0].id)
}

function Update-RenderKitJobProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [string]$Phase,
        [string]$Message,
        [int]$Current = 0,
        [int]$Total = 0,
        [Nullable[double]]$Percent
    )

    $path = Get-RenderKitJobStorePath
    Invoke-RenderKitJsonFileTransaction `
        -Path $path `
        -DefaultValue (New-RenderKitJobStore) `
        -Depth 30 `
        -Validator { param($value) Test-RenderKitJobStore $value } `
        -Update {
            param($store)

            $store = ConvertTo-RenderKitJobStoreVNext -Store $store
            $found = $false
            foreach ($job in @($store.jobs)) {
                if ([string]$job.id -eq $JobId) {
                    if ($job.status -in @('Succeeded', 'Failed', 'Cancelled')) {
                        throw "RenderKit job '$JobId' is terminal and cannot report progress."
                    }
                    $progressPhase = $Phase
                    if ([string]::IsNullOrWhiteSpace($progressPhase)) {
                        $progressPhase = [string]$job.status
                    }
                    $job.progress = New-RenderKitJobProgress `
                        -Phase $progressPhase `
                        -Message $Message `
                        -Current $Current `
                        -Total $Total `
                        -Percent $Percent
                    $job.progress.updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
                    $job.updatedAtUtc = $job.progress.updatedAtUtc
                    $found = $true
                    break
                }
            }
            if (-not $found) {
                throw "RenderKit job '$JobId' was not found."
            }

            $store.updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            return $store
        } |
        Out-Null

    return Get-RenderKitJob -JobId $JobId
}

function Set-RenderKitJobResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [object]$Result
    )

    $path = Get-RenderKitJobStorePath
    Invoke-RenderKitJsonFileTransaction `
        -Path $path `
        -DefaultValue (New-RenderKitJobStore) `
        -Depth 30 `
        -Validator { param($value) Test-RenderKitJobStore $value } `
        -Update {
            param($store)

            $store = ConvertTo-RenderKitJobStoreVNext -Store $store
            $found = $false
            foreach ($job in @($store.jobs)) {
                if ([string]$job.id -eq $JobId) {
                    $job.result = $Result
                    $job.updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
                    $found = $true
                    break
                }
            }
            if (-not $found) {
                throw "RenderKit job '$JobId' was not found."
            }

            $store.updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            return $store
        } |
        Out-Null

    return Get-RenderKitJob -JobId $JobId
}

function Request-RenderKitJobCancellation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [string]$Reason,
        [object]$RequestedBy
    )

    $path = Get-RenderKitJobStorePath
    Invoke-RenderKitJsonFileTransaction `
        -Path $path `
        -DefaultValue (New-RenderKitJobStore) `
        -Depth 30 `
        -Validator { param($value) Test-RenderKitJobStore $value } `
        -Update {
            param($store)

            $store = ConvertTo-RenderKitJobStoreVNext -Store $store
            $found = $false
            foreach ($job in @($store.jobs)) {
                if ([string]$job.id -eq $JobId) {
                    if ($job.status -in @('Succeeded', 'Failed', 'Cancelled')) {
                        throw "RenderKit job '$JobId' is terminal and cannot be cancelled."
                    }

                    $now = (Get-Date).ToUniversalTime().ToString('o')
                    $job.cancelRequestedAtUtc = $now
                    $job.cancelReason = $Reason
                    $job.requestedBy = $RequestedBy
                    $job.updatedAtUtc = $now
                    if ($job.status -in @('Queued', 'RetryScheduled')) {
                        $job.status = 'Cancelled'
                        $job.completedAtUtc = $now
                        if ($job.progress) {
                            $job.progress.phase = 'Cancelled'
                            $job.progress.updatedAtUtc = $now
                        }
                    }
                    $found = $true
                    break
                }
            }
            if (-not $found) {
                throw "RenderKit job '$JobId' was not found."
            }

            $store.updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            return $store
        } |
        Out-Null

    return Get-RenderKitJob -JobId $JobId
}

function Reset-RenderKitJobForRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId
    )

    $job = Get-RenderKitJob -JobId $JobId
    if (-not $job) {
        throw "RenderKit job '$JobId' was not found."
    }
    if ([string]$job.status -notin @('Failed', 'RetryScheduled')) {
        throw "RenderKit job '$JobId' cannot be retried from '$($job.status)'."
    }

    Set-RenderKitJobStatus -JobId $JobId -Status Queued
    return Get-RenderKitJob -JobId $JobId
}

function New-RenderKitWorkerId {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [string]$WorkerId
    )

    if ([string]::IsNullOrWhiteSpace($WorkerId)) {
        return "worker-$([guid]::NewGuid().ToString('N'))"
    }

    return $WorkerId
}

function ConvertTo-RenderKitUtcDateTime {
    [CmdletBinding()]
    [OutputType([System.Nullable[DateTime]])]
    param(
        [object]$Value
    )

    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [DateTime]) {
        return ([DateTime]$Value).ToUniversalTime()
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    $parsed = [DateTime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::RoundtripKind -bor
        [System.Globalization.DateTimeStyles]::AssumeUniversal
    if ([DateTime]::TryParse(
            $text,
            [System.Globalization.CultureInfo]::InvariantCulture,
            $styles,
            [ref]$parsed)) {
        return $parsed.ToUniversalTime()
    }
    if ([DateTime]::TryParse($text, [ref]$parsed)) {
        return $parsed.ToUniversalTime()
    }

    return $null
}

function Start-RenderKitQueuedJobLease {
    [CmdletBinding()]
    param(
        [string]$WorkerId,
        [string]$JobType,
        [string]$QueueName,
        [ValidateRange(1, 86400)]
        [int]$LeaseSeconds = 300
    )

    $normalizedWorkerId = New-RenderKitWorkerId -WorkerId $WorkerId
    $claimState = [PSCustomObject]@{ JobId = $null }
    $path = Get-RenderKitJobStorePath
    Invoke-RenderKitJsonFileTransaction `
        -Path $path `
        -DefaultValue (New-RenderKitJobStore) `
        -Depth 30 `
        -Validator { param($value) Test-RenderKitJobStore $value } `
        -Update {
            param($store)

            $store = ConvertTo-RenderKitJobStoreVNext -Store $store
            $candidates = @($store.jobs | Where-Object {
                [string]$_.status -eq 'Queued' -and
                ([string]::IsNullOrWhiteSpace($JobType) -or [string]$_.jobType -eq $JobType) -and
                ([string]::IsNullOrWhiteSpace($QueueName) -or [string]$_.queueName -eq $QueueName)
            } | Sort-Object `
                @{ Expression = 'priority'; Descending = $true },
                createdAtUtc,
                id)

            if ($candidates.Count -eq 0) {
                return $store
            }

            $job = $candidates[0]
            $now = (Get-Date).ToUniversalTime()
            $job.status = 'Running'
            $job.updatedAtUtc = $now.ToString('o')
            $job.startedAtUtc = $now.ToString('o')
            $job.claimedAtUtc = $now.ToString('o')
            $job.heartbeatAtUtc = $now.ToString('o')
            $job.leaseUntilUtc = $now.AddSeconds($LeaseSeconds).ToString('o')
            $job.ownerWorkerId = $normalizedWorkerId
            $job.retryAfterUtc = $null
            $job.attempts = [int]$job.attempts + 1
            if ($job.progress) {
                $job.progress.phase = 'Running'
                $job.progress.updatedAtUtc = $now.ToString('o')
            }
            $claimState.JobId = [string]$job.id
            $store.updatedAtUtc = $now.ToString('o')
            return $store
        } |
        Out-Null

    if ([string]::IsNullOrWhiteSpace([string]$claimState.JobId)) {
        return $null
    }

    return Get-RenderKitJob -JobId ([string]$claimState.JobId)
}

function Update-RenderKitJobHeartbeat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [Parameter(Mandatory)]
        [string]$WorkerId,
        [ValidateRange(1, 86400)]
        [int]$LeaseSeconds = 300
    )

    $path = Get-RenderKitJobStorePath
    Invoke-RenderKitJsonFileTransaction `
        -Path $path `
        -DefaultValue (New-RenderKitJobStore) `
        -Depth 30 `
        -Validator { param($value) Test-RenderKitJobStore $value } `
        -Update {
            param($store)

            $store = ConvertTo-RenderKitJobStoreVNext -Store $store
            $found = $false
            foreach ($job in @($store.jobs)) {
                if ([string]$job.id -eq $JobId) {
                    if ([string]$job.status -ne 'Running') {
                        throw "RenderKit job '$JobId' is not running."
                    }
                    if ([string]$job.ownerWorkerId -ne $WorkerId) {
                        throw "RenderKit job '$JobId' is owned by another worker."
                    }
                    $now = (Get-Date).ToUniversalTime()
                    $job.heartbeatAtUtc = $now.ToString('o')
                    $job.leaseUntilUtc = $now.AddSeconds($LeaseSeconds).ToString('o')
                    $job.updatedAtUtc = $now.ToString('o')
                    $found = $true
                    break
                }
            }
            if (-not $found) {
                throw "RenderKit job '$JobId' was not found."
            }

            $store.updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            return $store
        } |
        Out-Null

    return Get-RenderKitJob -JobId $JobId
}

function Reset-RenderKitStaleRunningJob {
    [CmdletBinding()]
    param(
        [DateTime]$NowUtc = (Get-Date).ToUniversalTime()
    )

    $recoveredJobIds = New-Object System.Collections.Generic.List[string]
    $path = Get-RenderKitJobStorePath
    Invoke-RenderKitJsonFileTransaction `
        -Path $path `
        -DefaultValue (New-RenderKitJobStore) `
        -Depth 30 `
        -Validator { param($value) Test-RenderKitJobStore $value } `
        -Update {
            param($store)

            $store = ConvertTo-RenderKitJobStoreVNext -Store $store
            foreach ($job in @($store.jobs)) {
                if ([string]$job.status -ne 'Running' -or
                    [string]::IsNullOrWhiteSpace([string]$job.leaseUntilUtc)) {
                    continue
                }

                $leaseUntil = ConvertTo-RenderKitUtcDateTime `
                    -Value $job.leaseUntilUtc
                if ($null -eq $leaseUntil) {
                    continue
                }
                if ($leaseUntil -gt $NowUtc.ToUniversalTime()) {
                    continue
                }

                $job.status = 'Queued'
                $job.ownerWorkerId = $null
                $job.leaseUntilUtc = $null
                $job.heartbeatAtUtc = $null
                $job.claimedAtUtc = $null
                $job.updatedAtUtc = $NowUtc.ToUniversalTime().ToString('o')
                if ($job.progress) {
                    $job.progress.phase = 'Queued'
                    $job.progress.updatedAtUtc = $job.updatedAtUtc
                }
                $recoveredJobIds.Add([string]$job.id)
            }

            if ($recoveredJobIds.Count -gt 0) {
                $store.updatedAtUtc = $NowUtc.ToUniversalTime().ToString('o')
            }
            return $store
        } |
        Out-Null

    return [PSCustomObject]@{
        RecoveredCount = [int]$recoveredJobIds.Count
        RecoveredJobIds = @($recoveredJobIds.ToArray())
    }
}
