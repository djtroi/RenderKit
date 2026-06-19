function Get-RenderKitEventStoreSchemaVersion {
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    return '1.1'
}

function Set-RenderKitEventObjectProperty {
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

function New-RenderKitEventIntegrity {
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        algorithm    = $null
        previousHash = $null
        hash         = $null
    }
}

function New-RenderKitEventStore {
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        tool          = 'RenderKit'
        schemaVersion = Get-RenderKitEventStoreSchemaVersion
        updatedAtUtc  = (Get-Date).ToUniversalTime().ToString('o')
        events        = @()
    }
}

function Test-RenderKitEventStore {
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
        -ArtifactType EventStore `
        -Version ([string]$Store.schemaVersion)

    return [bool]($compatibility.CanRead -and $compatibility.CanWrite)
}

function ConvertTo-RenderKitDomainEventVNext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Event
    )

    $now = (Get-Date).ToUniversalTime().ToString('o')
    if ([string]::IsNullOrWhiteSpace([string]$Event.id)) {
        Set-RenderKitEventObjectProperty -InputObject $Event -Name id -Value ([guid]::NewGuid().ToString())
    }
    if (-not ($Event.PSObject.Properties.Name -contains 'eventId') -or
        [string]::IsNullOrWhiteSpace([string]$Event.eventId)) {
        Set-RenderKitEventObjectProperty -InputObject $Event -Name eventId -Value ([string]$Event.id)
    }
    if (-not ($Event.PSObject.Properties.Name -contains 'eventSchemaVersion')) {
        Set-RenderKitEventObjectProperty -InputObject $Event -Name eventSchemaVersion -Value '1.0'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Event.occurredAtUtc)) {
        Set-RenderKitEventObjectProperty -InputObject $Event -Name occurredAtUtc -Value $now
    }
    if ([string]::IsNullOrWhiteSpace([string]$Event.correlationId)) {
        Set-RenderKitEventObjectProperty -InputObject $Event -Name correlationId -Value ([guid]::NewGuid().ToString())
    }
    if ([string]::IsNullOrWhiteSpace([string]$Event.status)) {
        Set-RenderKitEventObjectProperty -InputObject $Event -Name status -Value 'Pending'
    }

    $data = $null
    if ($Event.PSObject.Properties.Name -contains 'data') {
        $data = $Event.data
    }
    elseif ($Event.PSObject.Properties.Name -contains 'payload') {
        $data = $Event.payload
    }
    Set-RenderKitEventObjectProperty -InputObject $Event -Name data -Value $data
    Set-RenderKitEventObjectProperty -InputObject $Event -Name payload -Value $data

    $defaults = @{
        aggregateVersion = $null
        actor = $null
        category = 'Domain'
        retention = 'Indefinite'
        imported = $false
        lastError = $null
        processingAttempts = 0
        integrity = (New-RenderKitEventIntegrity)
    }
    foreach ($key in $defaults.Keys) {
        if (-not ($Event.PSObject.Properties.Name -contains $key)) {
            Set-RenderKitEventObjectProperty `
                -InputObject $Event `
                -Name $key `
                -Value $defaults[$key]
        }
    }

    return $Event
}

function ConvertTo-RenderKitEventStoreVNext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Store
    )

    if (-not ($Store.PSObject.Properties.Name -contains 'events') -or
        $null -eq $Store.events) {
        Set-RenderKitEventObjectProperty -InputObject $Store -Name events -Value @()
    }

    $events = @()
    foreach ($event in @($Store.events)) {
        $events += ConvertTo-RenderKitDomainEventVNext -Event $event
    }

    Set-RenderKitEventObjectProperty `
        -InputObject $Store `
        -Name schemaVersion `
        -Value (Get-RenderKitEventStoreSchemaVersion)
    Set-RenderKitEventObjectProperty -InputObject $Store -Name events -Value $events

    return $Store
}

function Read-RenderKitEventStore {
    [CmdletBinding()]
    param()

    $path = Get-RenderKitEventStorePath
    $store = Read-RenderKitJsonFile `
        -Path $path `
        -AllowMissing `
        -Validator { param($value) Test-RenderKitEventStore $value }

    if (-not $store) {
        return New-RenderKitEventStore
    }

    return ConvertTo-RenderKitEventStoreVNext -Store $store
}

function New-RenderKitDomainEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EventType,
        [Parameter(Mandatory)]
        [string]$AggregateType,
        [Parameter(Mandatory)]
        [string]$AggregateId,
        [object]$Payload,
        [object]$Data,
        [string]$CorrelationId,
        [string]$CausationId,
        [Nullable[int]]$AggregateVersion,
        [object]$Actor,
        [ValidateSet('Domain', 'Operational', 'Diagnostic', 'Security')]
        [string]$Category = 'Domain',
        [string]$Retention = 'Indefinite',
        [switch]$Imported
    )

    if ([string]::IsNullOrWhiteSpace($CorrelationId)) {
        $CorrelationId = [guid]::NewGuid().ToString()
    }
    if ($null -eq $Data) {
        $Data = $Payload
    }

    $aggregateVersionValue = $null
    if ($AggregateVersion.HasValue) {
        $aggregateVersionValue = [int]$AggregateVersion.Value
    }

    return [PSCustomObject]@{
        id                 = [guid]::NewGuid().ToString()
        eventId            = $null
        eventType          = $EventType
        eventSchemaVersion = '1.0'
        aggregateType      = $AggregateType
        aggregateId        = $AggregateId
        aggregateVersion   = $aggregateVersionValue
        occurredAtUtc      = (Get-Date).ToUniversalTime().ToString('o')
        correlationId      = $CorrelationId
        causationId        = $CausationId
        actor              = $Actor
        category           = $Category
        retention          = $Retention
        imported           = [bool]$Imported
        status             = 'Pending'
        processedAtUtc     = $null
        processingAttempts = 0
        lastError          = $null
        integrity          = New-RenderKitEventIntegrity
        data               = $Data
        payload            = $Data
    } | ForEach-Object {
        $_.eventId = [string]$_.id
        $_
    }
}

function Add-RenderKitDomainEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Event
    )

    $normalizedEvent = ConvertTo-RenderKitDomainEventVNext -Event $Event
    $path = Get-RenderKitEventStorePath
    Invoke-RenderKitJsonFileTransaction `
        -Path $path `
        -DefaultValue (New-RenderKitEventStore) `
        -Depth 30 `
        -Validator { param($value) Test-RenderKitEventStore $value } `
        -Update {
            param($store)

            $store = ConvertTo-RenderKitEventStoreVNext -Store $store
            $store.events = @($store.events) + @($normalizedEvent)
            $store.updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            return $store
        } |
        Out-Null

    return $normalizedEvent
}

function Get-RenderKitDomainEventList {
    [CmdletBinding()]
    param(
        [string]$Status,
        [string]$EventType,
        [string]$AggregateType,
        [string]$AggregateId,
        [string]$CorrelationId,
        [string]$Category
    )

    $store = Read-RenderKitEventStore
    $events = @($store.events)
    if (-not [string]::IsNullOrWhiteSpace($Status)) {
        $events = @($events | Where-Object { [string]$_.status -eq $Status })
    }
    if (-not [string]::IsNullOrWhiteSpace($EventType)) {
        $events = @($events | Where-Object { [string]$_.eventType -eq $EventType })
    }
    if (-not [string]::IsNullOrWhiteSpace($AggregateType)) {
        $events = @($events | Where-Object { [string]$_.aggregateType -eq $AggregateType })
    }
    if (-not [string]::IsNullOrWhiteSpace($AggregateId)) {
        $events = @($events | Where-Object { [string]$_.aggregateId -eq $AggregateId })
    }
    if (-not [string]::IsNullOrWhiteSpace($CorrelationId)) {
        $events = @($events | Where-Object { [string]$_.correlationId -eq $CorrelationId })
    }
    if (-not [string]::IsNullOrWhiteSpace($Category)) {
        $events = @($events | Where-Object { [string]$_.category -eq $Category })
    }

    return @($events | Sort-Object occurredAtUtc, id)
}

function Get-RenderKitDomainEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EventId
    )

    return @(Get-RenderKitDomainEventList | Where-Object {
        [string]$_.id -eq $EventId -or [string]$_.eventId -eq $EventId
    } | Select-Object -First 1)
}

function Get-RenderKitPendingDomainEvent {
    [CmdletBinding()]
    param(
        [string]$EventType
    )

    return Get-RenderKitDomainEventList -Status Pending -EventType $EventType
}

function Set-RenderKitDomainEventStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EventId,
        [Parameter(Mandatory)]
        [ValidateSet('Pending', 'Processed', 'Failed')]
        [string]$Status,
        [string]$ErrorMessage
    )

    $path = Get-RenderKitEventStorePath
    Invoke-RenderKitJsonFileTransaction `
        -Path $path `
        -DefaultValue (New-RenderKitEventStore) `
        -Depth 30 `
        -Validator { param($value) Test-RenderKitEventStore $value } `
        -Update {
            param($store)

            $store = ConvertTo-RenderKitEventStoreVNext -Store $store
            $found = $false
            foreach ($event in @($store.events)) {
                if ([string]$event.id -eq $EventId -or [string]$event.eventId -eq $EventId) {
                    $event.status = $Status
                    $event.processedAtUtc = if ($Status -eq 'Pending') {
                        $null
                    }
                    else {
                        (Get-Date).ToUniversalTime().ToString('o')
                    }
                    if ($Status -eq 'Failed') {
                        $event.processingAttempts = [int]$event.processingAttempts + 1
                        $event.lastError = [PSCustomObject]@{
                            message       = $ErrorMessage
                            occurredAtUtc = (Get-Date).ToUniversalTime().ToString('o')
                        }
                    }
                    elseif ($Status -ne 'Pending') {
                        $event.lastError = $null
                    }
                    $found = $true
                    break
                }
            }
            if (-not $found) {
                throw "RenderKit domain event '$EventId' was not found."
            }

            $store.updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            return $store
        } |
        Out-Null
}

function Write-RenderKitProjectLifecycleEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Metadata,
        [Parameter(Mandatory)]
        [string]$ProjectRoot,
        [Parameter(Mandatory)]
        [string]$FromStatus,
        [Parameter(Mandatory)]
        [string]$ToStatus,
        [string]$Reason,
        [string]$Source = 'System',
        [object]$Actor
    )

    if ($FromStatus -eq $ToStatus) {
        return $null
    }

    $event = New-RenderKitDomainEvent `
        -EventType 'ProjectLifecycleStatusChanged' `
        -AggregateType 'Project' `
        -AggregateId ([string]$Metadata.project.id) `
        -Actor $Actor `
        -Payload ([PSCustomObject]@{
            projectName = [string]$Metadata.project.name
            projectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
            fromStatus  = $FromStatus
            toStatus    = $ToStatus
            reason      = $Reason
            source      = $Source
        })

    return Add-RenderKitDomainEvent -Event $event
}