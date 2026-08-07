Register-RenderKitFunction 'Get-BackupWorkerCapability'
function Get-BackupWorkerCapability {
    <#
.SYNOPSIS
Returns execution capabilities for local and registered backup workers.

.DESCRIPTION
Each worker reports its own encoder capabilities. The returned array is
designed for heterogeneous worker pools and includes offline registrations.
#>
    [CmdletBinding()]
    param(
        [string[]]$WorkerId,
        [switch]$Refresh,
        [switch]$OnlineOnly
    )

    $capabilities = [ordered]@{}
    foreach ($state in @(Get-RenderKitWorkerStateList)) {
        if (-not $state.capabilities -or
            [string]::IsNullOrWhiteSpace([string]$state.workerId)) {
            continue
        }
        $snapshot = $state.capabilities
        $online = [string]$state.status -in @('Starting', 'Running', 'Idle') -and
            (Test-RenderKitWorkerProcessAlive `
                -ProcessId ([int]$state.processId) `
                -MachineName ([string]$state.machine))
        $snapshot | Add-Member `
            -NotePropertyName online `
            -NotePropertyValue ([bool]$online) `
            -Force
        $snapshot | Add-Member `
            -NotePropertyName status `
            -NotePropertyValue ([string]$state.status) `
            -Force
        $capabilities[[string]$state.workerId] = $snapshot
    }

    $localWorkerId = 'local-{0}' -f (
        ConvertTo-RenderKitWorkerSafeName `
            -Value ([Environment]::MachineName.ToLowerInvariant())
    )
    $capabilities[$localWorkerId] = Get-BackupWorkerCapabilitySnapshot `
        -WorkerId $localWorkerId `
        -Refresh:$Refresh

    $result = @($capabilities.Values)
    if ($WorkerId) {
        $requested = @($WorkerId | ForEach-Object { [string]$_ })
        $result = @(
            $result |
                Where-Object { $requested -contains [string]$_.workerId }
        )
    }
    if ($OnlineOnly) {
        $result = @($result | Where-Object { [bool]$_.online })
    }
    return @($result | Sort-Object workerId)
}
