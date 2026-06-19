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

function Test-RenderKitJobExistsForEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TriggerEventId,
        [Parameter(Mandatory)]
        [string]$JobType
    )

    $store = Read-RenderKitJobStore
    return [bool](@($store.jobs | Where-Object {
        [string]$_.triggerEventId -eq $TriggerEventId -and
        [string]$_.jobType -eq $JobType
    }).Count -gt 0)
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
            if (Test-RenderKitJobExistsForEvent `
                    -TriggerEventId ([string]$event.id) `
                    -JobType ([string]$subscription.JobType)) {
                continue
            }

            $job = New-RenderKitJobFromDomainEvent `
                -Event $event `
                -Subscription $subscription
            Add-RenderKitJob -Job $job | Out-Null
            $createdJobs.Add($job)
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