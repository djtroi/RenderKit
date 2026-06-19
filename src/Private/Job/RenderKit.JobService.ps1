function New-RenderKitJobStore {
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        tool          = 'RenderKit'
        schemaVersion = '1.0'
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

    if (-not ($store.PSObject.Properties.Name -contains 'jobs') -or
        $null -eq $store.jobs) {
        $store | Add-Member -NotePropertyName jobs `
            -NotePropertyValue @() `
            -Force
    }

    return $store
}

function New-RenderKitJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobType,
        [object]$Payload,
        [string]$TriggerEventId,
        [string]$CorrelationId
    )

    if ([string]::IsNullOrWhiteSpace($CorrelationId)) {
        $CorrelationId = [guid]::NewGuid().ToString()
    }

    $now = (Get-Date).ToUniversalTime().ToString('o')
    return [PSCustomObject]@{
        id             = [guid]::NewGuid().ToString()
        jobType        = $JobType
        status         = 'Queued'
        createdAtUtc   = $now
        updatedAtUtc   = $now
        startedAtUtc   = $null
        completedAtUtc = $null
        attempts       = 0
        maxAttempts    = 3
        triggerEventId = $TriggerEventId
        correlationId  = $CorrelationId
        lastError      = $null
        payload        = $Payload
    }
}

function Add-RenderKitJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Job
    )

    $path = Get-RenderKitJobStorePath
    Invoke-RenderKitJsonFileTransaction `
        -Path $path `
        -DefaultValue (New-RenderKitJobStore) `
        -Depth 20 `
        -Validator { param($value) Test-RenderKitJobStore $value } `
        -Update {
            param($store)

            if (-not ($store.PSObject.Properties.Name -contains 'jobs') -or
                $null -eq $store.jobs) {
                $store | Add-Member -NotePropertyName jobs `
                    -NotePropertyValue @() `
                    -Force
            }

            $store.jobs = @($store.jobs) + @($Job)
            $store.updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            return $store
        } |
        Out-Null

    return $Job
}

function Get-RenderKitQueuedJob {
    [CmdletBinding()]
    param(
        [string]$JobType
    )

    $store = Read-RenderKitJobStore
    $jobs = @($store.jobs | Where-Object { [string]$_.status -eq 'Queued' })
    if (-not [string]::IsNullOrWhiteSpace($JobType)) {
        $jobs = @($jobs | Where-Object { [string]$_.jobType -eq $JobType })
    }

    return @($jobs | Sort-Object createdAtUtc, id)
}

function Set-RenderKitJobStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobId,
        [Parameter(Mandatory)]
        [ValidateSet('Queued', 'Running', 'Succeeded', 'Failed', 'Cancelled')]
        [string]$Status,
        [string]$ErrorMessage
    )

    $path = Get-RenderKitJobStorePath
    Invoke-RenderKitJsonFileTransaction `
        -Path $path `
        -DefaultValue (New-RenderKitJobStore) `
        -Depth 20 `
        -Validator { param($value) Test-RenderKitJobStore $value } `
        -Update {
            param($store)

            $found = $false
            foreach ($job in @($store.jobs)) {
                if ([string]$job.id -eq $JobId) {
                    $now = (Get-Date).ToUniversalTime().ToString('o')
                    $job.status = $Status
                    $job.updatedAtUtc = $now
                    if ($Status -eq 'Running') {
                        $job.startedAtUtc = $now
                        $job.attempts = [int]$job.attempts + 1
                    }
                    if ($Status -in @('Succeeded', 'Failed', 'Cancelled')) {
                        $job.completedAtUtc = $now
                    }
                    $job.lastError = if ($Status -eq 'Failed') {
                        $ErrorMessage
                    }
                    else {
                        $null
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

    $store = Read-RenderKitJobStore
    return @($store.jobs |
        Where-Object { [string]$_.id -eq [string]$job[0].id } |
        Select-Object -First 1)
}