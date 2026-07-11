function ConvertTo-BackupFailureScenarioList {
    [CmdletBinding()]
    param(
        [string[]]$Scenario = @()
    )

    $seen = @{}
    $items = New-Object System.Collections.Generic.List[string]
    foreach ($value in @($Scenario)) {
        $name = ([string]$value).Trim()
        if ([string]::IsNullOrWhiteSpace($name) -or $name -eq 'None') {
            continue
        }
        if (-not $seen.ContainsKey($name)) {
            $seen[$name] = $true
            $items.Add($name)
        }
    }

    return @($items.ToArray())
}

function New-BackupFailureSimulationPlan {
    [CmdletBinding()]
    param(
        [string[]]$Scenario = @(),
        [ValidateRange(1, 20)]
        [int]$FailAttempts = 1
    )

    $scenarios = @(ConvertTo-BackupFailureScenarioList -Scenario $Scenario)
    return [PSCustomObject]@{
        schemaVersion = '1.0'
        enabled       = $scenarios.Count -gt 0
        scenarios     = @($scenarios)
        failAttempts  = [Math]::Max(1, [int]$FailAttempts)
        createdAtUtc  = (Get-Date).ToUniversalTime().ToString('o')
        stages        = [PSCustomObject]@{
            abortRequested       = [PSCustomObject]@{ stage = 'PlanningEncoding'; action = 'CancelJob' }
            missingTarget        = [PSCustomObject]@{ stage = 'StorageHealthCheck'; action = 'FailRequiredTier' }
            fullDisk             = [PSCustomObject]@{ stage = 'StorageHealthCheck'; action = 'ReportInsufficientSpace' }
            transientStorageCopy = [PSCustomObject]@{ stage = 'CopyingToStorageTier'; action = 'FailThenRetry' }
            corruptChunk         = [PSCustomObject]@{ stage = 'Encoding'; action = 'FailThenRetryChunk' }
        }
    }
}

function New-BackupFailureRecoveryPolicy {
    [CmdletBinding()]
    param(
        [ValidateSet('None', 'AbortRequested', 'MissingTarget', 'FullDisk', 'CorruptChunk', 'TransientStorageCopy')]
        [string[]]$SimulateFailure = @(),
        [ValidateRange(1, 20)]
        [int]$MaxChunkRetryAttempts = 3,
        [ValidateRange(0, 3600)]
        [int]$ChunkRetryDelaySeconds = 1,
        [ValidateRange(1, 20)]
        [int]$SimulatedFailureCount = 1
    )

    $simulation = New-BackupFailureSimulationPlan `
        -Scenario $SimulateFailure `
        -FailAttempts $SimulatedFailureCount

    return [PSCustomObject]@{
        schemaVersion = '1.0'
        enabled       = $true
        state         = 'Planned'
        strategy      = 'DetectClassifyRetryOrBlockRelease'
        retry         = [PSCustomObject]@{
            chunk = [PSCustomObject]@{
                enabled             = $true
                maxAttempts         = [int]$MaxChunkRetryAttempts
                retryDelaySeconds   = [int]$ChunkRetryDelaySeconds
                retryFrom           = 'LastFailedChunk'
                persistentChunkIndex = $true
            }
            storage = [PSCustomObject]@{
                enabled             = $true
                source              = 'TierPolicy'
                retryOn             = @('Unavailable', 'CopyFailed', 'VerifyFailed', 'TransientStorageCopy')
                blockSourceReleaseOnRequiredFailure = $true
            }
        }
        classification = @(
            [PSCustomObject]@{ scenario = 'AbortRequested'; category = 'UserOrSimulationAbort'; retryable = $false; terminal = $true; releaseSource = $false }
            [PSCustomObject]@{ scenario = 'MissingTarget'; category = 'MissingStorageTarget'; retryable = $false; terminal = $false; releaseSource = $false }
            [PSCustomObject]@{ scenario = 'FullDisk'; category = 'InsufficientStorageCapacity'; retryable = $false; terminal = $false; releaseSource = $false }
            [PSCustomObject]@{ scenario = 'TransientStorageCopy'; category = 'TransientStorageCopy'; retryable = $true; terminal = $false; releaseSource = $false }
            [PSCustomObject]@{ scenario = 'CorruptChunk'; category = 'ChunkOutputInvalid'; retryable = $true; terminal = $false; releaseSource = $false }
        )
        simulation    = $simulation
    }
}

function Get-BackupFailureSimulation {
    [CmdletBinding()]
    param(
        [object]$Source
    )

    if (-not $Source) {
        return $null
    }
    if ($Source.PSObject.Properties.Name -contains 'failureSimulation') {
        return $Source.failureSimulation
    }
    if ($Source.PSObject.Properties.Name -contains 'simulation') {
        return $Source.simulation
    }

    return $null
}

function Test-BackupFailureScenario {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [object]$Simulation,
        [Parameter(Mandatory)]
        [string]$Scenario
    )

    if (-not $Simulation) {
        return $false
    }
    if ($Simulation.PSObject.Properties.Name -contains 'enabled' -and -not [bool]$Simulation.enabled) {
        return $false
    }

    $scenarios = @()
    if ($Simulation.PSObject.Properties.Name -contains 'scenarios') {
        $scenarios = @($Simulation.scenarios | ForEach-Object { [string]$_ })
    }
    elseif ($Simulation.PSObject.Properties.Name -contains 'scenario') {
        $scenarios = @([string]$Simulation.scenario)
    }

    return $scenarios -contains $Scenario
}

function Test-BackupFailureSimulationShouldFail {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [object]$Simulation,
        [Parameter(Mandatory)]
        [string]$Scenario,
        [ValidateRange(1, 1000)]
        [int]$Attempt = 1
    )

    if (-not (Test-BackupFailureScenario -Simulation $Simulation -Scenario $Scenario)) {
        return $false
    }

    $failAttempts = if ($Simulation.PSObject.Properties.Name -contains 'failAttempts') {
        [Math]::Max(1, [int]$Simulation.failAttempts)
    }
    else {
        1
    }

    return [int]$Attempt -le $failAttempts
}

function New-BackupFailureClassification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Scenario,
        [string]$Stage,
        [int]$Attempt,
        [string]$Message
    )

    $category = switch ($Scenario) {
        'AbortRequested' { 'UserOrSimulationAbort'; break }
        'MissingTarget' { 'MissingStorageTarget'; break }
        'FullDisk' { 'InsufficientStorageCapacity'; break }
        'TransientStorageCopy' { 'TransientStorageCopy'; break }
        'CorruptChunk' { 'ChunkOutputInvalid'; break }
        default { 'UnknownFailure' }
    }
    $retryable = $Scenario -in @('TransientStorageCopy', 'CorruptChunk')

    return [PSCustomObject]@{
        schemaVersion = '1.0'
        scenario      = $Scenario
        category      = $category
        stage         = $Stage
        attempt       = [int]$Attempt
        retryable     = [bool]$retryable
        blocksSourceRelease = $true
        message       = $Message
        classifiedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Set-BackupFailureSimulationOnStorageTiers {
    [CmdletBinding()]
    param(
        [object[]]$StorageTiers,
        [object]$Simulation
    )

    $tiers = @($StorageTiers)
    if (-not $Simulation -or -not [bool]$Simulation.enabled -or $tiers.Count -eq 0) {
        return @($tiers)
    }

    $storageScenarios = @(
        'MissingTarget',
        'FullDisk',
        'TransientStorageCopy'
    ) | Where-Object { Test-BackupFailureScenario -Simulation $Simulation -Scenario $_ }

    if (@($storageScenarios).Count -eq 0) {
        return @($tiers)
    }

    $targetTier = @($tiers | Sort-Object order, id | Select-Object -First 1)
    if ($targetTier.Count -eq 0) {
        return @($tiers)
    }

    $targetTier[0] | Add-Member `
        -NotePropertyName failureSimulation `
        -NotePropertyValue ([PSCustomObject]@{
            schemaVersion = '1.0'
            enabled       = $true
            scenarios     = @($storageScenarios)
            failAttempts  = if ($Simulation.PSObject.Properties.Name -contains 'failAttempts') { [int]$Simulation.failAttempts } else { 1 }
            scope         = 'StorageTier'
            injectedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        }) `
        -Force

    return @($tiers)
}

function Set-BackupFailureSimulationOnEncodingCommands {
    [CmdletBinding()]
    param(
        [object[]]$Commands,
        [object]$Simulation
    )

    $commandList = @($Commands)
    if (-not $Simulation -or
        -not [bool]$Simulation.enabled -or
        -not (Test-BackupFailureScenario -Simulation $Simulation -Scenario 'CorruptChunk')) {
        return @($commandList)
    }

    $targetCommand = @(
        $commandList |
            Where-Object { [string]$_.type -eq 'EncodeChunk' -and [string]$_.state -ne 'Completed' } |
            Sort-Object assetId, index |
            Select-Object -First 1
    )
    if ($targetCommand.Count -eq 0) {
        return @($commandList)
    }

    $targetCommand[0] | Add-Member `
        -NotePropertyName failureSimulation `
        -NotePropertyValue ([PSCustomObject]@{
            schemaVersion = '1.0'
            enabled       = $true
            scenarios     = @('CorruptChunk')
            failAttempts  = if ($Simulation.PSObject.Properties.Name -contains 'failAttempts') { [int]$Simulation.failAttempts } else { 1 }
            scope         = 'EncodeChunk'
            injectedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        }) `
        -Force

    return @($commandList)
}

function Invoke-BackupFailureAbortSimulationIfRequested {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Job,
        [Parameter(Mandatory)]
        [object]$Payload,
        [string]$StageName = 'PlanningEncoding'
    )

    $simulation = if ($Payload.PSObject.Properties.Name -contains 'failureRecovery' -and $Payload.failureRecovery) {
        $Payload.failureRecovery.simulation
    }
    else {
        $null
    }

    if (-not (Test-BackupFailureScenario -Simulation $simulation -Scenario 'AbortRequested')) {
        return $false
    }

    $reason = "Simulated abort requested during '$StageName'."
    if ($Payload.control -and -not [string]::IsNullOrWhiteSpace([string]$Payload.control.statePath)) {
        $control = Read-BackupControlState -JobId ([string]$Job.id)
        $control.requestedAction = 'Cancel'
        $control.state = 'CancelRequested'
        $control.reason = $reason
        Save-BackupControlState -JobId ([string]$Job.id) -State $control | Out-Null
    }

    Stop-BackupJobForCancellation -Job $Job -Reason $reason
    throw $reason
}
