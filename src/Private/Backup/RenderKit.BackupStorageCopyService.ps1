function Test-BackupPathLooksLikeUri {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [string]$Path
    )

    return [bool](-not [string]::IsNullOrWhiteSpace($Path) -and $Path -match '^[a-z][a-z0-9+.-]*://')
}

function Test-BackupPathEquivalent {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [string]$Left,
        [string]$Right
    )

    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) {
        return $false
    }
    if ((Test-BackupPathLooksLikeUri -Path $Left) -or (Test-BackupPathLooksLikeUri -Path $Right)) {
        return [string]::Equals($Left, $Right, [System.StringComparison]::OrdinalIgnoreCase)
    }

    try {
        $leftFull = [System.IO.Path]::GetFullPath($Left).TrimEnd('\', '/')
        $rightFull = [System.IO.Path]::GetFullPath($Right).TrimEnd('\', '/')
        return [string]::Equals($leftFull, $rightFull, [System.StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        return [string]::Equals($Left, $Right, [System.StringComparison]::OrdinalIgnoreCase)
    }
}

function New-BackupCopyVerifyPlan {
    [CmdletBinding()]
    param(
        [object[]]$StorageTiers,
        [object]$StorageCascade
    )

    $tiers = @($StorageTiers | Sort-Object order, id)
    $maxAttempts = 1
    foreach ($tier in $tiers) {
        $retries = if ($tier.copy -and $tier.copy.PSObject.Properties.Name -contains 'maxRetries') {
            [int]$tier.copy.maxRetries
        }
        else {
            0
        }
        $maxAttempts = [Math]::Max($maxAttempts, $retries + 1)
    }

    return [PSCustomObject]@{
        schemaVersion = '1.0'
        enabled       = $tiers.Count -gt 0
        state         = 'Planned'
        algorithm     = 'SHA256'
        scope         = 'ArchiveArtifact'
        healthCheck   = [PSCustomObject]@{
            enabled          = $true
            createTargetRoot = $true
            writeProbe       = $true
            freeSpaceCheck   = $true
        }
        verify        = [PSCustomObject]@{
            afterEveryTier       = $true
            method               = 'ChecksumCompare'
            releaseRequires      = 'ArchiveIntegrityAndRequiredStorageTiersVerified'
            primaryTierRequired  = $true
            requiredTierIds      = if ($StorageCascade) { @($StorageCascade.requiredTierIds) } else { @($tiers | Where-Object { [bool]$_.required } | ForEach-Object { [string]$_.id }) }
            allTierVerification  = $false
        }
        retry         = [PSCustomObject]@{
            maxAttempts      = $maxAttempts
            defaultDelaySecs = 5
            retryOn          = @('Unavailable', 'CopyFailed', 'VerifyFailed')
        }
        report        = [PSCustomObject]@{
            includeTierResults = $true
            includeHealth      = $true
            includeRelease     = $true
        }
    }
}

function Get-BackupStorageTierArchivePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Tier,
        [Parameter(Mandatory)]
        [string]$ArchivePath
    )

    $target = if ($Tier.target -and $Tier.target.PSObject.Properties.Name -contains 'value') {
        [string]$Tier.target.value
    }
    elseif ($Tier.PSObject.Properties.Name -contains 'path') {
        [string]$Tier.path
    }
    else {
        $null
    }

    if ([string]::IsNullOrWhiteSpace($target)) {
        return $null
    }
    if (Test-BackupPathLooksLikeUri -Path $target) {
        $leaf = Split-Path -Path $ArchivePath -Leaf
        return ($target.TrimEnd('/') + '/' + $leaf)
    }

    return Join-Path -Path $target -ChildPath (Split-Path -Path $ArchivePath -Leaf)
}

function Test-BackupStorageTierHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Tier,
        [int64]$RequiredBytes = 0,
        [switch]$CreateTargetRoot
    )

    $target = if ($Tier.target -and $Tier.target.PSObject.Properties.Name -contains 'value') {
        [string]$Tier.target.value
    }
    elseif ($Tier.PSObject.Properties.Name -contains 'path') {
        [string]$Tier.path
    }
    else {
        $null
    }
    $checkedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    $adapter = if ($Tier.PSObject.Properties.Name -contains 'adapter') { [string]$Tier.adapter } else { 'FileSystem' }
    $adapterId = if ($Tier.PSObject.Properties.Name -contains 'adapterId' -and
        -not [string]::IsNullOrWhiteSpace([string]$Tier.adapterId)) {
        [string]$Tier.adapterId
    }
    else {
        Resolve-BackupAdapterId -Type Storage -Name $adapter
    }
    $failureSimulation = Get-BackupFailureSimulation -Source $Tier

    if (Test-BackupFailureSimulationShouldFail -Simulation $failureSimulation -Scenario 'MissingTarget' -Attempt 1) {
        return [PSCustomObject]@{
            healthy       = $false
            state         = 'Failed'
            reason        = 'MissingTarget'
            checkedAtUtc  = $checkedAtUtc
            target        = $target
            adapter       = $adapter
            adapterId     = $adapterId
            canWrite      = $false
            freeBytes     = $null
            requiredBytes = $RequiredBytes
            failureClass  = New-BackupFailureClassification `
                -Scenario 'MissingTarget' `
                -Stage 'StorageHealthCheck' `
                -Attempt 1 `
                -Message "Simulated missing storage target for tier '$($Tier.name)'."
            error         = "Simulated missing storage target for tier '$($Tier.name)'."
        }
    }

    if (Test-BackupFailureSimulationShouldFail -Simulation $failureSimulation -Scenario 'FullDisk' -Attempt 1) {
        return [PSCustomObject]@{
            healthy       = $false
            state         = 'InsufficientSpace'
            reason        = 'InsufficientFreeSpace'
            checkedAtUtc  = $checkedAtUtc
            target        = $target
            adapter       = $adapter
            adapterId     = $adapterId
            canWrite      = $true
            created       = $false
            freeBytes     = 0
            requiredBytes = $RequiredBytes
            failureClass  = New-BackupFailureClassification `
                -Scenario 'FullDisk' `
                -Stage 'StorageHealthCheck' `
                -Attempt 1 `
                -Message "Simulated full storage target for tier '$($Tier.name)'."
            error         = "Simulated full storage target for tier '$($Tier.name)'."
        }
    }

    if ([string]::IsNullOrWhiteSpace($target)) {
        return [PSCustomObject]@{
            healthy       = $false
            state         = 'Failed'
            reason        = 'MissingTarget'
            checkedAtUtc  = $checkedAtUtc
            target        = $target
            adapter       = $adapter
            adapterId     = $adapterId
            canWrite      = $false
            freeBytes     = $null
            requiredBytes = $RequiredBytes
            error         = "Storage tier '$($Tier.name)' does not define a target."
        }
    }

    $adapterDefinition = Get-BackupAdapterDefinition -Type Storage -Name $adapterId
    if (-not $adapterDefinition) {
        return [PSCustomObject]@{
            healthy       = -not [bool]$Tier.required
            state         = 'AdapterRequired'
            reason        = 'StorageAdapterNotRegistered'
            checkedAtUtc  = $checkedAtUtc
            target        = $target
            adapter       = $adapter
            adapterId     = $adapterId
            canWrite      = $false
            freeBytes     = $null
            requiredBytes = $RequiredBytes
            error         = "Storage tier '$($Tier.name)' requires registered adapter '$adapterId'."
        }
    }

    try {
        $adapterHealth = Invoke-BackupAdapterOperation `
            -Adapter $adapterDefinition `
            -Operation TestHealth `
            -Context ([PSCustomObject]@{
                tier             = $Tier
                target           = $target
                requiredBytes    = $RequiredBytes
                createTargetRoot = [bool]$CreateTargetRoot
            })
        return [PSCustomObject]@{
            healthy       = [bool]$adapterHealth.healthy
            state         = [string]$adapterHealth.state
            reason        = [string]$adapterHealth.reason
            checkedAtUtc  = $checkedAtUtc
            target        = $target
            adapter       = $adapter
            adapterId     = $adapterId
            adapterVersion = [string]$adapterDefinition.version
            canWrite      = [bool]$adapterHealth.canWrite
            created       = if ($adapterHealth.PSObject.Properties.Name -contains 'created') { [bool]$adapterHealth.created } else { $false }
            freeBytes     = if ($adapterHealth.PSObject.Properties.Name -contains 'freeBytes') { $adapterHealth.freeBytes } else { $null }
            requiredBytes = $RequiredBytes
            adapterResult = $adapterHealth
            error         = [string]$adapterHealth.error
        }
    }
    catch {
        return [PSCustomObject]@{
            healthy       = $false
            state         = 'Failed'
            reason        = 'HealthCheckFailed'
            checkedAtUtc  = $checkedAtUtc
            target        = $target
            adapter       = $adapter
            adapterId     = $adapterId
            adapterVersion = [string]$adapterDefinition.version
            canWrite      = $false
            created       = $false
            freeBytes     = $null
            requiredBytes = $RequiredBytes
            error         = $_.Exception.Message
        }
    }
}

function Invoke-BackupStorageTierCopyVerify {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,
        [Parameter(Mandatory)]
        [string]$ArchivePath,
        [Parameter(Mandatory)]
        [object]$Tier,
        [Parameter(Mandatory)]
        [string]$ExpectedHash,
        [int64]$ExpectedSizeBytes,
        [string]$Algorithm = 'SHA256'
    )

    $targetPath = Get-BackupStorageTierArchivePath -Tier $Tier -ArchivePath $ArchivePath
    $health = Test-BackupStorageTierHealth `
        -Tier $Tier `
        -RequiredBytes $ExpectedSizeBytes `
        -CreateTargetRoot

    $result = [ordered]@{
        tierId          = [string]$Tier.id
        tierName        = [string]$Tier.name
        profile         = [string]$Tier.profile
        storageAdapterId = [string]$health.adapterId
        verifierAdapterId = if ($Tier.verify -and $Tier.verify.PSObject.Properties.Name -contains 'adapterId') {
            [string]$Tier.verify.adapterId
        }
        else {
            'verifier.sha256'
        }
        required        = [bool]$Tier.required
        targetPath      = $targetPath
        health          = $health
        attempts        = @()
        copied          = $false
        verified        = $false
        skipped         = $false
        state           = 'Planned'
        sourcePath      = $SourcePath
        sourceHash      = $ExpectedHash
        targetHash      = $null
        sizeBytes       = $null
        failureClass    = $null
        error           = $null
        completedAtUtc  = $null
    }

    if (-not [bool]$health.canWrite) {
        $result.state = if ([string]$health.state -eq 'AdapterRequired') { 'AdapterRequired' } else { 'Failed' }
        $result.skipped = [string]$health.state -eq 'AdapterRequired'
        $result.error = [string]$health.error
        return [PSCustomObject]$result
    }
    if (-not [bool]$health.healthy) {
        $result.state = 'Failed'
        $result.error = [string]$health.error
        return [PSCustomObject]$result
    }

    $storageAdapter = Get-BackupAdapterDefinition `
        -Type Storage `
        -Name ([string]$result.storageAdapterId)
    $verifierAdapter = Get-BackupAdapterDefinition `
        -Type Verifier `
        -Name ([string]$result.verifierAdapterId)
    if (-not $storageAdapter -or -not $verifierAdapter) {
        $missingAdapterId = if (-not $storageAdapter) {
            [string]$result.storageAdapterId
        }
        else {
            [string]$result.verifierAdapterId
        }
        $result.state = 'AdapterRequired'
        $result.skipped = $true
        $result.error = "Backup adapter '$missingAdapterId' is not registered."
        return [PSCustomObject]$result
    }

    $maxRetries = if ($Tier.copy -and $Tier.copy.PSObject.Properties.Name -contains 'maxRetries') {
        [int]$Tier.copy.maxRetries
    }
    else {
        0
    }
    $retryDelay = if ($Tier.copy -and $Tier.copy.PSObject.Properties.Name -contains 'retryDelaySeconds') {
        [int]$Tier.copy.retryDelaySeconds
    }
    else {
        5
    }
    $maxAttempts = [Math]::Max(1, $maxRetries + 1)
    $attempts = New-Object System.Collections.Generic.List[object]

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $attemptStarted = (Get-Date).ToUniversalTime()
        $failureClass = $null
        try {
            $failureSimulation = Get-BackupFailureSimulation -Source $Tier
            if (Test-BackupFailureSimulationShouldFail -Simulation $failureSimulation -Scenario 'TransientStorageCopy' -Attempt $attempt) {
                $failureClass = New-BackupFailureClassification `
                    -Scenario 'TransientStorageCopy' `
                    -Stage 'CopyingToStorageTier' `
                    -Attempt $attempt `
                    -Message "Simulated transient storage copy failure for tier '$($Tier.name)' on attempt $attempt."
                throw [string]$failureClass.message
            }

            $samePath = Test-BackupPathEquivalent `
                -Left $SourcePath `
                -Right $targetPath
            $writeResult = if ($samePath) {
                [PSCustomObject]@{
                    copied     = $false
                    targetPath = $targetPath
                    sizeBytes  = $ExpectedSizeBytes
                }
            }
            else {
                Invoke-BackupAdapterOperation `
                    -Adapter $storageAdapter `
                    -Operation Write `
                    -Context ([PSCustomObject]@{
                        sourcePath = $SourcePath
                        targetPath = $targetPath
                        tier       = $Tier
                        attempt    = $attempt
                        expectedSizeBytes = $ExpectedSizeBytes
                    })
            }
            $result.copied = [bool]$writeResult.copied

            $verification = Invoke-BackupAdapterOperation `
                -Adapter $verifierAdapter `
                -Operation Verify `
                -Context ([PSCustomObject]@{
                    sourcePath       = $SourcePath
                    targetPath       = $targetPath
                    tier             = $Tier
                    expectedHash     = $ExpectedHash
                    expectedSizeBytes = $ExpectedSizeBytes
                    algorithm        = $Algorithm
                    writeResult      = $writeResult
                })
            $result.targetHash = [string]$verification.targetHash
            $result.sizeBytes = [int64]$verification.sizeBytes
            if (-not [bool]$verification.verified) {
                $verificationError = if ([string]::IsNullOrWhiteSpace([string]$verification.error)) {
                    "Storage tier '$($Tier.name)' verification failed."
                }
                else {
                    [string]$verification.error
                }
                throw $verificationError
            }

            $attempts.Add([PSCustomObject]@{
                    attempt      = $attempt
                    state        = 'Verified'
                    startedAtUtc = $attemptStarted.ToString('o')
                    endedAtUtc   = (Get-Date).ToUniversalTime().ToString('o')
                    failureClass = $null
                    error        = $null
                })
            $result.verified = $true
            $result.state = 'Verified'
            $result.completedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            break
        }
        catch {
            $attempts.Add([PSCustomObject]@{
                    attempt      = $attempt
                    state        = 'Failed'
                    startedAtUtc = $attemptStarted.ToString('o')
                    endedAtUtc   = (Get-Date).ToUniversalTime().ToString('o')
                    failureClass = $failureClass
                    error        = $_.Exception.Message
                })
            $result.error = $_.Exception.Message
            $result.failureClass = $failureClass
            $result.state = 'Failed'
            if ($attempt -lt $maxAttempts -and $retryDelay -gt 0) {
                Start-Sleep -Seconds $retryDelay
            }
        }
    }

    $result.attempts = @($attempts.ToArray())
    return [PSCustomObject]$result
}

function Invoke-BackupStorageTierCopyVerifyChain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ArchivePath,
        [Parameter(Mandatory)]
        [object[]]$StorageTiers,
        [object]$StorageCascade,
        [Parameter(Mandatory)]
        [string]$ExpectedHash,
        [int64]$ExpectedSizeBytes,
        [string]$Algorithm = 'SHA256',
        [bool]$ArchiveIntegrityPassed = $true
    )

    $results = New-Object System.Collections.Generic.List[object]
    $orderedTiers = @($StorageTiers | Sort-Object order, id)
    $lastVerifiedPath = $ArchivePath
    foreach ($tier in $orderedTiers) {
        $tierResult = Invoke-BackupStorageTierCopyVerify `
            -SourcePath $lastVerifiedPath `
            -ArchivePath $ArchivePath `
            -Tier $tier `
            -ExpectedHash $ExpectedHash `
            -ExpectedSizeBytes $ExpectedSizeBytes `
            -Algorithm $Algorithm

        $results.Add($tierResult)
        if ([bool]$tierResult.verified -and -not (Test-BackupPathLooksLikeUri -Path ([string]$tierResult.targetPath))) {
            $lastVerifiedPath = [string]$tierResult.targetPath
        }
    }

    $resultArray = @($results.ToArray())
    $primaryTierId = if ($StorageCascade -and $StorageCascade.PSObject.Properties.Name -contains 'primaryTierId') {
        [string]$StorageCascade.primaryTierId
    }
    elseif ($orderedTiers.Count -gt 0) {
        [string]$orderedTiers[0].id
    }
    else {
        $null
    }
    $requiredTierIds = if ($StorageCascade -and $StorageCascade.PSObject.Properties.Name -contains 'requiredTierIds' -and $StorageCascade.requiredTierIds) {
        @($StorageCascade.requiredTierIds | ForEach-Object { [string]$_ })
    }
    else {
        @($orderedTiers | Where-Object { [bool]$_.required } | ForEach-Object { [string]$_.id })
    }
    $primaryResult = @($resultArray | Where-Object { [string]$_.tierId -eq $primaryTierId } | Select-Object -First 1)
    $requiredResults = @($resultArray | Where-Object { $requiredTierIds -contains [string]$_.tierId })
    $failedRequired = @($requiredResults | Where-Object { -not [bool]$_.verified })
    $failedOptional = @($resultArray | Where-Object { -not [bool]$_.required -and -not [bool]$_.verified })
    $verifiedCount = @($resultArray | Where-Object { [bool]$_.verified }).Count
    $adapterPlannedCount = @($resultArray | Where-Object { [string]$_.state -eq 'AdapterRequired' }).Count
    $canReleaseSource = [bool](
        $ArchiveIntegrityPassed -and
        $primaryResult.Count -gt 0 -and
        [bool]$primaryResult[0].verified -and
        $failedRequired.Count -eq 0
    )

    return [PSCustomObject]@{
        schemaVersion = '1.0'
        state         = if ($canReleaseSource) { 'Verified' } else { 'Blocked' }
        startedAtUtc  = if ($resultArray.Count -gt 0 -and $resultArray[0].attempts.Count -gt 0) { $resultArray[0].attempts[0].startedAtUtc } else { $null }
        completedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        artifact      = [PSCustomObject]@{
            path          = $ArchivePath
            sizeBytes     = $ExpectedSizeBytes
            hashAlgorithm = $Algorithm
            hash          = $ExpectedHash
        }
        summary       = [PSCustomObject]@{
            tierCount           = $orderedTiers.Count
            verifiedTierCount   = $verifiedCount
            failedRequiredCount = $failedRequired.Count
            failedOptionalCount = $failedOptional.Count
            adapterPlannedCount = $adapterPlannedCount
        }
        tiers         = @($resultArray)
        release       = [PSCustomObject]@{
            canReleaseSource        = $canReleaseSource
            reason                  = if ($canReleaseSource) { 'ArchiveIntegrityAndRequiredStorageTiersVerified' } else { 'RequiredStorageTierVerificationFailed' }
            archiveIntegrityPassed  = [bool]$ArchiveIntegrityPassed
            primaryTierVerified     = [bool]($primaryResult.Count -gt 0 -and [bool]$primaryResult[0].verified)
            requiredTierIds         = @($requiredTierIds)
            failedRequiredTierIds   = @($failedRequired | ForEach-Object { [string]$_.tierId })
            failedOptionalTierIds   = @($failedOptional | ForEach-Object { [string]$_.tierId })
        }
    }
}
