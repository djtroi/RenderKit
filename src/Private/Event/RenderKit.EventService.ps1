function New-RenderKitEventStore {
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        tool          = 'RenderKit'
        schemaVersion = '1.0'
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

    if (-not ($store.PSObject.Properties.Name -contains 'events') -or
        $null -eq $store.events) {
        $store | Add-Member -NotePropertyName events `
            -NotePropertyValue @() `
            -Force
    }

    return $store
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
        [string]$CorrelationId,
        [string]$CausationId
    )

    if ([string]::IsNullOrWhiteSpace($CorrelationId)) {
        $CorrelationId = [guid]::NewGuid().ToString()
    }

    return [PSCustomObject]@{
        id             = [guid]::NewGuid().ToString()
        eventType      = $EventType
        aggregateType  = $AggregateType
        aggregateId    = $AggregateId
        occurredAtUtc  = (Get-Date).ToUniversalTime().ToString('o')
        correlationId  = $CorrelationId
        causationId    = $CausationId
        status         = 'Pending'
        processedAtUtc = $null
        payload        = $Payload
    }
}

function Add-RenderKitDomainEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Event
    )

    $path = Get-RenderKitEventStorePath
    Invoke-RenderKitJsonFileTransaction `
        -Path $path `
        -DefaultValue (New-RenderKitEventStore) `
        -Depth 20 `
        -Validator { param($value) Test-RenderKitEventStore $value } `
        -Update {
            param($store)

            if (-not ($store.PSObject.Properties.Name -contains 'events') -or
                $null -eq $store.events) {
                $store | Add-Member -NotePropertyName events `
                    -NotePropertyValue @() `
                    -Force
            }

            $store.events = @($store.events) + @($Event)
            $store.updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            return $store
        } |
        Out-Null

    return $Event
}

function Get-RenderKitPendingDomainEvent {
    [CmdletBinding()]
    param(
        [string]$EventType
    )

    $store = Read-RenderKitEventStore
    $events = @($store.events | Where-Object { [string]$_.status -eq 'Pending' })
    if (-not [string]::IsNullOrWhiteSpace($EventType)) {
        $events = @($events | Where-Object { [string]$_.eventType -eq $EventType })
    }

    return @($events | Sort-Object occurredAtUtc, id)
}

function Set-RenderKitDomainEventStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EventId,
        [Parameter(Mandatory)]
        [ValidateSet('Pending', 'Processed', 'Failed')]
        [string]$Status
    )

    $path = Get-RenderKitEventStorePath
    Invoke-RenderKitJsonFileTransaction `
        -Path $path `
        -DefaultValue (New-RenderKitEventStore) `
        -Depth 20 `
        -Validator { param($value) Test-RenderKitEventStore $value } `
        -Update {
            param($store)

            $found = $false
            foreach ($event in @($store.events)) {
                if ([string]$event.id -eq $EventId) {
                    $event.status = $Status
                    $event.processedAtUtc = if ($Status -eq 'Pending') {
                        $null
                    }
                    else {
                        (Get-Date).ToUniversalTime().ToString('o')
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
        [string]$Source = 'System'
    )

    if ($FromStatus -eq $ToStatus) {
        return $null
    }

    $event = New-RenderKitDomainEvent `
        -EventType 'ProjectLifecycleStatusChanged' `
        -AggregateType 'Project' `
        -AggregateId ([string]$Metadata.project.id) `
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