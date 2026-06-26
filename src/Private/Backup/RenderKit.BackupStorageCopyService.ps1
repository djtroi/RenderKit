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

    if ([string]::IsNullOrWhiteSpace($target)) {
        return [PSCustomObject]@{
            healthy       = $false
            state         = 'Failed'
            reason        = 'MissingTarget'
            checkedAtUtc  = $checkedAtUtc
            target        = $target
            adapter       = $adapter
            canWrite      = $false
            freeBytes     = $null
            requiredBytes = $RequiredBytes
            error         = "Storage tier '$($Tier.name)' does not define a target."
        }
    }

    if (Test-BackupPathLooksLikeUri -Path $target) {
        return [PSCustomObject]@{
            healthy       = -not [bool]$Tier.required
            state         = 'AdapterRequired'
            reason        = 'NonFileSystemTarget'
            checkedAtUtc  = $checkedAtUtc
            target        = $target
            adapter       = $adapter
            canWrite      = $false
            freeBytes     = $null
            requiredBytes = $RequiredBytes
            error         = "Storage tier '$($Tier.name)' requires adapter '$adapter'."
        }
    }

    try {
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            throw "Storage tier target '$target' is a file, not a directory."
        }
        $created = $false
        if (-not (Test-Path -LiteralPath $target -PathType Container)) {
            if (-not $CreateTargetRoot) {
                throw "Storage tier target '$target' does not exist."
            }
            New-Item -ItemType Directory -Path $target -Force | Out-Null
            $created = $true
        }

        $probePath = Join-Path -Path $target -ChildPath (".renderkit-health-{0}.tmp" -f [guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $probePath -Value 'renderkit-storage-health' -Encoding UTF8 -ErrorAction Stop
        Remove-Item -LiteralPath $probePath -Force -ErrorAction Stop

        $freeBytes = $null
        $hasEnoughSpace = $true
        try {
            $targetItem = Get-Item -LiteralPath $target -ErrorAction Stop
            if ($targetItem.PSDrive -and $null -ne $targetItem.PSDrive.Free) {
                $freeBytes = [int64]$targetItem.PSDrive.Free
                if ($RequiredBytes -gt 0) {
                    $hasEnoughSpace = $freeBytes -gt $RequiredBytes
                }
            }
        }
        catch {
            $freeBytes = $null
        }

        return [PSCustomObject]@{
            healthy       = [bool]$hasEnoughSpace
            state         = if ($hasEnoughSpace) { 'Healthy' } else { 'InsufficientSpace' }
            reason        = if ($hasEnoughSpace) { 'Writable' } else { 'InsufficientFreeSpace' }
            checkedAtUtc  = $checkedAtUtc
            target        = $target
            adapter       = $adapter
            canWrite      = $true
            created       = $created
            freeBytes     = $freeBytes
            requiredBytes = $RequiredBytes
            error         = $null
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
        try {
            $samePath = Test-BackupPathEquivalent -Left $SourcePath -Right $targetPath
            if (-not $samePath) {
                Copy-Item -LiteralPath $SourcePath -Destination $targetPath -Force -ErrorAction Stop
                $result.copied = $true
            }

            $targetItem = Get-Item -LiteralPath $targetPath -ErrorAction Stop
            $targetHash = Get-FileHash -LiteralPath $targetPath -Algorithm $Algorithm -ErrorAction Stop
            $result.targetHash = [string]$targetHash.Hash
            $result.sizeBytes = [int64]$targetItem.Length

            $hashMatches = [string]::Equals([string]$ExpectedHash, [string]$targetHash.Hash, [System.StringComparison]::OrdinalIgnoreCase)
            $sizeMatches = $ExpectedSizeBytes -le 0 -or [int64]$targetItem.Length -eq [int64]$ExpectedSizeBytes
            if (-not $hashMatches -or -not $sizeMatches) {
                throw "Storage tier '$($Tier.name)' verification failed. HashMatches=$hashMatches SizeMatches=$sizeMatches."
            }

            $attempts.Add([PSCustomObject]@{
                    attempt      = $attempt
                    state        = 'Verified'
                    startedAtUtc = $attemptStarted.ToString('o')
                    endedAtUtc   = (Get-Date).ToUniversalTime().ToString('o')
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
                    error        = $_.Exception.Message
                })
            $result.error = $_.Exception.Message
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
