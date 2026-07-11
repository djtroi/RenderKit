function New-RenderKitCorrelationId {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [string]$CorrelationId
    )

    if ([string]::IsNullOrWhiteSpace($CorrelationId)) {
        return [guid]::NewGuid().ToString()
    }

    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($CorrelationId, [ref]$parsed)) {
        throw "RenderKit correlation id '$CorrelationId' is not a valid GUID."
    }

    return $parsed.ToString()
}

function New-RenderKitCausationId {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [string]$CausationId
    )

    if ([string]::IsNullOrWhiteSpace($CausationId)) {
        return $null
    }

    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($CausationId, [ref]$parsed)) {
        throw "RenderKit causation id '$CausationId' is not a valid GUID."
    }

    return $parsed.ToString()
}

function Get-RenderKitErrorCodeCatalog {
    [CmdletBinding()]
    param()

    return @(
        [PSCustomObject]@{ Code = 'RK_VALIDATION_FAILED'; Category = 'Validation'; Description = 'The request failed validation.' }
        [PSCustomObject]@{ Code = 'RK_NOT_FOUND'; Category = 'NotFound'; Description = 'The requested resource was not found.' }
        [PSCustomObject]@{ Code = 'RK_CONFLICT'; Category = 'Conflict'; Description = 'The request conflicts with current state.' }
        [PSCustomObject]@{ Code = 'RK_LOCK_TIMEOUT'; Category = 'Storage'; Description = 'A storage lock could not be acquired in time.' }
        [PSCustomObject]@{ Code = 'RK_STORAGE_UNAVAILABLE'; Category = 'Storage'; Description = 'The required storage location is unavailable.' }
        [PSCustomObject]@{ Code = 'RK_SCHEMA_UNSUPPORTED'; Category = 'Compatibility'; Description = 'The artifact schema is unsupported by this engine.' }
        [PSCustomObject]@{ Code = 'RK_JOB_NOT_FOUND'; Category = 'Job'; Description = 'The requested job was not found.' }
        [PSCustomObject]@{ Code = 'RK_JOB_INVALID_STATE'; Category = 'Job'; Description = 'The requested job transition is not allowed.' }
        [PSCustomObject]@{ Code = 'RK_JOB_HANDLER_NOT_FOUND'; Category = 'Job'; Description = 'No trusted handler is registered for the job type.' }
        [PSCustomObject]@{ Code = 'RK_OPERATION_CANCELLED'; Category = 'Cancellation'; Description = 'The operation was cancelled.' }
        [PSCustomObject]@{ Code = 'RK_ACCESS_CONTEXT_MISSING'; Category = 'AccessContext'; Description = 'The host did not provide the required actor or operation context.' }
        [PSCustomObject]@{ Code = 'RK_INTERNAL_ERROR'; Category = 'Internal'; Description = 'An unexpected engine error occurred.' }
    )
}

function Test-RenderKitErrorCode {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory)]
        [string]$Code
    )

    return [bool](@(Get-RenderKitErrorCodeCatalog | Where-Object {
        [string]$_.Code -eq $Code
    }).Count -gt 0)
}

function New-RenderKitError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Code,
        [Parameter(Mandatory)]
        [string]$Message,
        [object]$Details,
        [string]$Category
    )

    $catalogEntry = @(Get-RenderKitErrorCodeCatalog | Where-Object {
        [string]$_.Code -eq $Code
    } | Select-Object -First 1)

    if ($catalogEntry.Count -eq 0) {
        throw "RenderKit error code '$Code' is not registered."
    }

    if ([string]::IsNullOrWhiteSpace($Category)) {
        $Category = [string]$catalogEntry[0].Category
    }

    return [PSCustomObject]@{
        code          = $Code
        message       = $Message
        category      = $Category
        details       = $Details
        occurredAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function New-RenderKitActorContext {
    [CmdletBinding()]
    param(
        [string]$ActorId,
        [ValidateSet('User', 'System', 'Worker', 'Integration', 'Service')]
        [string]$ActorType = 'System',
        [string]$DisplayName,
        [string]$Source = 'RenderKit',
        [string[]]$RolesSnapshot,
        [string]$SessionId,
        [string]$CorrelationId,
        [string]$CausationId
    )

    $roles = @()
    if ($RolesSnapshot) {
        $roles = @($RolesSnapshot)
    }

    return [PSCustomObject]@{
        actorId       = $ActorId
        actorType     = $ActorType
        displayName   = $DisplayName
        source        = $Source
        rolesSnapshot = $roles
        sessionId     = $SessionId
        correlationId = New-RenderKitCorrelationId -CorrelationId $CorrelationId
        causationId   = New-RenderKitCausationId -CausationId $CausationId
    }
}

function New-RenderKitOperationContext {
    [CmdletBinding()]
    param(
        [string]$OperationName,
        [object]$Actor,
        [string]$CorrelationId,
        [string]$CausationId,
        [string]$Source = 'RenderKit',
        [object]$Metadata
    )

    $normalizedCorrelationId = New-RenderKitCorrelationId -CorrelationId $CorrelationId
    $normalizedCausationId = New-RenderKitCausationId -CausationId $CausationId

    if (-not $Actor) {
        $Actor = New-RenderKitActorContext `
            -ActorType System `
            -Source $Source `
            -CorrelationId $normalizedCorrelationId `
            -CausationId $normalizedCausationId
    }

    return [PSCustomObject]@{
        operationName = $OperationName
        source        = $Source
        actor         = $Actor
        correlationId = $normalizedCorrelationId
        causationId   = $normalizedCausationId
        metadata      = $Metadata
        createdAtUtc  = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function New-RenderKitResult {
    [CmdletBinding(DefaultParameterSetName = 'Success')]
    param(
        [Parameter(ParameterSetName = 'Success')]
        [object]$Data,
        [Parameter(ParameterSetName = 'Failure', Mandatory)]
        [object]$Errors,
        [object[]]$Warnings,
        [object]$OperationContext,
        [string]$CorrelationId,
        [string]$CausationId
    )

    if ($OperationContext) {
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) {
            $CorrelationId = [string]$OperationContext.correlationId
        }
        if ([string]::IsNullOrWhiteSpace($CausationId)) {
            $CausationId = [string]$OperationContext.causationId
        }
    }

    $isSuccess = $PSCmdlet.ParameterSetName -eq 'Success'
    $resultData = $null
    $resultError = $null
    if ($isSuccess) {
        $resultData = $Data
    }
    else {
        $resultError = $Errors
    }

    $actor = $null
    if ($OperationContext) {
        $actor = $OperationContext.actor
    }

    return [PSCustomObject]@{
        success       = $isSuccess
        data          = $resultData
        warnings      = @($Warnings)
        error         = $resultError
        correlationId = New-RenderKitCorrelationId -CorrelationId $CorrelationId
        causationId   = New-RenderKitCausationId -CausationId $CausationId
        actor         = $actor
        timestampUtc  = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Get-RenderKitEngineFacadeOperationCatalog {
    [CmdletBinding()]
    param()

    return @(
        [PSCustomObject]@{ Name = 'GetRenderKitEngineContractSnapshot'; MutatesState = $false; RequiresActor = $false; Description = 'Returns a machine-readable host handoff contract snapshot.' }
        [PSCustomObject]@{ Name = 'GetRenderKitEngineInfo'; MutatesState = $false; RequiresActor = $false; Description = 'Returns module and engine capability metadata.' }
        [PSCustomObject]@{ Name = 'GetRenderKitEngineState'; MutatesState = $false; RequiresActor = $false; Description = 'Returns storage and artifact health for the active engine state.' }
        [PSCustomObject]@{ Name = 'GetRenderKitProjectList'; MutatesState = $false; RequiresActor = $false; Description = 'Returns GUI-ready project summaries.' }
        [PSCustomObject]@{ Name = 'GetRenderKitProjectDetail'; MutatesState = $false; RequiresActor = $false; Description = 'Returns a GUI-ready project detail view.' }
        [PSCustomObject]@{ Name = 'GetRenderKitClientList'; MutatesState = $false; RequiresActor = $false; Description = 'Returns paged client summaries without contact details.' }
        [PSCustomObject]@{ Name = 'GetRenderKitClientDetail'; MutatesState = $false; RequiresActor = $false; Description = 'Returns one client including contacts and addresses.' }
        [PSCustomObject]@{ Name = 'NewRenderKitClient'; MutatesState = $true; RequiresActor = $true; Description = 'Creates a validated client in the global registry.' }
        [PSCustomObject]@{ Name = 'SetRenderKitClient'; MutatesState = $true; RequiresActor = $true; Description = 'Updates a client with optimistic revision checks.' }
        [PSCustomObject]@{ Name = 'GetRenderKitPublicationList'; MutatesState = $false; RequiresActor = $false; Description = 'Returns bounded publication summaries overlapping a UTC range.' }
        [PSCustomObject]@{ Name = 'GetRenderKitPublicationDetail'; MutatesState = $false; RequiresActor = $false; Description = 'Returns one publication planning record.' }
        [PSCustomObject]@{ Name = 'NewRenderKitPublication'; MutatesState = $true; RequiresActor = $true; Description = 'Creates a non-recurring publication planning record.' }
        [PSCustomObject]@{ Name = 'SetRenderKitPublication'; MutatesState = $true; RequiresActor = $true; Description = 'Updates a publication with optimistic revision checks.' }
        [PSCustomObject]@{ Name = 'GetRenderKitJobList'; MutatesState = $false; RequiresActor = $false; Description = 'Returns GUI-ready job summaries.' }
        [PSCustomObject]@{ Name = 'GetRenderKitJobDetail'; MutatesState = $false; RequiresActor = $false; Description = 'Returns a GUI-ready job detail view.' }
        [PSCustomObject]@{ Name = 'GetRenderKitJobHandlerCatalog'; MutatesState = $false; RequiresActor = $false; Description = 'Returns trusted job handler metadata without executable scriptblocks.' }
        [PSCustomObject]@{ Name = 'NewRenderKitEngineJob'; MutatesState = $true; RequiresActor = $true; Description = 'Creates a durable job from a validated host request.' }
        [PSCustomObject]@{ Name = 'RequestRenderKitEngineJobCancellation'; MutatesState = $true; RequiresActor = $true; Description = 'Requests cancellation for a queued, retry-scheduled, or running job.' }
        [PSCustomObject]@{ Name = 'RetryRenderKitEngineJob'; MutatesState = $true; RequiresActor = $true; Description = 'Moves a failed or retry-scheduled job back to the queue.' }
        [PSCustomObject]@{ Name = 'UpdateRenderKitEngineJobProgress'; MutatesState = $true; RequiresActor = $true; Description = 'Updates structured progress for a non-terminal job.' }
        [PSCustomObject]@{ Name = 'SetRenderKitEngineJobSucceeded'; MutatesState = $true; RequiresActor = $true; Description = 'Persists a result and marks a running job as succeeded.' }
        [PSCustomObject]@{ Name = 'SetRenderKitEngineJobFailed'; MutatesState = $true; RequiresActor = $true; Description = 'Persists a structured error and marks a job as failed.' }
        [PSCustomObject]@{ Name = 'InvokeRenderKitWorkerTick'; MutatesState = $true; RequiresActor = $true; Description = 'Claims and processes at most one durable unit of work.' }
        [PSCustomObject]@{ Name = 'GetRenderKitEventList'; MutatesState = $false; RequiresActor = $false; Description = 'Returns GUI-ready domain event summaries.' }
        [PSCustomObject]@{ Name = 'GetRenderKitEventDetail'; MutatesState = $false; RequiresActor = $false; Description = 'Returns a GUI-ready event detail view.' }
        [PSCustomObject]@{ Name = 'InvokeRenderKitEventBridge'; MutatesState = $true; RequiresActor = $true; Description = 'Processes pending domain-event subscriptions into durable jobs.' }
    )
}

function New-RenderKitEngineOperationContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OperationName,
        [object]$OperationContext,
        [object]$Actor,
        [string]$CorrelationId,
        [string]$CausationId,
        [string]$Source = 'RenderKitBroker',
        [object]$Metadata
    )

    if ($OperationContext) {
        return $OperationContext
    }

    return New-RenderKitOperationContext `
        -OperationName $OperationName `
        -Actor $Actor `
        -CorrelationId $CorrelationId `
        -CausationId $CausationId `
        -Source $Source `
        -Metadata $Metadata
}

function New-RenderKitEngineFailureResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$OperationContext,
        [Parameter(Mandatory)]
        [string]$Code,
        [Parameter(Mandatory)]
        [string]$Message,
        [object]$Details
    )

    return New-RenderKitResult `
        -Error (New-RenderKitError `
            -Code $Code `
            -Message $Message `
            -Details $Details) `
        -OperationContext $OperationContext
}

function Test-RenderKitEngineActorContext {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [object]$OperationContext
    )

    if (-not $OperationContext -or -not $OperationContext.actor) {
        return $false
    }

    return (
        -not [string]::IsNullOrWhiteSpace([string]$OperationContext.actor.actorType) -and
        -not [string]::IsNullOrWhiteSpace([string]$OperationContext.actor.actorId)
    )
}

function New-RenderKitEngineJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobType,
        [object]$Payload,
        [string]$TriggerEventId,
        [string]$PayloadSchemaVersion = '1.0',
        [string]$QueueName = 'default',
        [int]$Priority = 0,
        [object]$OperationContext,
        [object]$Actor,
        [string]$CorrelationId,
        [string]$CausationId,
        [string]$Source = 'RenderKitBroker'
    )

    $context = New-RenderKitEngineOperationContext `
        -OperationName 'NewRenderKitEngineJob' `
        -OperationContext $OperationContext `
        -Actor $Actor `
        -CorrelationId $CorrelationId `
        -CausationId $CausationId `
        -Source $Source

    if (-not (Test-RenderKitEngineActorContext -OperationContext $context)) {
        return New-RenderKitEngineFailureResult `
            -OperationContext $context `
            -Code 'RK_ACCESS_CONTEXT_MISSING' `
            -Message 'Creating a RenderKit job requires an actor context.'
    }

    $job = Add-RenderKitJob -Job (New-RenderKitJob `
            -JobType $JobType `
            -Payload $Payload `
            -TriggerEventId $TriggerEventId `
            -CorrelationId ([string]$context.correlationId) `
            -PayloadSchemaVersion $PayloadSchemaVersion `
            -QueueName $QueueName `
            -Priority $Priority `
            -RequestedBy $context.actor)

    return New-RenderKitResult -Data $job -OperationContext $context
}

function Get-RenderKitEngineJobList {
    [CmdletBinding()]
    param(
        [string]$Status,
        [string]$JobType,
        [string]$QueueName,
        [string]$JobCorrelationId,
        [string]$CorrelationId,
        [object]$OperationContext,
        [object]$Actor,
        [string]$CausationId,
        [string]$Source = 'RenderKitBroker'
    )

    $context = New-RenderKitEngineOperationContext `
        -OperationName 'GetRenderKitJobList' `
        -OperationContext $OperationContext `
        -Actor $Actor `
        -CorrelationId $CorrelationId `
        -CausationId $CausationId `
        -Source $Source

    try {
        $jobs = @(Get-RenderKitJobList `
                -Status $Status `
                -JobType $JobType `
                -QueueName $QueueName `
                -CorrelationId $JobCorrelationId)
        return New-RenderKitResult -Data $jobs -OperationContext $context
    }
    catch {
        return New-RenderKitEngineFailureResult `
            -OperationContext $context `
            -Code 'RK_VALIDATION_FAILED' `
            -Message $_.Exception.Message
    }
}

function Get-RenderKitEngineJobDetail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [object]$OperationContext,
        [object]$Actor,
        [string]$CorrelationId,
        [string]$CausationId,
        [string]$Source = 'RenderKitBroker'
    )

    $context = New-RenderKitEngineOperationContext `
        -OperationName 'GetRenderKitJobDetail' `
        -OperationContext $OperationContext `
        -Actor $Actor `
        -CorrelationId $CorrelationId `
        -CausationId $CausationId `
        -Source $Source

    $job = Get-RenderKitJob -JobId $JobId
    if (-not $job) {
        return New-RenderKitEngineFailureResult `
            -OperationContext $context `
            -Code 'RK_JOB_NOT_FOUND' `
            -Message "RenderKit job '$JobId' was not found." `
            -Details ([PSCustomObject]@{ jobId = $JobId })
    }

    return New-RenderKitResult -Data $job -OperationContext $context
}

function Request-RenderKitEngineJobCancellation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [string]$Reason,
        [object]$OperationContext,
        [object]$Actor,
        [string]$CorrelationId,
        [string]$CausationId,
        [string]$Source = 'RenderKitBroker'
    )

    $context = New-RenderKitEngineOperationContext `
        -OperationName 'RequestRenderKitEngineJobCancellation' `
        -OperationContext $OperationContext `
        -Actor $Actor `
        -CorrelationId $CorrelationId `
        -CausationId $CausationId `
        -Source $Source

    if (-not (Test-RenderKitEngineActorContext -OperationContext $context)) {
        return New-RenderKitEngineFailureResult `
            -OperationContext $context `
            -Code 'RK_ACCESS_CONTEXT_MISSING' `
            -Message 'Cancelling a RenderKit job requires an actor context.'
    }

    try {
        $job = Request-RenderKitJobCancellation `
            -JobId $JobId `
            -Reason $Reason `
            -RequestedBy $context.actor
        return New-RenderKitResult -Data $job -OperationContext $context
    }
    catch {
        return New-RenderKitEngineFailureResult `
            -OperationContext $context `
            -Code 'RK_JOB_INVALID_STATE' `
            -Message $_.Exception.Message `
            -Details ([PSCustomObject]@{ jobId = $JobId })
    }
}

function Retry-RenderKitEngineJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [object]$OperationContext,
        [object]$Actor,
        [string]$CorrelationId,
        [string]$CausationId,
        [string]$Source = 'RenderKitBroker'
    )

    $context = New-RenderKitEngineOperationContext `
        -OperationName 'RetryRenderKitEngineJob' `
        -OperationContext $OperationContext `
        -Actor $Actor `
        -CorrelationId $CorrelationId `
        -CausationId $CausationId `
        -Source $Source

    if (-not (Test-RenderKitEngineActorContext -OperationContext $context)) {
        return New-RenderKitEngineFailureResult `
            -OperationContext $context `
            -Code 'RK_ACCESS_CONTEXT_MISSING' `
            -Message 'Retrying a RenderKit job requires an actor context.'
    }

    try {
        $job = Reset-RenderKitJobForRetry -JobId $JobId
        return New-RenderKitResult -Data $job -OperationContext $context
    }
    catch {
        return New-RenderKitEngineFailureResult `
            -OperationContext $context `
            -Code 'RK_JOB_INVALID_STATE' `
            -Message $_.Exception.Message `
            -Details ([PSCustomObject]@{ jobId = $JobId })
    }
}

function Update-RenderKitEngineJobProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [string]$Phase,
        [string]$Message,
        [int]$Current = 0,
        [int]$Total = 0,
        [Nullable[double]]$Percent,
        [object]$OperationContext,
        [object]$Actor,
        [string]$CorrelationId,
        [string]$CausationId,
        [string]$Source = 'RenderKitBroker'
    )

    $context = New-RenderKitEngineOperationContext `
        -OperationName 'UpdateRenderKitEngineJobProgress' `
        -OperationContext $OperationContext `
        -Actor $Actor `
        -CorrelationId $CorrelationId `
        -CausationId $CausationId `
        -Source $Source

    if (-not (Test-RenderKitEngineActorContext -OperationContext $context)) {
        return New-RenderKitEngineFailureResult `
            -OperationContext $context `
            -Code 'RK_ACCESS_CONTEXT_MISSING' `
            -Message 'Updating RenderKit job progress requires an actor context.'
    }

        try {
        $job = Update-RenderKitJobProgress `
            -JobId $JobId `
            -Phase $Phase `
            -Message $Message `
            -Current $Current `
            -Total $Total `
            -Percent $Percent
        return New-RenderKitResult -Data $job -OperationContext $context
    }
    catch {
        return New-RenderKitEngineFailureResult `
            -OperationContext $context `
            -Code 'RK_JOB_INVALID_STATE' `
            -Message $_.Exception.Message `
            -Details ([PSCustomObject]@{ jobId = $JobId })
    }
}

function Set-RenderKitEngineJobSucceeded {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [object]$Result,
        [object]$OperationContext,
        [object]$Actor,
        [string]$CorrelationId,
        [string]$CausationId,
        [string]$Source = 'RenderKitBroker'
    )

    $context = New-RenderKitEngineOperationContext `
        -OperationName 'SetRenderKitEngineJobSucceeded' `
        -OperationContext $OperationContext `
        -Actor $Actor `
        -CorrelationId $CorrelationId `
        -CausationId $CausationId `
        -Source $Source

        if (-not (Test-RenderKitEngineActorContext -OperationContext $context)) {
        return New-RenderKitEngineFailureResult `
            -OperationContext $context `
            -Code 'RK_ACCESS_CONTEXT_MISSING' `
            -Message 'Marking a RenderKit job as succeeded requires an actor context.'
    }

    try {
        Set-RenderKitJobResult -JobId $JobId -Result $Result | Out-Null
        Set-RenderKitJobStatus -JobId $JobId -Status Succeeded
        $job = Get-RenderKitJob -JobId $JobId
        return New-RenderKitResult -Data $job -OperationContext $context
    }
    catch {
        return New-RenderKitEngineFailureResult `
            -OperationContext $context `
            -Code 'RK_JOB_INVALID_STATE' `
            -Message $_.Exception.Message `
            -Details ([PSCustomObject]@{ jobId = $JobId })
    }
}

function Set-RenderKitEngineJobFailed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [Parameter(Mandatory)]
        [string]$Message,
        [string]$Code = 'RK_INTERNAL_ERROR',
        [object]$Details,
        [object]$OperationContext,
        [object]$Actor,
        [string]$CorrelationId,
        [string]$CausationId,
        [string]$Source = 'RenderKitBroker'
    )

    $context = New-RenderKitEngineOperationContext `
        -OperationName 'SetRenderKitEngineJobFailed' `
        -OperationContext $OperationContext `
        -Actor $Actor `
        -CorrelationId $CorrelationId `
        -CausationId $CausationId `
        -Source $Source

        if (-not (Test-RenderKitEngineActorContext -OperationContext $context)) {
        return New-RenderKitEngineFailureResult `
            -OperationContext $context `
            -Code 'RK_ACCESS_CONTEXT_MISSING' `
            -Message 'Marking a RenderKit job as failed requires an actor context.'
    }

    try {
        Set-RenderKitJobStatus `
            -JobId $JobId `
            -Status Failed `
            -ErrorMessage $Message `
            -ErrorCode $Code
        $job = Get-RenderKitJob -JobId $JobId
        return New-RenderKitResult -Data $job -OperationContext $context
    }
    catch {
        return New-RenderKitEngineFailureResult `
            -OperationContext $context `
            -Code 'RK_JOB_INVALID_STATE' `
            -Message $_.Exception.Message `
            -Details ([PSCustomObject]@{ jobId = $JobId; details = $Details })
    }
}


function Get-RenderKitEngineJobHandlerCatalog {
    [CmdletBinding()]
    param(
        [string]$JobType,
        [object]$OperationContext,
        [object]$Actor,
        [string]$CorrelationId,
        [string]$CausationId,
        [string]$Source = 'RenderKitBroker'
    )

    $context = New-RenderKitEngineOperationContext `
        -OperationName 'GetRenderKitJobHandlerCatalog' `
        -OperationContext $OperationContext `
        -Actor $Actor `
        -CorrelationId $CorrelationId `
        -CausationId $CausationId `
        -Source $Source

    $catalog = @(Get-RenderKitJobHandlerCatalog -JobType $JobType)
    return New-RenderKitResult -Data $catalog -OperationContext $context
}

function Get-RenderKitEngineEventList {
    [CmdletBinding()]
    param(
        [string]$Status,
        [string]$EventType,
        [string]$AggregateType,
        [string]$AggregateId,
        [string]$EventCorrelationId,
        [string]$Category,
        [object]$OperationContext,
        [object]$Actor,
        [string]$CorrelationId,
        [string]$CausationId,
        [string]$Source = 'RenderKitBroker'
    )

    $context = New-RenderKitEngineOperationContext `
        -OperationName 'GetRenderKitEventList' `
        -OperationContext $OperationContext `
        -Actor $Actor `
        -CorrelationId $CorrelationId `
        -CausationId $CausationId `
        -Source $Source

    try {
        $events = @(Get-RenderKitDomainEventList `
                -Status $Status `
                -EventType $EventType `
                -AggregateType $AggregateType `
                -AggregateId $AggregateId `
                -CorrelationId $EventCorrelationId `
                -Category $Category)
        return New-RenderKitResult -Data $events -OperationContext $context
    }
    catch {
        return New-RenderKitEngineFailureResult `
            -OperationContext $context `
            -Code 'RK_VALIDATION_FAILED' `
            -Message $_.Exception.Message
    }
}

function Get-RenderKitEngineEventDetail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EventId,
        [object]$OperationContext,
        [object]$Actor,
        [string]$CorrelationId,
        [string]$CausationId,
        [string]$Source = 'RenderKitBroker'
    )

    $context = New-RenderKitEngineOperationContext `
        -OperationName 'GetRenderKitEventDetail' `
        -OperationContext $OperationContext `
        -Actor $Actor `
        -CorrelationId $CorrelationId `
        -CausationId $CausationId `
        -Source $Source

    $events = Get-RenderKitDomainEvent -EventId $EventId
    if (-not $events) {
        return New-RenderKitEngineFailureResult `
            -OperationContext $context `
            -Code 'RK_NOT_FOUND' `
            -Message "RenderKit domain event '$EventId' was not found." `
            -Details ([PSCustomObject]@{ eventId = $EventId })
    }

    return New-RenderKitResult -Data $events -OperationContext $context
}

function Invoke-RenderKitEngineEventBridge {
    [CmdletBinding()]
    param(
        [string]$EventType,
        [object]$OperationContext,
        [object]$Actor,
        [string]$CorrelationId,
        [string]$CausationId,
        [string]$Source = 'RenderKitBroker'
    )

    $context = New-RenderKitEngineOperationContext `
        -OperationName 'InvokeRenderKitEventBridge' `
        -OperationContext $OperationContext `
        -Actor $Actor `
        -CorrelationId $CorrelationId `
        -CausationId $CausationId `
        -Source $Source

    if (-not (Test-RenderKitEngineActorContext -OperationContext $context)) {
        return New-RenderKitEngineFailureResult `
            -OperationContext $context `
            -Code 'RK_ACCESS_CONTEXT_MISSING' `
            -Message 'Invoking the RenderKit event bridge requires an actor context.'
    }

    try {
        $bridgeResult = Invoke-RenderKitEventJobBridge -EventType $EventType
        return New-RenderKitResult -Data $bridgeResult -OperationContext $context
    }
    catch {
        return New-RenderKitEngineFailureResult `
            -OperationContext $context `
            -Code 'RK_INTERNAL_ERROR' `
            -Message $_.Exception.Message
    }
}


function Get-RenderKitEngineContractSnapshot {
    [CmdletBinding()]
    param(
        [object]$OperationContext,
        [object]$Actor,
        [string]$CorrelationId,
        [string]$CausationId,
        [string]$Source = 'RenderKitBroker'
    )

    $context = New-RenderKitEngineOperationContext `
        -OperationName 'GetRenderKitEngineContractSnapshot' `
        -OperationContext $OperationContext `
        -Actor $Actor `
        -CorrelationId $CorrelationId `
        -CausationId $CausationId `
        -Source $Source

    $snapshot = [PSCustomObject]@{
        contractVersion = '1.0'
        generatedAtUtc  = (Get-Date).ToUniversalTime().ToString('o')
        boundary        = [PSCustomObject]@{
            authenticationOwner = 'Host'
            authorizationOwner  = 'Host'
            engineRole          = 'Domain validation, durable state, and trusted worker operations'
            transport           = 'Host-defined local IPC or process bridge'
        }
        schemas         = [PSCustomObject]@{
            eventStore         = Get-RenderKitEventStoreSchemaVersion
            jobStore           = Get-RenderKitJobStoreSchemaVersion
            clientRegistry     = (
                Get-RenderKitArtifactVersionPolicy `
                    -ArtifactType ClientRegistry
            ).Current
            publishingSchedule = (
                Get-RenderKitArtifactVersionPolicy `
                    -ArtifactType PublishingSchedule
            ).Current
        }
        resultEnvelope  = [PSCustomObject]@{
            fields = @('success', 'data', 'warnings', 'error', 'correlationId', 'causationId', 'actor', 'timestampUtc')
        }
        actorContext    = [PSCustomObject]@{
            actorTypes = @('User', 'System', 'Worker', 'Integration', 'Service')
            fields     = @('actorId', 'actorType', 'displayName', 'source', 'rolesSnapshot', 'sessionId', 'correlationId', 'causationId')
        }
        operations      = @(Get-RenderKitEngineFacadeOperationCatalog)
        errorCodes      = @(Get-RenderKitErrorCodeCatalog)
        handoff         = [PSCustomObject]@{
            recommendedHostRuntime = 'Electron local broker with private PowerShell worker process'
            notes                  = @(
                'Keep users, sessions, roles, and permissions outside the engine.',
                'Call mutating operations with an actor context supplied by the host.',
                'Persist host audit logs outside domain events if regulatory audit is required.',
                'Use correlation and causation ids for GUI, worker, and adapter tracing.'
            )
        }
    }

    return New-RenderKitResult -Data $snapshot -OperationContext $context
}

function Get-RenderKitEngineInfo {
    [CmdletBinding()]
    param(
        [object]$OperationContext,
        [object]$Actor,
        [string]$CorrelationId,
        [string]$CausationId,
        [string]$Source = 'RenderKitBroker'
    )

    $context = New-RenderKitEngineOperationContext `
        -OperationName 'GetRenderKitEngineInfo' `
        -OperationContext $OperationContext `
        -Actor $Actor `
        -CorrelationId $CorrelationId `
        -CausationId $CausationId `
        -Source $Source

    $manifestPath = Join-Path -Path $script:RenderKitModuleRoot -ChildPath 'RenderKit.psd1'
    $manifest = $null
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
    }

    $data = [PSCustomObject]@{
        name              = 'RenderKit'
        moduleVersion     = if ($manifest) { [string]$manifest.ModuleVersion } else { $null }
        minimumPowerShell = if ($manifest) { [string]$manifest.PowerShellVersion } else { $null }
        compatibleEdition = if ($manifest) { @($manifest.CompatiblePSEditions) } else { @() }
        engineSchema      = [PSCustomObject]@{
            eventStore     = Get-RenderKitEventStoreSchemaVersion
            jobStore       = Get-RenderKitJobStoreSchemaVersion
            clientRegistry = (
                Get-RenderKitArtifactVersionPolicy `
                    -ArtifactType ClientRegistry
            ).Current
            publishingSchedule = (
                Get-RenderKitArtifactVersionPolicy `
                    -ArtifactType PublishingSchedule
            ).Current
        }
        facadeOperations  = @(Get-RenderKitEngineFacadeOperationCatalog)
    }

    return New-RenderKitResult -Data $data -OperationContext $context
}

function Get-RenderKitEngineState {
    [CmdletBinding()]
    param(
        [switch]$RestoreFromBackup,
        [object]$OperationContext,
        [object]$Actor,
        [string]$CorrelationId,
        [string]$CausationId,
        [string]$Source = 'RenderKitBroker'
    )

    $context = New-RenderKitEngineOperationContext `
        -OperationName 'GetRenderKitEngineState' `
        -OperationContext $OperationContext `
        -Actor $Actor `
        -CorrelationId $CorrelationId `
        -CausationId $CausationId `
        -Source $Source

    try {
        $state = Invoke-RenderKitStateRepair -RestoreFromBackup:$RestoreFromBackup
        return New-RenderKitResult -Data $state -OperationContext $context
    }
    catch {
        return New-RenderKitEngineFailureResult `
            -OperationContext $context `
            -Code 'RK_STORAGE_UNAVAILABLE' `
            -Message $_.Exception.Message
    }
}

function New-RenderKitEngineClientSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Client
    )

    return [PSCustomObject]@{
        id           = [string]$Client.id
        displayName  = [string]$Client.displayName
        legalName    = [string]$Client.legalName
        status       = [string]$Client.status
        tags         = @($Client.tags | ForEach-Object { [string]$_ })
        revision     = [int]$Client.revision
        updatedAtUtc = [string]$Client.updatedAtUtc
    }
}

function Get-RenderKitEngineClientList {
    [CmdletBinding()]
    param(
        [string]$Search,
        [string]$Status,
        [string]$Tag,
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Offset = 0,
        [ValidateRange(1, 200)]
        [int]$Limit = 100,
        [object]$OperationContext,
        [object]$Actor,
        [string]$CorrelationId,
        [string]$CausationId,
        [string]$Source = 'RenderKitBroker'
    )

    $context = New-RenderKitEngineOperationContext `
        -OperationName 'GetRenderKitClientList' `
        -OperationContext $OperationContext `
        -Actor $Actor `
        -CorrelationId $CorrelationId `
        -CausationId $CausationId `
        -Source $Source
    try {
        $parameters = @{}
        if (-not [string]::IsNullOrWhiteSpace($Search)) {
            $parameters.Search = $Search
        }
        if (-not [string]::IsNullOrWhiteSpace($Status)) {
            if (@('Active', 'Inactive', 'Archived') -notcontains $Status) {
                throw [System.ArgumentException]::new(
                    "Unsupported client status '$Status'.")
            }
            $parameters.Status = $Status
        }
        if (-not [string]::IsNullOrWhiteSpace($Tag)) {
            $parameters.Tag = $Tag
        }
        $clients = @(Get-RenderKitClientRecordList @parameters)
        $items = @(
            $clients |
                Select-Object -Skip $Offset -First $Limit |
                ForEach-Object {
                    New-RenderKitEngineClientSummary -Client $_
                }
        )
        return New-RenderKitResult `
            -Data ([PSCustomObject]@{
                items = $items
                total = $clients.Count
                offset = $Offset
                limit = $Limit
            }) `
            -OperationContext $context
    }
    catch {
        return New-RenderKitEngineClientFailure `
            -OperationContext $context `
            -Exception $_.Exception
    }
}

function Get-RenderKitEngineClientDetail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ClientId,
        [object]$OperationContext,
        [object]$Actor,
        [string]$CorrelationId,
        [string]$CausationId,
        [string]$Source = 'RenderKitBroker'
    )

    $context = New-RenderKitEngineOperationContext `
        -OperationName 'GetRenderKitClientDetail' `
        -OperationContext $OperationContext `
        -Actor $Actor `
        -CorrelationId $CorrelationId `
        -CausationId $CausationId `
        -Source $Source
    try {
        $client = Get-RenderKitClientRecord -Id $ClientId
        if (-not $client) {
            throw [System.Collections.Generic.KeyNotFoundException]::new(
                "RenderKit client '$ClientId' was not found.")
        }
        return New-RenderKitResult -Data $client -OperationContext $context
    }
    catch {
        return New-RenderKitEngineClientFailure `
            -OperationContext $context `
            -Exception $_.Exception
    }
}

function New-RenderKitEngineClient {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DisplayName,
        [string]$LegalName,
        [string]$Status = 'Active',
        [string[]]$Tags = @(),
        [string]$Notes,
        [object[]]$Contacts = @(),
        [object[]]$Addresses = @(),
        [object]$Consent,
        [object]$Retention,
        [object]$OperationContext,
        [object]$Actor,
        [string]$CorrelationId,
        [string]$CausationId,
        [string]$Source = 'RenderKitBroker'
    )

    $context = New-RenderKitEngineOperationContext `
        -OperationName 'NewRenderKitClient' `
        -OperationContext $OperationContext `
        -Actor $Actor `
        -CorrelationId $CorrelationId `
        -CausationId $CausationId `
        -Source $Source

    if (-not (Test-RenderKitEngineActorContext -OperationContext $context)) {
        return New-RenderKitEngineFailureResult `
            -OperationContext $context `
            -Code 'RK_ACCESS_CONTEXT_MISSING' `
            -Message 'Creating a RenderKit client requires an actor context.'
    }

    try {
        $client = New-RenderKitClientRecord `
            -DisplayName $DisplayName `
            -LegalName $LegalName `
            -Status $Status `
            -Tags $Tags `
            -Notes $Notes `
            -Contacts $Contacts `
            -Addresses $Addresses `
            -Consent $Consent `
            -Retention $Retention
        $created = Add-RenderKitClientRecord -Client $client
        return New-RenderKitResult -Data $created -OperationContext $context
    }
    catch {
        return New-RenderKitEngineClientFailure `
            -OperationContext $context `
            -Exception $_.Exception
    }
}

function Set-RenderKitEngineClient {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ClientId,
        [Parameter(Mandatory)]
        [int]$ExpectedRevision,
        [Parameter(Mandatory)]
        [hashtable]$Changes,
        [object]$OperationContext,
        [object]$Actor,
        [string]$CorrelationId,
        [string]$CausationId,
        [string]$Source = 'RenderKitBroker'
    )

    $context = New-RenderKitEngineOperationContext `
        -OperationName 'SetRenderKitClient' `
        -OperationContext $OperationContext `
        -Actor $Actor `
        -CorrelationId $CorrelationId `
        -CausationId $CausationId `
        -Source $Source

    if (-not (Test-RenderKitEngineActorContext -OperationContext $context)) {
        return New-RenderKitEngineFailureResult `
            -OperationContext $context `
            -Code 'RK_ACCESS_CONTEXT_MISSING' `
            -Message 'Updating a RenderKit client requires an actor context.'
    }

    try {
        if ($Changes.Count -eq 0) {
            throw [System.ArgumentException]::new(
                'At least one client field must be supplied.')
        }
        $updated = Update-RenderKitClientRecord `
            -Id $ClientId `
            -ExpectedRevision $ExpectedRevision `
            -Changes $Changes
        return New-RenderKitResult -Data $updated -OperationContext $context
    }
    catch {
        return New-RenderKitEngineClientFailure `
            -OperationContext $context `
            -Exception $_.Exception
    }
}

function New-RenderKitEngineClientFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$OperationContext,
        [Parameter(Mandatory)]
        [System.Exception]$Exception
    )

    $code = if ($Exception -is [System.ArgumentException]) {
        'RK_VALIDATION_FAILED'
    }
    elseif ($Exception -is [System.Collections.Generic.KeyNotFoundException]) {
        'RK_NOT_FOUND'
    }
    elseif ($Exception -is [System.InvalidOperationException]) {
        'RK_CONFLICT'
    }
    else {
        'RK_STORAGE_UNAVAILABLE'
    }
    return New-RenderKitEngineFailureResult `
        -OperationContext $OperationContext `
        -Code $code `
        -Message $Exception.Message
}

function New-RenderKitEnginePublicationSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Publication
    )

    return [PSCustomObject]@{
        id                  = [string]$Publication.id
        title               = [string]$Publication.title
        status              = [string]$Publication.status
        startUtc            = [string]$Publication.startUtc
        endUtc              = [string]$Publication.endUtc
        timeZone            = [string]$Publication.timeZone
        projectId           = [string]$Publication.projectId
        projectNameSnapshot = [string]$Publication.projectNameSnapshot
        clientId            = [string]$Publication.clientId
        clientNameSnapshot  = [string]$Publication.clientNameSnapshot
        channelProvider     = [string]$Publication.channelProvider
        channelNameSnapshot = [string]$Publication.channelNameSnapshot
        ownerId             = [string]$Publication.ownerId
        ownerNameSnapshot   = [string]$Publication.ownerNameSnapshot
        revision            = [int]$Publication.revision
        updatedAtUtc        = [string]$Publication.updatedAtUtc
    }
}

function Get-RenderKitEnginePublicationList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FromUtc,
        [Parameter(Mandatory)][string]$ToUtc,
        [string]$Search,
        [string]$Status,
        [string]$ProjectId,
        [string]$ClientId,
        [string]$ChannelProvider,
        [ValidateRange(0, [int]::MaxValue)][int]$Offset = 0,
        [ValidateRange(1, 500)][int]$Limit = 200,
        [object]$OperationContext,
        [object]$Actor,
        [string]$CorrelationId,
        [string]$CausationId,
        [string]$Source = 'RenderKitBroker'
    )

    $context = New-RenderKitEngineOperationContext `
        -OperationName 'GetRenderKitPublicationList' `
        -OperationContext $OperationContext `
        -Actor $Actor `
        -CorrelationId $CorrelationId `
        -CausationId $CausationId `
        -Source $Source
    try {
        $parameters = @{
            FromUtc = $FromUtc
            ToUtc = $ToUtc
        }
        foreach ($name in @(
            'Search',
            'Status',
            'ProjectId',
            'ClientId',
            'ChannelProvider'
        )) {
            $value = Get-Variable -Name $name -ValueOnly
            if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
                $parameters[$name] = $value
            }
        }
        $records = @(Get-RenderKitPublicationRecordList @parameters)
        $items = @(
            $records |
                Select-Object -Skip $Offset -First $Limit |
                ForEach-Object {
                    New-RenderKitEnginePublicationSummary -Publication $_
                }
        )
        return New-RenderKitResult `
            -Data ([PSCustomObject]@{
                items = $items
                total = $records.Count
                offset = $Offset
                limit = $Limit
                fromUtc = ConvertTo-RenderKitPublicationUtcTimestamp `
                    -Value $FromUtc -Name FromUtc -Required
                toUtc = ConvertTo-RenderKitPublicationUtcTimestamp `
                    -Value $ToUtc -Name ToUtc -Required
            }) `
            -OperationContext $context
    }
    catch {
        return New-RenderKitEnginePublicationFailure `
            -OperationContext $context `
            -Exception $_.Exception
    }
}

function Get-RenderKitEnginePublicationDetail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PublicationId,
        [object]$OperationContext,
        [object]$Actor,
        [string]$CorrelationId,
        [string]$CausationId,
        [string]$Source = 'RenderKitBroker'
    )

    $context = New-RenderKitEngineOperationContext `
        -OperationName 'GetRenderKitPublicationDetail' `
        -OperationContext $OperationContext `
        -Actor $Actor `
        -CorrelationId $CorrelationId `
        -CausationId $CausationId `
        -Source $Source
    try {
        $publication = Get-RenderKitPublicationRecord -Id $PublicationId
        if (-not $publication) {
            throw [System.Collections.Generic.KeyNotFoundException]::new(
                "RenderKit publication '$PublicationId' was not found.")
        }
        return New-RenderKitResult `
            -Data $publication `
            -OperationContext $context
    }
    catch {
        return New-RenderKitEnginePublicationFailure `
            -OperationContext $context `
            -Exception $_.Exception
    }
}

function New-RenderKitEnginePublication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [string]$Description,
        [ValidateSet('Draft', 'Scheduled')][string]$Status = 'Draft',
        [Parameter(Mandatory)][string]$StartUtc,
        [string]$EndUtc,
        [Parameter(Mandatory)][string]$TimeZone,
        [string]$ProjectId,
        [string]$ProjectNameSnapshot,
        [string]$ClientId,
        [string]$ClientNameSnapshot,
        [string]$ChannelProvider,
        [string]$ChannelId,
        [string]$ChannelNameSnapshot,
        [string]$OwnerId,
        [string]$OwnerNameSnapshot,
        [object[]]$Media = @(),
        [object]$OperationContext,
        [object]$Actor,
        [string]$CorrelationId,
        [string]$CausationId,
        [string]$Source = 'RenderKitBroker'
    )

    $context = New-RenderKitEngineOperationContext `
        -OperationName 'NewRenderKitPublication' `
        -OperationContext $OperationContext `
        -Actor $Actor `
        -CorrelationId $CorrelationId `
        -CausationId $CausationId `
        -Source $Source
    if (-not (Test-RenderKitEngineActorContext -OperationContext $context)) {
        return New-RenderKitEngineFailureResult `
            -OperationContext $context `
            -Code 'RK_ACCESS_CONTEXT_MISSING' `
            -Message 'Creating a RenderKit publication requires an actor context.'
    }
    try {
        $publication = New-RenderKitPublicationRecord `
            -Title $Title `
            -Description $Description `
            -Status $Status `
            -StartUtc $StartUtc `
            -EndUtc $EndUtc `
            -TimeZone $TimeZone `
            -ProjectId $ProjectId `
            -ProjectNameSnapshot $ProjectNameSnapshot `
            -ClientId $ClientId `
            -ClientNameSnapshot $ClientNameSnapshot `
            -ChannelProvider $ChannelProvider `
            -ChannelId $ChannelId `
            -ChannelNameSnapshot $ChannelNameSnapshot `
            -OwnerId $OwnerId `
            -OwnerNameSnapshot $OwnerNameSnapshot `
            -Media @($Media | Where-Object { $null -ne $_ })
        $created = Add-RenderKitPublicationRecord `
            -Publication $publication
        return New-RenderKitResult -Data $created -OperationContext $context
    }
    catch {
        return New-RenderKitEnginePublicationFailure `
            -OperationContext $context `
            -Exception $_.Exception
    }
}

function Set-RenderKitEnginePublication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PublicationId,
        [Parameter(Mandatory)][int]$ExpectedRevision,
        [Parameter(Mandatory)][hashtable]$Changes,
        [object]$OperationContext,
        [object]$Actor,
        [string]$CorrelationId,
        [string]$CausationId,
        [string]$Source = 'RenderKitBroker'
    )

    $context = New-RenderKitEngineOperationContext `
        -OperationName 'SetRenderKitPublication' `
        -OperationContext $OperationContext `
        -Actor $Actor `
        -CorrelationId $CorrelationId `
        -CausationId $CausationId `
        -Source $Source
    if (-not (Test-RenderKitEngineActorContext -OperationContext $context)) {
        return New-RenderKitEngineFailureResult `
            -OperationContext $context `
            -Code 'RK_ACCESS_CONTEXT_MISSING' `
            -Message 'Updating a RenderKit publication requires an actor context.'
    }
    try {
        if ($Changes.Count -eq 0) {
            throw [System.ArgumentException]::new(
                'At least one publication field must be supplied.')
        }
        $updated = Update-RenderKitPublicationRecord `
            -Id $PublicationId `
            -ExpectedRevision $ExpectedRevision `
            -Changes $Changes
        return New-RenderKitResult -Data $updated -OperationContext $context
    }
    catch {
        return New-RenderKitEnginePublicationFailure `
            -OperationContext $context `
            -Exception $_.Exception
    }
}

function New-RenderKitEnginePublicationFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$OperationContext,
        [Parameter(Mandatory)][System.Exception]$Exception
    )

    $code = if ($Exception -is [System.ArgumentException]) {
        'RK_VALIDATION_FAILED'
    }
    elseif ($Exception -is [System.Collections.Generic.KeyNotFoundException]) {
        'RK_NOT_FOUND'
    }
    elseif ($Exception -is [System.InvalidOperationException]) {
        'RK_CONFLICT'
    }
    else {
        'RK_STORAGE_UNAVAILABLE'
    }
    return New-RenderKitEngineFailureResult `
        -OperationContext $OperationContext `
        -Code $code `
        -Message $Exception.Message
}

function New-RenderKitEngineProjectSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$RegistryEntry
    )

    $propertyNames = @($RegistryEntry.PSObject.Properties.Name)
    $metadataPath = $null
    $version = $null
    $updatedAtUtc = $null
    if ($propertyNames -contains 'metadataPath') {
        $metadataPath = [string]$RegistryEntry.metadataPath
    }
    if ($propertyNames -contains 'version') {
        $version = [string]$RegistryEntry.version
    }
    if ($propertyNames -contains 'updatedAtUtc') {
        $updatedAtUtc = [string]$RegistryEntry.updatedAtUtc
    }

    return [PSCustomObject]@{
        id            = [string]$RegistryEntry.id
        name          = [string]$RegistryEntry.name
        rootPath      = [string]$RegistryEntry.rootPath
        metadataPath  = $metadataPath
        version       = $version
        exists        = [bool]$RegistryEntry.exists
        updatedAtUtc  = $updatedAtUtc
    }
}

function Get-RenderKitEngineProjectList {
    [CmdletBinding()]
    param(
        [string]$ProjectName,
        [Nullable[bool]]$Exists,
        [object]$OperationContext,
        [object]$Actor,
        [string]$CorrelationId,
        [string]$CausationId,
        [string]$Source = 'RenderKitBroker'
    )

    $context = New-RenderKitEngineOperationContext `
        -OperationName 'GetRenderKitProjectList' `
        -OperationContext $OperationContext `
        -Actor $Actor `
        -CorrelationId $CorrelationId `
        -CausationId $CausationId `
        -Source $Source

    try {
        $registry = Read-RenderKitProjectRegistry
        $projects = @($registry.projects | ForEach-Object { New-RenderKitEngineProjectSummary -RegistryEntry $_ })
        if (-not [string]::IsNullOrWhiteSpace($ProjectName)) {
            $projects = @($projects | Where-Object { [string]$_.name -eq $ProjectName })
        }
        if ($PSBoundParameters.ContainsKey('Exists')) {
            $projects = @($projects | Where-Object { [bool]$_.exists -eq [bool]$Exists })
        }

        return New-RenderKitResult -Data @($projects | Sort-Object name, rootPath) -OperationContext $context
    }
    catch {
        return New-RenderKitEngineFailureResult `
            -OperationContext $context `
            -Code 'RK_STORAGE_UNAVAILABLE' `
            -Message $_.Exception.Message
    }
}

function Get-RenderKitEngineProjectDetail {
    [CmdletBinding()]
    param(
        [string]$ProjectId,
        [string]$ProjectName,
        [string]$ProjectRoot,
        [object]$OperationContext,
        [object]$Actor,
        [string]$CorrelationId,
        [string]$CausationId,
        [string]$Source = 'RenderKitBroker'
    )

    $context = New-RenderKitEngineOperationContext `
        -OperationName 'GetRenderKitProjectDetail' `
        -OperationContext $OperationContext `
        -Actor $Actor `
        -CorrelationId $CorrelationId `
        -CausationId $CausationId `
        -Source $Source

    try {
        $registry = Read-RenderKitProjectRegistry
    }
    catch {
        return New-RenderKitEngineFailureResult `
            -OperationContext $context `
            -Code 'RK_STORAGE_UNAVAILABLE' `
            -Message $_.Exception.Message
    }

    $projectMatches = @($registry.projects)
    if (-not [string]::IsNullOrWhiteSpace($ProjectId)) {
        $projectMatches = @($projectMatches | Where-Object { [string]$_.id -eq $ProjectId })
    }
    if (-not [string]::IsNullOrWhiteSpace($ProjectName)) {
        $projectMatches = @($projectMatches | Where-Object { [string]$_.name -eq $ProjectName })
    }
    if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
        $fullRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
        $projectMatches = @($projectMatches | Where-Object { [string]$_.rootPath -eq $fullRoot })
    }

    if ($projectMatches.Count -eq 0) {
        return New-RenderKitEngineFailureResult `
            -OperationContext $context `
            -Code 'RK_NOT_FOUND' `
            -Message 'RenderKit project was not found.' `
            -Details ([PSCustomObject]@{ projectId = $ProjectId; projectName = $ProjectName; projectRoot = $ProjectRoot })
    }
    if ($projectMatches.Count -gt 1) {
        return New-RenderKitEngineFailureResult `
            -OperationContext $context `
            -Code 'RK_CONFLICT' `
            -Message 'Multiple RenderKit projects matched the requested detail lookup.' `
            -Details ([PSCustomObject]@{ matchCount = $projectMatches.Count; projectName = $ProjectName })
    }

    $entry = $projectMatches[0]
    $metadata = $null
    $metadataError = $null
    $entryPropertyNames = @($entry.PSObject.Properties.Name)
    $entryMetadataPath = $null
    if ($entryPropertyNames -contains 'metadataPath') {
        $entryMetadataPath = [string]$entry.metadataPath
    }
    if ([bool]$entry.exists -and
        -not [string]::IsNullOrWhiteSpace($entryMetadataPath) -and
        (Test-Path -LiteralPath $entryMetadataPath -PathType Leaf)) {
        try {
            $metadata = Read-RenderKitJsonFile -Path $entryMetadataPath
        }
        catch {
            $metadataError = $_.Exception.Message
        }
    }

    $detail = [PSCustomObject]@{
        summary       = New-RenderKitEngineProjectSummary -RegistryEntry $entry
        metadata      = $metadata
        metadataError = $metadataError
    }

    return New-RenderKitResult -Data $detail -OperationContext $context
}
