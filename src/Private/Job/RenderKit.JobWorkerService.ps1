function New-RenderKitJobHandlerRegistration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobType,
        [Parameter(Mandatory)]
        [scriptblock]$Handler,
        [string]$HandlerId,
        [string]$Version = '1.0',
        [string]$Description,
        [object]$PayloadSchema,
        [bool]$SupportsCancellation = $false,
        [bool]$SupportsProgress = $false,
        [bool]$IsIdempotent = $false,
        [string[]]$RequiredCapabilities
    )

    if ([string]::IsNullOrWhiteSpace($HandlerId)) {
        $HandlerId = $JobType
    }
    if ([string]::IsNullOrWhiteSpace($Version)) {
        $Version = '1.0'
    }

    $capabilities = @()
    if ($RequiredCapabilities) {
        $capabilities = @($RequiredCapabilities)
    }

    return [PSCustomObject]@{
        jobType              = $JobType
        handlerId            = $HandlerId
        version              = $Version
        description          = $Description
        payloadSchema        = $PayloadSchema
        supportsCancellation = $SupportsCancellation
        supportsProgress     = $SupportsProgress
        isIdempotent         = $IsIdempotent
        requiredCapabilities = $capabilities
        handler              = $Handler
        registeredAtUtc      = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Register-RenderKitJobHandler {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobType,
        [Parameter(Mandatory)]
        [scriptblock]$Handler,
        [string]$HandlerId,
        [string]$Version = '1.0',
        [string]$Description,
        [object]$PayloadSchema,
        [switch]$SupportsCancellation,
        [switch]$SupportsProgress,
        [switch]$IsIdempotent,
        [string[]]$RequiredCapabilities
    )

    $handlerRegistry = Get-Variable -Name RenderKitJobHandlers -Scope Script -ErrorAction SilentlyContinue
    if (-not $handlerRegistry -or -not $handlerRegistry.Value) {
        $script:RenderKitJobHandlers = @{}
    }

    $script:RenderKitJobHandlers[$JobType] = New-RenderKitJobHandlerRegistration `
        -JobType $JobType `
        -Handler $Handler `
        -HandlerId $HandlerId `
        -Version $Version `
        -Description $Description `
        -PayloadSchema $PayloadSchema `
        -SupportsCancellation ([bool]$SupportsCancellation) `
        -SupportsProgress ([bool]$SupportsProgress) `
        -IsIdempotent ([bool]$IsIdempotent) `
        -RequiredCapabilities $RequiredCapabilities
}

function Get-RenderKitJobHandlerRegistration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobType
    )

    $handlerRegistry = Get-Variable -Name RenderKitJobHandlers -Scope Script -ErrorAction SilentlyContinue
    if (-not $handlerRegistry -or -not $handlerRegistry.Value) {
        $script:RenderKitJobHandlers = @{}
    }

    if (-not $script:RenderKitJobHandlers.ContainsKey($JobType)) {
        return $null
    }

    $registration = $script:RenderKitJobHandlers[$JobType]
    if ($registration -is [scriptblock]) {
        return New-RenderKitJobHandlerRegistration `
            -JobType $JobType `
            -Handler $registration
    }

    return $registration
}

function Get-RenderKitJobHandler {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobType
    )

    $registration = Get-RenderKitJobHandlerRegistration -JobType $JobType
    if (-not $registration) {
        return $null
    }

    return $registration.handler
}

function Get-RenderKitJobHandlerCatalog {
    [CmdletBinding()]
    param(
        [string]$JobType
    )

    $handlerRegistry = Get-Variable -Name RenderKitJobHandlers -Scope Script -ErrorAction SilentlyContinue
    if (-not $handlerRegistry -or -not $handlerRegistry.Value) {
        $script:RenderKitJobHandlers = @{}
    }

    $registrations = foreach ($key in @($script:RenderKitJobHandlers.Keys | Sort-Object)) {
        if (-not [string]::IsNullOrWhiteSpace($JobType) -and [string]$key -ne $JobType) {
            continue
        }
        $registration = Get-RenderKitJobHandlerRegistration -JobType ([string]$key)
        if ($registration) {
            [PSCustomObject]@{
                jobType              = [string]$registration.jobType
                handlerId            = [string]$registration.handlerId
                version              = [string]$registration.version
                description          = [string]$registration.description
                payloadSchema        = $registration.payloadSchema
                supportsCancellation = [bool]$registration.supportsCancellation
                supportsProgress     = [bool]$registration.supportsProgress
                isIdempotent         = [bool]$registration.isIdempotent
                requiredCapabilities = @($registration.requiredCapabilities)
                registeredAtUtc      = [string]$registration.registeredAtUtc
            }
        }
    }

    return @($registrations)
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
function Fail-RenderKitJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,

        [string]$ErrorMessage,

        [string]$ErrorCode = 'RK_INTERNAL_ERROR'
    )

    $job = Get-RenderKitJobById -JobId $JobId
    if (-not $job) {
        throw "RenderKit job '$JobId' was not found."
    }

    $maxAttempts = [int]$job.maxAttempts
    if ($maxAttempts -le 0) {
        $maxAttempts = 1
    }

    if ([int]$job.attempts -lt $maxAttempts) {
        Set-RenderKitJobStatus `
            -JobId $JobId `
            -Status Failed `
            -ErrorMessage $ErrorMessage `
            -ErrorCode $ErrorCode
        Reset-RenderKitJobForRetry -JobId $JobId | Out-Null
    }
    else {
        Set-RenderKitJobStatus `
            -JobId $JobId `
            -Status Failed `
            -ErrorMessage $ErrorMessage `
            -ErrorCode $ErrorCode
    }

    return Get-RenderKitJobById -JobId $JobId
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
        if ($currentJob -and [string]$currentJob.status -eq 'Cancelled') {
            return $currentJob
        }
        return Complete-RenderKitJob -JobId $JobId
    }
    catch {
        $currentJob = Get-RenderKitJobById -JobId $JobId
        if ($currentJob -and [string]$currentJob.status -eq 'Cancelled') {
            return $currentJob
        }
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

function Invoke-RenderKitWorkerTick {
    [CmdletBinding()]
    param(
        [string]$WorkerId,
        [string]$JobType,
        [string]$QueueName,
        [ValidateRange(1, 86400)]
        [int]$LeaseSeconds = 300
    )

    $normalizedWorkerId = New-RenderKitWorkerId -WorkerId $WorkerId
    $recovery = Reset-RenderKitStaleRunningJob
    $claimed = Start-RenderKitQueuedJobLease `
        -WorkerId $normalizedWorkerId `
        -JobType $JobType `
        -QueueName $QueueName `
        -LeaseSeconds $LeaseSeconds

    if (-not $claimed) {
        return [PSCustomObject]@{
            WorkerId = $normalizedWorkerId
            ClaimedJob = $null
            ResultJob = $null
            RecoveredJobIds = @($recovery.RecoveredJobIds)
            Processed = $false
        }
    }

    $result = Invoke-RenderKitJob -JobId ([string]$claimed.id)
    return [PSCustomObject]@{
        WorkerId = $normalizedWorkerId
        ClaimedJob = $claimed
        ResultJob = $result
        RecoveredJobIds = @($recovery.RecoveredJobIds)
        Processed = $true
    }
}

function Initialize-RenderKitDefaultJobHandlers {
    [CmdletBinding()]
    param()

    Register-RenderKitJobHandler `
        -JobType 'ProjectLifecycleAutomation' `
        -HandlerId 'RenderKit.ProjectLifecycleAutomation' `
        -Version '1.0' `
        -Description 'Safe placeholder for future project lifecycle automation.' `
        -SupportsProgress `
        -IsIdempotent `
        -Handler {
            param($Job)
            # $logger = Get-Command -Name Write-RenderKitLog -ErrorAction SilentlyContinue
            # if ($logger) {
            #     Write-RenderKitLog `
            #         -Level Debug `
            #         -Message "Processed ProjectLifecycleAutomation job '$($Job.id)'."
            # }
            # Intentionally no-op until lifecycle automation is implemented.
            # Keep the placeholder independent from optional logging helpers so
            # it can run in focused tests and minimal host integrations.
        }

    Register-RenderKitJobHandler `
        -JobType 'BackupProject' `
        -HandlerId 'RenderKit.BackupProject' `
        -Version '1.0' `
        -Description 'Plans and executes the resumable Backup-Project worker pipeline.' `
        -SupportsProgress `
        -SupportsCancellation `
        -IsIdempotent `
        -RequiredCapabilities @('local-files', 'ffmpeg-optional') `
        -Handler {
            param($Job)

            $result = Invoke-BackupProjectJob -Job $Job
            Set-RenderKitJobResult `
                -JobId ([string]$Job.id) `
                -Result $result |
                Out-Null
        }
}

Initialize-RenderKitDefaultJobHandlers
