function Get-RenderKitEventJobSubscriptionCatalog {
    [CmdletBinding()]
    param()

    if ($script:RenderKitEventJobSubscriptionCatalog) {
        return $script:RenderKitEventJobSubscriptionCatalog
    }

    $root = Get-RenderKitModuleResourceRoot -RelativePath 'Resources/Automation'
    $path = Join-Path -Path $root -ChildPath 'EventJobSubscriptions.psd1'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "RenderKit event/job subscription catalog was not found at '$path'."
    }

    $catalog = Import-PowerShellDataFile -LiteralPath $path
    if (-not $catalog.CatalogVersion -or -not $catalog.Subscriptions) {
        throw "RenderKit event/job subscription catalog '$path' is invalid."
    }

    $script:RenderKitEventJobSubscriptionCatalog = $catalog
    return $catalog
}

function Get-RenderKitEventJobSubscription {
    [CmdletBinding()]
    param(
        [string]$EventType
    )

    $catalog = Get-RenderKitEventJobSubscriptionCatalog
    $subscriptions = @($catalog.Subscriptions | Where-Object {
        [bool]$_.Enabled
    })

    if (-not [string]::IsNullOrWhiteSpace($EventType)) {
        $subscriptions = @($subscriptions | Where-Object {
            [string]$_.EventType -eq $EventType
        })
    }

    return $subscriptions
}

function New-RenderKitJobFromDomainEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Event,
        [Parameter(Mandatory)]
        [object]$Subscription
    )

    return New-RenderKitJob `
        -JobType ([string]$Subscription.JobType) `
        -TriggerEventId ([string]$Event.id) `
        -CorrelationId ([string]$Event.correlationId) `
        -Payload ([PSCustomObject]@{
            subscriptionId = [string]$Subscription.Id
            eventType      = [string]$Event.eventType
            aggregateType  = [string]$Event.aggregateType
            aggregateId    = [string]$Event.aggregateId
            occurredAtUtc  = [string]$Event.occurredAtUtc
            eventPayload   = $Event.payload
        })
}

function Add-RenderKitEventJobIfMissing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Job
    )

    $normalizedJob = ConvertTo-RenderKitJobVNext -Job $Job
    $path = Get-RenderKitJobStorePath
    $appendResult = New-Object System.Collections.Generic.List[bool]

    # RS-1512: the duplicate check and append must share the same file transaction.
    # A read-before-write check outside this lock allows concurrent bridge invocations
    # to observe the same missing job and enqueue duplicate work before either writer
    # commits its update.
    Invoke-RenderKitJsonFileTransaction `
        -Path $path `
        -DefaultValue (New-RenderKitJobStore) `
        -Depth 30 `
        -Validator { param($value) Test-RenderKitJobStore $value } `
        -Update {
            param($store)

            $store = ConvertTo-RenderKitJobStoreVNext -Store $store
            $alreadyExists = @($store.jobs | Where-Object {
                [string]$_.triggerEventId -eq [string]$normalizedJob.triggerEventId -and
                [string]$_.jobType -eq [string]$normalizedJob.jobType
            }).Count -gt 0

            if (-not $alreadyExists) {
                $store.jobs = @($store.jobs) + @($normalizedJob)
                $store.updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
                $appendResult.Add($true)
            }

            return $store
        } |
        Out-Null

    # RS-1512: this reference-type marker records whether this invocation appended
    # while holding the JobStore lock. Looking up the generated job id afterwards is
    # insufficient because callers may legitimately retry with the same job object/id.
    if ($appendResult.Count -eq 0) {
        return $null
    }

    return $normalizedJob
}

function Invoke-RenderKitEventJobBridge {
    [CmdletBinding()]
    param(
        [string]$EventType
    )

    $events = @(Get-RenderKitPendingDomainEvent -EventType $EventType)
    $createdJobs = New-Object System.Collections.Generic.List[object]
    $processedEvents = New-Object System.Collections.Generic.List[string]

    foreach ($event in $events) {
        $subscriptions = @(Get-RenderKitEventJobSubscription `
            -EventType ([string]$event.eventType))

        foreach ($subscription in $subscriptions) {
            $job = New-RenderKitJobFromDomainEvent `
                -Event $event `
                -Subscription $subscription
            $createdJob = Add-RenderKitEventJobIfMissing -Job $job
            if ($createdJob) {
                $createdJobs.Add($createdJob)
            }
        }

        Set-RenderKitDomainEventStatus `
            -EventId ([string]$event.id) `
            -Status Processed
        $processedEvents.Add([string]$event.id)
    }

    return [PSCustomObject]@{
        ProcessedEventCount = [int]$processedEvents.Count
        CreatedJobCount     = [int]$createdJobs.Count
        ProcessedEventIds   = @($processedEvents.ToArray())
        CreatedJobs         = @($createdJobs.ToArray())
    }
}
