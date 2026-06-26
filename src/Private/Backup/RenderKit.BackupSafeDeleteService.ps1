function Get-BackupSafeDeleteValue {
    [CmdletBinding()]
    param(
        [object]$InputObject,
        [Parameter(Mandatory)]
        [string]$Name,
        [object]$DefaultValue = $null
    )

    if ($null -eq $InputObject) {
        return $DefaultValue
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return $InputObject[$Name]
        }

        return $DefaultValue
    }

    if ($InputObject.PSObject.Properties.Name -contains $Name) {
        return $InputObject.$Name
    }

    return $DefaultValue
}

function ConvertTo-BackupSafeDeleteBoolean {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [object]$Value,
        [bool]$DefaultValue = $false
    )

    if ($null -eq $Value) {
        return $DefaultValue
    }
    if ($Value -is [bool]) {
        return [bool]$Value
    }
    if ($Value -is [string]) {
        $normalized = $Value.Trim().ToLowerInvariant()
        if ($normalized -in @('true', '1', 'yes', 'y', 'ja', 'j')) {
            return $true
        }
        if ($normalized -in @('false', '0', 'no', 'n', 'nein')) {
            return $false
        }
    }

    return [bool]$Value
}

function New-BackupSafeDeletePolicy {
    [CmdletBinding()]
    param(
        [ValidateSet('RemoveSourceAfterVerified', 'KeepSource', 'NeverDelete')]
        [string]$Mode = 'RemoveSourceAfterVerified',
        [bool]$RequiresArchiveIntegrity = $true,
        [bool]$RequiresDecodeValidation = $true,
        [ValidateSet('WhenProducedMediaExists', 'Always', 'Never')]
        [string]$DecodeValidationScope = 'WhenProducedMediaExists',
        [bool]$RequiresPrimaryTierVerification = $true,
        [bool]$RequiresStorageCascadeVerification = $true,
        [bool]$RequiresAllTierVerification = $false,
        [string[]]$RequiredStorageTierIds = @()
    )

    return [PSCustomObject]@{
        schemaVersion    = '1.0'
        mode             = $Mode
        releaseCondition = 'ArchiveIntegrityDecodeAndRequiredStorageTiersVerified'
        rules            = [PSCustomObject]@{
            requiresArchiveIntegrity          = [bool]$RequiresArchiveIntegrity
            requiresDecodeValidation          = [bool]$RequiresDecodeValidation
            decodeValidationScope             = $DecodeValidationScope
            requiresPrimaryTierVerification   = [bool]$RequiresPrimaryTierVerification
            requiresStorageCascadeVerification = [bool]$RequiresStorageCascadeVerification
            requiresAllTierVerification        = [bool]$RequiresAllTierVerification
            requiredStorageTierIds             = @($RequiredStorageTierIds)
        }
        actions          = [PSCustomObject]@{
            onPass = 'DeleteSourceWhenRequested'
            onFail = 'KeepSourceAndFailBeforeRemoval'
            dryRun = 'KeepSource'
        }
        report           = [PSCustomObject]@{
            includePassedRules = $true
            includeFailedRules = $true
            includeEvidence    = $true
        }
    }
}

function Test-BackupSafeDeletePolicy {
    [CmdletBinding()]
    param(
        [object]$Policy,
        [object]$ArchiveInfo,
        [object]$StorageVerification,
        [object[]]$MergeValidations = @(),
        [bool]$DryRun,
        [bool]$DeleteRequested
    )

    if (-not $Policy) {
        $Policy = New-BackupSafeDeletePolicy
    }

    $rules = Get-BackupSafeDeleteValue -InputObject $Policy -Name 'rules' -DefaultValue $Policy
    $mode = [string](Get-BackupSafeDeleteValue -InputObject $Policy -Name 'mode' -DefaultValue 'RemoveSourceAfterVerified')
    $requiresArchiveIntegrity = ConvertTo-BackupSafeDeleteBoolean `
        -Value (Get-BackupSafeDeleteValue -InputObject $rules -Name 'requiresArchiveIntegrity' -DefaultValue $true) `
        -DefaultValue $true
    $requiresDecodeValidation = ConvertTo-BackupSafeDeleteBoolean `
        -Value (Get-BackupSafeDeleteValue -InputObject $rules -Name 'requiresDecodeValidation' -DefaultValue $true) `
        -DefaultValue $true
    $decodeValidationScope = [string](Get-BackupSafeDeleteValue -InputObject $rules -Name 'decodeValidationScope' -DefaultValue 'WhenProducedMediaExists')
    if ([string]::IsNullOrWhiteSpace($decodeValidationScope)) {
        $decodeValidationScope = 'WhenProducedMediaExists'
    }
    $requiresPrimaryTierVerification = ConvertTo-BackupSafeDeleteBoolean `
        -Value (Get-BackupSafeDeleteValue -InputObject $rules -Name 'requiresPrimaryTierVerification' -DefaultValue $true) `
        -DefaultValue $true
    $requiresStorageCascadeVerification = ConvertTo-BackupSafeDeleteBoolean `
        -Value (Get-BackupSafeDeleteValue -InputObject $rules -Name 'requiresStorageCascadeVerification' -DefaultValue $true) `
        -DefaultValue $true
    $requiresAllTierVerification = ConvertTo-BackupSafeDeleteBoolean `
        -Value (Get-BackupSafeDeleteValue -InputObject $rules -Name 'requiresAllTierVerification' -DefaultValue $false) `
        -DefaultValue $false
    $requiredStorageTierIds = @(
        Get-BackupSafeDeleteValue -InputObject $rules -Name 'requiredStorageTierIds' -DefaultValue @() |
            ForEach-Object { [string]$_ }
    )

    $passedRules = New-Object System.Collections.Generic.List[object]
    $failedRules = New-Object System.Collections.Generic.List[object]
    $contentIntegrity = Get-BackupSafeDeleteValue -InputObject $ArchiveInfo -Name 'contentIntegrity'
    $archiveIntegrityChecked = ConvertTo-BackupSafeDeleteBoolean `
        -Value (Get-BackupSafeDeleteValue -InputObject $contentIntegrity -Name 'checked' -DefaultValue $false) `
        -DefaultValue $false
    $archiveIntegrityMatches = ConvertTo-BackupSafeDeleteBoolean `
        -Value (Get-BackupSafeDeleteValue -InputObject $contentIntegrity -Name 'isMatch' -DefaultValue $false) `
        -DefaultValue $false
    $release = Get-BackupSafeDeleteValue -InputObject $StorageVerification -Name 'release'
    $canReleaseSource = ConvertTo-BackupSafeDeleteBoolean `
        -Value (Get-BackupSafeDeleteValue -InputObject $release -Name 'canReleaseSource' -DefaultValue $false) `
        -DefaultValue $false
    $primaryTierVerified = ConvertTo-BackupSafeDeleteBoolean `
        -Value (Get-BackupSafeDeleteValue -InputObject $release -Name 'primaryTierVerified' -DefaultValue $false) `
        -DefaultValue $false
    $failedRequiredTierIds = @(
        Get-BackupSafeDeleteValue -InputObject $release -Name 'failedRequiredTierIds' -DefaultValue @() |
            ForEach-Object { [string]$_ }
    )
    $storageTierResults = @(
        Get-BackupSafeDeleteValue -InputObject $StorageVerification -Name 'tiers' -DefaultValue @()
    )
    $mergeValidationResults = @($MergeValidations | Where-Object { $null -ne $_ })
    $failedMergeValidations = @(
        $mergeValidationResults |
            Where-Object {
                -not (ConvertTo-BackupSafeDeleteBoolean `
                    -Value (Get-BackupSafeDeleteValue -InputObject $_ -Name 'succeeded' -DefaultValue $false) `
                    -DefaultValue $false)
            }
    )

    $evidence = [PSCustomObject]@{
        archiveIntegrity   = [PSCustomObject]@{
            required = [bool]$requiresArchiveIntegrity
            checked  = [bool]$archiveIntegrityChecked
            isMatch  = [bool]$archiveIntegrityMatches
        }
        decodeValidation   = [PSCustomObject]@{
            required       = [bool]$requiresDecodeValidation
            scope          = $decodeValidationScope
            validationCount = $mergeValidationResults.Count
            failedCount    = $failedMergeValidations.Count
            failedAssetIds = @(
                $failedMergeValidations |
                    ForEach-Object {
                        [string](Get-BackupSafeDeleteValue -InputObject $_ -Name 'assetId' -DefaultValue '')
                    } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )
        }
        storageVerification = [PSCustomObject]@{
            required              = [bool]$requiresStorageCascadeVerification
            state                 = [string](Get-BackupSafeDeleteValue -InputObject $StorageVerification -Name 'state' -DefaultValue $null)
            canReleaseSource      = [bool]$canReleaseSource
            primaryTierVerified   = [bool]$primaryTierVerified
            requiredStorageTierIds = @($requiredStorageTierIds)
            failedRequiredTierIds = @($failedRequiredTierIds)
        }
    }

    if (-not $DeleteRequested) {
        return [PSCustomObject]@{
            schemaVersion  = '1.0'
            state          = 'NotRequested'
            canDelete      = $false
            reason         = 'DeleteNotRequested'
            evaluatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            passedRules    = @()
            failedRules    = @()
            evidence       = $evidence
        }
    }

    if ($DryRun) {
        $failedRules.Add([PSCustomObject]@{
                rule   = 'DryRun'
                reason = 'DryRunKeepsSource'
            })
    }

    if ($mode -in @('KeepSource', 'NeverDelete')) {
        $failedRules.Add([PSCustomObject]@{
                rule   = 'DeletePolicyMode'
                reason = 'PolicyKeepsSource'
                mode   = $mode
            })
    }
    else {
        $passedRules.Add([PSCustomObject]@{
                rule   = 'DeletePolicyMode'
                reason = 'DeletePolicyAllowsVerifiedRemoval'
                mode   = $mode
            })
    }

    if ($requiresArchiveIntegrity) {
        if ($archiveIntegrityChecked -and $archiveIntegrityMatches) {
            $passedRules.Add([PSCustomObject]@{
                    rule   = 'ArchiveIntegrity'
                    reason = 'ArchiveIntegrityVerified'
                })
        }
        else {
            $failedRules.Add([PSCustomObject]@{
                    rule    = 'ArchiveIntegrity'
                    reason  = 'ArchiveIntegrityMissingOrFailed'
                    checked = [bool]$archiveIntegrityChecked
                    isMatch = [bool]$archiveIntegrityMatches
                })
        }
    }

    if ($requiresDecodeValidation -and $decodeValidationScope -ne 'Never') {
        if ($mergeValidationResults.Count -eq 0 -and $decodeValidationScope -eq 'WhenProducedMediaExists') {
            $passedRules.Add([PSCustomObject]@{
                    rule   = 'DecodeValidation'
                    reason = 'NoProducedMediaRequiresDecodeValidation'
                })
        }
        elseif ($mergeValidationResults.Count -eq 0) {
            $failedRules.Add([PSCustomObject]@{
                    rule   = 'DecodeValidation'
                    reason = 'DecodeValidationMissing'
                })
        }
        elseif ($failedMergeValidations.Count -eq 0) {
            $passedRules.Add([PSCustomObject]@{
                    rule            = 'DecodeValidation'
                    reason          = 'DecodeValidationPassed'
                    validationCount = $mergeValidationResults.Count
                })
        }
        else {
            $failedRules.Add([PSCustomObject]@{
                    rule           = 'DecodeValidation'
                    reason         = 'DecodeValidationFailed'
                    failedAssetIds = @($evidence.decodeValidation.failedAssetIds)
                })
        }
    }

    if ($requiresStorageCascadeVerification) {
        if ($canReleaseSource) {
            $passedRules.Add([PSCustomObject]@{
                    rule   = 'StorageCascadeVerification'
                    reason = 'StorageCascadeReleasedSource'
                })
        }
        else {
            $failedRules.Add([PSCustomObject]@{
                    rule                 = 'StorageCascadeVerification'
                    reason               = 'StorageCascadeVerificationFailed'
                    failedRequiredTierIds = @($failedRequiredTierIds)
                })
        }
    }

    if ($requiresPrimaryTierVerification) {
        if ($primaryTierVerified) {
            $passedRules.Add([PSCustomObject]@{
                    rule   = 'PrimaryTierVerification'
                    reason = 'PrimaryTierVerified'
                })
        }
        else {
            $failedRules.Add([PSCustomObject]@{
                    rule   = 'PrimaryTierVerification'
                    reason = 'PrimaryTierVerificationFailed'
                })
        }
    }

    if ($requiresAllTierVerification) {
        $failedTierIds = @(
            $storageTierResults |
                Where-Object {
                    -not (ConvertTo-BackupSafeDeleteBoolean `
                        -Value (Get-BackupSafeDeleteValue -InputObject $_ -Name 'verified' -DefaultValue $false) `
                        -DefaultValue $false)
                } |
                ForEach-Object { [string](Get-BackupSafeDeleteValue -InputObject $_ -Name 'tierId' -DefaultValue '') } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
        if ($failedTierIds.Count -eq 0) {
            $passedRules.Add([PSCustomObject]@{
                    rule   = 'AllTierVerification'
                    reason = 'AllStorageTiersVerified'
                })
        }
        else {
            $failedRules.Add([PSCustomObject]@{
                    rule          = 'AllTierVerification'
                    reason        = 'OneOrMoreStorageTiersFailed'
                    failedTierIds = @($failedTierIds)
                })
        }
    }

    $canDelete = $failedRules.Count -eq 0
    return [PSCustomObject]@{
        schemaVersion  = '1.0'
        state          = if ($canDelete) { 'Allowed' } else { 'Blocked' }
        canDelete      = [bool]$canDelete
        reason         = if ($canDelete) { 'SafeDeleteChecksPassed' } else { [string]$failedRules[0].reason }
        evaluatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        passedRules    = @($passedRules.ToArray())
        failedRules    = @($failedRules.ToArray())
        evidence       = $evidence
    }
}
