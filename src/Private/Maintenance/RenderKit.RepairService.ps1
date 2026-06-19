function New-RenderKitRepairComponentResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [ValidateSet('Healthy', 'Repaired', 'Warning', 'Failed')]
        [string]$Status,
        [string]$Message,
        [object]$Data
    )

    return [PSCustomObject]@{
        Name         = $Name
        Status       = $Status
        Message      = $Message
        Data         = $Data
        CheckedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Test-RenderKitStoreHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [scriptblock]$Reader
    )

    try {
        $value = & $Reader
        return New-RenderKitRepairComponentResult `
            -Name $Name `
            -Status Healthy `
            -Message "$Name is readable." `
            -Data $value
    }
    catch {
        return New-RenderKitRepairComponentResult `
            -Name $Name `
            -Status Failed `
            -Message $_.Exception.Message
    }
}

function Repair-RenderKitJsonStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [scriptblock]$Reader,
        [switch]$RestoreFromBackup
    )

    $health = Test-RenderKitStoreHealth -Name $Name -Reader $Reader
    if ($health.Status -eq 'Healthy') {
        return $health
    }

    if (-not $RestoreFromBackup) {
        return $health
    }

    try {
        Restore-RenderKitJsonFileBackup -Path $Path | Out-Null
        & $Reader | Out-Null
        return New-RenderKitRepairComponentResult `
            -Name $Name `
            -Status Repaired `
            -Message "$Name was restored from backup."
    }
    catch {
        return New-RenderKitRepairComponentResult `
            -Name $Name `
            -Status Failed `
            -Message "Could not repair $Name from backup: $($_.Exception.Message)"
    }
}

function Invoke-RenderKitStateRepair {
    [CmdletBinding()]
    param(
        [switch]$RestoreFromBackup
    )

    $components = New-Object System.Collections.Generic.List[object]

    foreach ($kind in @('Configuration', 'State', 'Cache', 'UserData')) {
        try {
            $root = Get-RenderKitStorageRoot -Kind $kind -Ensure
            $components.Add((New-RenderKitRepairComponentResult `
                -Name "Storage:$kind" `
                -Status Healthy `
                -Message "Storage root exists." `
                -Data ([PSCustomObject]@{ Path = $root })))
        }
        catch {
            $components.Add((New-RenderKitRepairComponentResult `
                -Name "Storage:$kind" `
                -Status Failed `
                -Message $_.Exception.Message))
        }
    }

    $components.Add((Repair-RenderKitJsonStore `
        -Name 'ProjectRegistry' `
        -Path (Get-RenderKitProjectRegistryPath) `
        -Reader { Read-RenderKitProjectRegistry } `
        -RestoreFromBackup:$RestoreFromBackup))

    try {
        $registry = Repair-RenderKitProjectRegistry
        $components.Add((New-RenderKitRepairComponentResult `
            -Name 'ProjectRegistryEntries' `
            -Status Repaired `
            -Message 'Project registry entries were reconciled with the filesystem.' `
            -Data ([PSCustomObject]@{
                ProjectCount = @($registry.projects).Count
            })))
    }
    catch {
        $components.Add((New-RenderKitRepairComponentResult `
            -Name 'ProjectRegistryEntries' `
            -Status Failed `
            -Message $_.Exception.Message))
    }

    $components.Add((Repair-RenderKitJsonStore `
        -Name 'EventStore' `
        -Path (Get-RenderKitEventStorePath) `
        -Reader { Read-RenderKitEventStore } `
        -RestoreFromBackup:$RestoreFromBackup))

    $components.Add((Repair-RenderKitJsonStore `
        -Name 'JobStore' `
        -Path (Get-RenderKitJobStorePath) `
        -Reader { Read-RenderKitJobStore } `
        -RestoreFromBackup:$RestoreFromBackup))

    $failed = @($components.ToArray() | Where-Object { $_.Status -eq 'Failed' })
    return [PSCustomObject]@{
        Status        = if ($failed.Count -eq 0) { 'Healthy' } else { 'Failed' }
        FailedCount   = [int]$failed.Count
        ComponentCount = [int]$components.Count
        Components    = @($components.ToArray())
        CheckedAtUtc  = (Get-Date).ToUniversalTime().ToString('o')
    }
}