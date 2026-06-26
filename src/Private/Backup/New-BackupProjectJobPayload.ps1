function Resolve-BackupStorageTierProfileName {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [string]$Profile
    )

    if ([string]::IsNullOrWhiteSpace($Profile)) {
        return 'LocalFileSystem'
    }

    $normalized = ([string]$Profile).Trim().ToLowerInvariant() -replace '[^a-z0-9]', ''
    switch ($normalized) {
        { $_ -in @('fastssd', 'ssd', 'fast') } { return 'FastSSD' }
        { $_ -in @('hdd', 'harddisk', 'localhdd') } { return 'HDD' }
        { $_ -in @('nas', 'networkshare', 'smb', 'nfs') } { return 'NAS' }
        { $_ -in @('coldstorage', 'cold', 'archivevolume', 'offline') } { return 'ColdStorage' }
        { $_ -in @('tape', 'ltfs', 'lto', 'tapelibrary') } { return 'Tape' }
        { $_ -in @('clouds3', 's3', 'cloud', 'objectstorage') } { return 'CloudS3' }
        { $_ -in @('localfilesystem', 'local', 'folder') } { return 'LocalFileSystem' }
        default {
            throw "Unknown backup storage tier profile '$Profile'. Use FastSSD, HDD, NAS, ColdStorage, Tape, or CloudS3."
        }
    }
}

function Get-BackupStorageTierProfile {
    [CmdletBinding()]
    param(
        [string]$Profile = 'LocalFileSystem'
    )

    $profileName = Resolve-BackupStorageTierProfileName -Profile $Profile
    switch ($profileName) {
        'FastSSD' {
            return [PSCustomObject]@{
                name            = 'FastSSD'
                displayName     = 'Fast SSD'
                kind            = 'LocalFileSystem'
                adapter         = 'FileSystem'
                role            = 'Primary'
                speedClass      = 'HotFast'
                durabilityClass = 'WorkingCopy'
                targetKind      = 'Path'
                defaultRequired = $true
                defaultVerify   = $true
                capabilities    = @('PrimaryIngest', 'FastWrite', 'ChecksumVerify')
            }
        }
        'HDD' {
            return [PSCustomObject]@{
                name            = 'HDD'
                displayName     = 'HDD'
                kind            = 'LocalFileSystem'
                adapter         = 'FileSystem'
                role            = 'Cascade'
                speedClass      = 'Warm'
                durabilityClass = 'Nearline'
                targetKind      = 'Path'
                defaultRequired = $false
                defaultVerify   = $true
                capabilities    = @('CascadeCopy', 'ChecksumVerify')
            }
        }
        'NAS' {
            return [PSCustomObject]@{
                name            = 'NAS'
                displayName     = 'NAS'
                kind            = 'NetworkShare'
                adapter         = 'SMBOrNFS'
                role            = 'Cascade'
                speedClass      = 'Network'
                durabilityClass = 'SharedNearline'
                targetKind      = 'Path'
                defaultRequired = $false
                defaultVerify   = $true
                capabilities    = @('CascadeCopy', 'ChecksumVerify', 'NetworkTarget')
            }
        }
        'ColdStorage' {
            return [PSCustomObject]@{
                name            = 'ColdStorage'
                displayName     = 'Cold Storage'
                kind            = 'ColdStorage'
                adapter         = 'OfflineDisk'
                role            = 'ColdArchive'
                speedClass      = 'Cold'
                durabilityClass = 'OfflineArchive'
                targetKind      = 'Path'
                defaultRequired = $false
                defaultVerify   = $true
                capabilities    = @('ColdArchive', 'ChecksumVerify', 'MayBeOffline')
            }
        }
        'Tape' {
            return [PSCustomObject]@{
                name            = 'Tape'
                displayName     = 'Tape Library'
                kind            = 'TapeLibrary'
                adapter         = 'LTFS'
                role            = 'ColdArchive'
                speedClass      = 'Sequential'
                durabilityClass = 'TapeArchive'
                targetKind      = 'Uri'
                defaultRequired = $false
                defaultVerify   = $true
                capabilities    = @('ColdArchive', 'SequentialWrite', 'AdapterRequired')
            }
        }
        'CloudS3' {
            return [PSCustomObject]@{
                name            = 'CloudS3'
                displayName     = 'Cloud / S3'
                kind            = 'S3ObjectStorage'
                adapter         = 'S3'
                role            = 'CloudArchive'
                speedClass      = 'WAN'
                durabilityClass = 'ObjectStorage'
                targetKind      = 'Uri'
                defaultRequired = $false
                defaultVerify   = $true
                capabilities    = @('CloudArchive', 'ObjectStorage', 'AdapterRequired')
            }
        }
        default {
            return [PSCustomObject]@{
                name            = 'LocalFileSystem'
                displayName     = 'Local Folder'
                kind            = 'LocalFileSystem'
                adapter         = 'FileSystem'
                role            = 'Cascade'
                speedClass      = 'Warm'
                durabilityClass = 'LocalCopy'
                targetKind      = 'Path'
                defaultRequired = $false
                defaultVerify   = $true
                capabilities    = @('CascadeCopy', 'ChecksumVerify')
            }
        }
    }
}

function ConvertTo-BackupStorageTierProfileInput {
    [CmdletBinding()]
    param(
        [string[]]$Profile,
        [string[]]$Path
    )

    $tiers = New-Object System.Collections.Generic.List[hashtable]
    for ($index = 0; $index -lt @($Profile).Count; $index++) {
        $profileName = Resolve-BackupStorageTierProfileName -Profile ([string]$Profile[$index])
        $target = if ($Path -and @($Path).Count -gt $index) { [string]$Path[$index] } else { $null }
        $tiers.Add(@{
                Profile = $profileName
                Path    = $target
                Order   = ($index + 1)
                Source  = 'ProfileParameter'
            })
    }

    return @($tiers.ToArray())
}

function Read-BackupStorageTierInteractiveConfiguration {
    [CmdletBinding()]
    param()

    Write-Information 'Available storage tier profiles: FastSSD, HDD, NAS, ColdStorage, Tape, CloudS3' -InformationAction Continue
    $tiers = New-Object System.Collections.Generic.List[hashtable]
    $order = 0
    while ($true) {
        $profileInput = Read-Host 'Storage profile, blank to finish'
        if ([string]::IsNullOrWhiteSpace($profileInput)) {
            break
        }

        $profileName = Resolve-BackupStorageTierProfileName -Profile $profileInput
        $profile = Get-BackupStorageTierProfile -Profile $profileName
        $name = Read-Host ("Display name [{0}]" -f $profile.displayName)
        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = [string]$profile.displayName
        }
        $target = Read-Host ("Target {0} path/URI" -f $profile.targetKind)
        $requiredAnswer = Read-Host 'Required tier? [y/N]'
        $fallbackTo = Read-Host 'Fallback tier id/name, blank for next tier'
        $order++

        $tier = @{
            Profile  = $profileName
            Name     = $name
            Path     = $target
            Order    = $order
            Required = $requiredAnswer -match '^(y|yes|j|ja)$'
            Source   = 'Interactive'
        }
        if (-not [string]::IsNullOrWhiteSpace($fallbackTo)) {
            $tier.FallbackTo = $fallbackTo
        }
        $tiers.Add($tier)

        $more = Read-Host 'Add another storage tier? [y/N]'
        if ($more -notmatch '^(y|yes|j|ja)$') {
            break
        }
    }

    return @($tiers.ToArray())
}

function Resolve-BackupStorageTierProfileFromHashtable {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Tier,
        [int]$Index
    )

    foreach ($key in 'Profile', 'ProfileName') {
        if ($Tier.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace([string]$Tier[$key])) {
            return Resolve-BackupStorageTierProfileName -Profile ([string]$Tier[$key])
        }
    }

    $hint = @(
        if ($Tier.ContainsKey('Name')) { [string]$Tier.Name }
        if ($Tier.ContainsKey('Kind')) { [string]$Tier.Kind }
    ) -join ' '

    if ($hint -match '(?i)ssd') { return 'FastSSD' }
    if ($hint -match '(?i)nas|network|smb|nfs') { return 'NAS' }
    if ($hint -match '(?i)tape|ltfs|lto') { return 'Tape' }
    if ($hint -match '(?i)s3|cloud|object') { return 'CloudS3' }
    if ($hint -match '(?i)cold|offline') { return 'ColdStorage' }
    if ($hint -match '(?i)hdd|hard') { return 'HDD' }

    if ($Index -eq 1) {
        return 'FastSSD'
    }

    return 'HDD'
}

function New-BackupStorageCascadePlan {
    [CmdletBinding()]
    param(
        [object[]]$StorageTiers
    )

    $orderedTiers = @($StorageTiers | Sort-Object order, id)
    $stages = New-Object System.Collections.Generic.List[object]
    for ($index = 0; $index -lt $orderedTiers.Count; $index++) {
        $tier = $orderedTiers[$index]
        $stages.Add([PSCustomObject]@{
                index            = $index
                tierId           = [string]$tier.id
                tierName         = [string]$tier.name
                profile          = [string]$tier.profile
                action           = if ($index -eq 0) { 'WritePrimary' } else { 'CascadeCopy' }
                sourceTierId     = if ($index -eq 0) { $null } else { [string]$orderedTiers[$index - 1].id }
                targetKind       = [string]$tier.target.kind
                target           = [string]$tier.target.value
                verify           = $tier.verify
                required         = [bool]$tier.required
                fallbackToTierId = $tier.fallback.toTierId
                adapter          = [string]$tier.adapter
            })
    }

    return [PSCustomObject]@{
        schemaVersion     = '1.0'
        enabled           = $orderedTiers.Count -gt 0
        mode              = if ($orderedTiers.Count -gt 1) { 'Cascading' } else { 'SingleTarget' }
        strategy          = 'FastestWritableFirstThenCascade'
        primaryTierId     = if ($orderedTiers.Count -gt 0) { [string]$orderedTiers[0].id } else { $null }
        finalTierIds      = @($orderedTiers | Where-Object { [string]$_.role -in @('ColdArchive', 'CloudArchive', 'Cascade') } | ForEach-Object { [string]$_.id })
        requiredTierIds   = @($orderedTiers | Where-Object { [bool]$_.required } | ForEach-Object { [string]$_.id })
        optionalTierIds   = @($orderedTiers | Where-Object { -not [bool]$_.required } | ForEach-Object { [string]$_.id })
        supportedProfiles = @('FastSSD', 'HDD', 'NAS', 'ColdStorage', 'Tape', 'CloudS3')
        interactive       = [PSCustomObject]@{
            enabled      = $true
            command      = 'Backup-Project -ConfigureStorageTiers'
            profileParam = '-StorageTierProfile'
            pathParam    = '-StorageTierPath'
        }
        fallbackPolicy   = [PSCustomObject]@{
            enabled         = $orderedTiers.Count -gt 1
            defaultAction   = 'UseNextAvailableTier'
            failJobWhenRequiredTierFails = $true
        }
        stages           = @($stages.ToArray())
    }
}

function ConvertTo-BackupProjectStorageTier {
    [CmdletBinding()]
    param(
        [hashtable[]]$StorageTier,
        [string]$DestinationRoot,
        [string]$ArchivePath
    )

    $tiers = New-Object System.Collections.Generic.List[object]
    $index = 0
    foreach ($tier in @($StorageTier)) {
        if (-not $tier) {
            continue
        }

        $index++
        $tierName = if ($tier.ContainsKey('Name')) { [string]$tier.Name } else { "Tier$index" }
        $profileName = Resolve-BackupStorageTierProfileFromHashtable -Tier $tier -Index $index
        $profile = Get-BackupStorageTierProfile -Profile $profileName
        $tierTarget = if ($tier.ContainsKey('Path')) { [string]$tier.Path } elseif ($tier.ContainsKey('Uri')) { [string]$tier.Uri } else { $null }
        if ([string]::IsNullOrWhiteSpace($tierTarget)) {
            throw "Backup storage tier '$tierName' must provide a Path or Uri value."
        }

        $tiers.Add([PSCustomObject]@{
            id       = if ($tier.ContainsKey('Id')) { [string]$tier.Id } else { "tier-$index" }
            name     = $tierName
            profile  = [string]$profile.name
            kind     = if ($tier.ContainsKey('Kind')) { [string]$tier.Kind } else { [string]$profile.kind }
            adapter  = [string]$profile.adapter
            role     = if ($tier.ContainsKey('Role')) { [string]$tier.Role } else { if ($index -eq 1) { 'Primary' } else { [string]$profile.role } }
            order    = if ($tier.ContainsKey('Order')) { [int]$tier.Order } else { $index }
            path     = $tierTarget
            uri      = if ($tier.ContainsKey('Uri')) { [string]$tier.Uri } else { $null }
            target   = [PSCustomObject]@{
                kind  = if ([string]$profile.targetKind -eq 'Uri' -or $tierTarget -match '^[a-z][a-z0-9+.-]*://') { 'Uri' } else { 'Path' }
                value = $tierTarget
            }
            speedClass      = [string]$profile.speedClass
            durabilityClass = [string]$profile.durabilityClass
            capabilities    = @($profile.capabilities)
            required        = if ($tier.ContainsKey('Required')) { [bool]$tier.Required } else { [bool]$profile.defaultRequired -or $index -eq 1 }
            verify   = [PSCustomObject]@{
                enabled   = if ($tier.ContainsKey('Verify')) { [bool]$tier.Verify } else { [bool]$profile.defaultVerify }
                algorithm = if ($tier.ContainsKey('VerifyAlgorithm')) { [string]$tier.VerifyAlgorithm } else { 'SHA256' }
                mode      = if ($tier.ContainsKey('VerifyMode')) { [string]$tier.VerifyMode } else { 'HashAfterWrite' }
            }
            fallback = [PSCustomObject]@{
                enabled   = if ($tier.ContainsKey('FallbackEnabled')) { [bool]$tier.FallbackEnabled } else { $true }
                toTierId  = if ($tier.ContainsKey('FallbackTo')) { [string]$tier.FallbackTo } elseif ($tier.ContainsKey('FallbackTierId')) { [string]$tier.FallbackTierId } else { $null }
                action    = if ($tier.ContainsKey('FallbackAction')) { [string]$tier.FallbackAction } else { 'UseNextAvailableTier' }
                onFailure = @('Unavailable', 'WriteFailed', 'VerifyFailed')
            }
            copy     = [PSCustomObject]@{
                mode              = if ($index -eq 1) { 'PrimaryWrite' } else { 'CascadeFromPreviousVerifiedTier' }
                includeManifest   = $true
                includeMetadata   = $true
                maxRetries        = if ($tier.ContainsKey('MaxRetries')) { [int]$tier.MaxRetries } else { 2 }
                retryDelaySeconds = if ($tier.ContainsKey('RetryDelaySeconds')) { [int]$tier.RetryDelaySeconds } else { 5 }
                continueOnFailure = if ($tier.ContainsKey('ContinueOnFailure')) { [bool]$tier.ContinueOnFailure } else { -not ([bool]$profile.defaultRequired -or $index -eq 1) }
            }
            configuration = [PSCustomObject]@{
                source = if ($tier.ContainsKey('Source')) { [string]$tier.Source } else { 'InlineHashtable' }
            }
            state    = 'Planned'
        })
    }

    if ($tiers.Count -eq 0) {
        $primaryPath = $DestinationRoot
        if ([string]::IsNullOrWhiteSpace($primaryPath) -and
            -not [string]::IsNullOrWhiteSpace($ArchivePath)) {
            $primaryPath = Split-Path -Path $ArchivePath -Parent
        }

        if (-not [string]::IsNullOrWhiteSpace($primaryPath)) {
            $profile = Get-BackupStorageTierProfile -Profile 'FastSSD'
            $tiers.Add([PSCustomObject]@{
                id     = 'tier-1'
                name   = 'Primary'
                profile = 'FastSSD'
                kind   = [string]$profile.kind
                adapter = [string]$profile.adapter
                role   = 'Primary'
                order  = 1
                path   = $primaryPath
                uri    = $null
                target = [PSCustomObject]@{
                    kind  = 'Path'
                    value = $primaryPath
                }
                speedClass      = [string]$profile.speedClass
                durabilityClass = [string]$profile.durabilityClass
                capabilities    = @($profile.capabilities)
                required        = $true
                verify = [PSCustomObject]@{
                    enabled   = $true
                    algorithm = 'SHA256'
                    mode      = 'HashAfterWrite'
                }
                fallback = [PSCustomObject]@{
                    enabled   = $false
                    toTierId  = $null
                    action    = 'None'
                    onFailure = @()
                }
                copy = [PSCustomObject]@{
                    mode              = 'PrimaryWrite'
                    includeManifest   = $true
                    includeMetadata   = $true
                    maxRetries        = 2
                    retryDelaySeconds = 5
                    continueOnFailure = $false
                }
                configuration = [PSCustomObject]@{
                    source = 'DestinationRoot'
                }
                state  = 'Planned'
            })
        }
    }

    $orderedTiers = @($tiers.ToArray() | Sort-Object order, id)
    for ($tierIndex = 0; $tierIndex -lt $orderedTiers.Count; $tierIndex++) {
        $current = $orderedTiers[$tierIndex]
        if ($current.fallback -and
            [bool]$current.fallback.enabled -and
            [string]::IsNullOrWhiteSpace([string]$current.fallback.toTierId) -and
            $tierIndex + 1 -lt $orderedTiers.Count) {
            $current.fallback.toTierId = [string]$orderedTiers[$tierIndex + 1].id
        }
    }

    return @($orderedTiers)
}

function New-BackupProjectJobPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Project,
        [Parameter(Mandatory)]
        [pscustomobject]$ArchiveDescriptor,
        [string[]]$CleanupPreset = @('General'),
        [string]$ConfigProfile = 'balanced',
        [ValidateSet('Zip', 'SevenZip', 'TarZstd', 'Folder')]
        [string]$ArchiveFormat = 'Zip',
        [ValidateSet('ArchiveOnly', 'TranscodeAndArchive', 'CopyOnly')]
        [string]$CompressionMode = 'ArchiveOnly',
        [ValidateSet('Fastest', 'Balanced', 'Smallest', 'Lossless')]
        [string]$CompressionPreset = 'Balanced',
        [ValidateSet('Auto', 'H264', 'H265', 'AV1')]
        [string]$VideoCodec = 'Auto',
        [ValidateSet('Auto', 'CPU', 'Nvidia', 'IntelQuickSync', 'AMD')]
        [string]$EncoderDevice = 'Auto',
        [ValidateSet('Draft', 'Balanced', 'High', 'Smallest', 'Lossless')]
        [string]$QualityPreset = 'Balanced',
        [ValidateSet('Auto', 'AAC_128', 'AAC_192', 'Opus_96', 'Opus_128', 'Copy', 'Lossless')]
        [string]$AudioProfile = 'Auto',
        [switch]$CreateProxy,
        [switch]$CreatePreview,
        [switch]$KeepEmptyFolders,
        [switch]$KeepSourceProject,
        [switch]$DryRun,
        [switch]$Background,
        [switch]$DisableChunking,
        [ValidateRange(10, 86400)]
        [int]$ChunkDurationSeconds = 600,
        [hashtable[]]$StorageTier,
        [ValidateRange(1, 64)]
        [int]$MaxParallelJobs = 1,
        [ValidateRange(1, 100)]
        [int]$MaxCpuPercent = 90,
        [ValidateRange(1, 100)]
        [int]$MaxGpuPercent = 95,
        [ValidateRange(1, 100)]
        [int]$MaxDiskActivePercent = 90,
        [ValidateRange(1, 120)]
        [int]$MaxTemperatureCelsius = 85,
        [switch]$RequireIdle,
        [ValidateRange(0, 1440)]
        [int]$MinIdleMinutes = 10,
        [string]$AllowedStartTime,
        [string]$AllowedEndTime,
        [ValidateRange(1, 3600)]
        [int]$SystemRulePollSeconds = 5,
        [switch]$AllowOnBattery,
        [switch]$DisableThermalThrottle,
        [string]$QueueName = 'backup',
        [int]$Priority = 0
    )

    if ([string]::IsNullOrWhiteSpace($ConfigProfile)) {
        $ConfigProfile = 'balanced'
    }
    if ([string]::IsNullOrWhiteSpace($QueueName)) {
        $QueueName = 'backup'
    }

    $chunkingEnabled = -not [bool]$DisableChunking
    $probeTimedMedia = $chunkingEnabled -and $CompressionMode -eq 'TranscodeAndArchive'
    $mediaAnalysis = Get-BackupMediaAnalysis `
        -ProjectRoot ([string]$Project.RootPath) `
        -ProbeTimedMedia:$probeTimedMedia
    $chunkPlan = New-BackupChunkPlan `
        -MediaAnalysis $mediaAnalysis `
        -ChunkDurationSeconds $ChunkDurationSeconds `
        -Enabled:$probeTimedMedia
    $deletePolicyMode = if ($KeepSourceProject) { 'KeepSource' } else { 'RemoveSourceAfterVerified' }
    $storageTiers = ConvertTo-BackupProjectStorageTier `
        -StorageTier $StorageTier `
        -DestinationRoot ([string]$ArchiveDescriptor.DestinationRoot) `
        -ArchivePath ([string]$ArchiveDescriptor.ArchivePath)
    $storageCascade = New-BackupStorageCascadePlan -StorageTiers @($storageTiers)
    $copyVerify = New-BackupCopyVerifyPlan `
        -StorageTiers @($storageTiers) `
        -StorageCascade $storageCascade
    $safeDelete = New-BackupSafeDeletePolicy `
        -Mode $deletePolicyMode `
        -RequiredStorageTierIds @($storageCascade.requiredTierIds)
    $gpuDetection = New-BackupGpuDetectionPlan `
        -VideoCodec $VideoCodec `
        -EncoderDevice $EncoderDevice `
        -CompressionPreset $CompressionPreset
    $qualityValidation = New-BackupQualityValidationPolicy `
        -QualityPreset $QualityPreset `
        -CompressionMode $CompressionMode
    $systemRules = New-RenderKitSystemRulesPolicy `
        -RequireIdle ([bool]$RequireIdle) `
        -MinIdleMinutes $MinIdleMinutes `
        -AllowOnBattery ([bool]$AllowOnBattery) `
        -ThermalThrottleEnabled (-not [bool]$DisableThermalThrottle) `
        -MaxCpuPercent $MaxCpuPercent `
        -MaxGpuPercent $MaxGpuPercent `
        -MaxDiskActivePercent $MaxDiskActivePercent `
        -MaxTemperatureCelsius $MaxTemperatureCelsius `
        -AllowedStartTime $AllowedStartTime `
        -AllowedEndTime $AllowedEndTime `
        -PollIntervalSeconds $SystemRulePollSeconds

    $now = (Get-Date).ToUniversalTime().ToString('o')
    return [PSCustomObject]@{
        schemaVersion    = '1.0'
        kind             = 'BackupProject'
        requestedAtUtc   = $now
        project          = [PSCustomObject]@{
            id       = [string]$Project.Id
            name     = [string]$Project.Name
            rootPath = [string]$Project.RootPath
        }
        source           = [PSCustomObject]@{
            rootPath        = [string]$Project.RootPath
            cleanup         = [PSCustomObject]@{
                presets          = @($CleanupPreset)
                keepEmptyFolders = [bool]$KeepEmptyFolders
            }
            deletePolicy    = [PSCustomObject]@{
                mode                           = $deletePolicyMode
                requiresArchiveIntegrity       = $true
                requiresDecodeValidation       = $true
                decodeValidationScope          = 'WhenProducedMediaExists'
                requiresPrimaryTierVerification = $true
                requiresStorageCascadeVerification = $true
                requiresAllTierVerification    = $false
                requiredStorageTierIds          = @($storageCascade.requiredTierIds)
                releaseCondition                = 'ArchiveIntegrityDecodeAndRequiredStorageTiersVerified'
            }
        }
        profile          = [PSCustomObject]@{
            configProfile     = $ConfigProfile
            cleanupPresets    = @($CleanupPreset)
            compressionPreset = $CompressionPreset
        }
        encoding         = [PSCustomObject]@{
            schemaVersion    = '1.0'
            videoCodec       = $VideoCodec
            encoderDevice    = $EncoderDevice
            qualityPreset    = $QualityPreset
            audioProfile     = $AudioProfile
            gpuDetection     = $gpuDetection
            qualityValidation = $qualityValidation
            proxy            = [PSCustomObject]@{
                enabled     = [bool]$CreateProxy
                height      = 720
                videoCodec  = 'H264'
                quality     = 'Draft'
            }
            preview          = [PSCustomObject]@{
                enabled        = [bool]$CreatePreview
                format         = 'jpg'
                intervalSeconds = 60
                width          = 1280
            }
        }
        archive          = [PSCustomObject]@{
            format            = $ArchiveFormat
            mode              = $CompressionMode
            compressionPreset = $CompressionPreset
            destinationRoot   = [string]$ArchiveDescriptor.DestinationRoot
            fileName          = [string]$ArchiveDescriptor.ArchiveFileName
            path              = [string]$ArchiveDescriptor.ArchivePath
        }
        chunking         = [PSCustomObject]@{
            enabled         = $chunkingEnabled
            strategy        = if ($chunkingEnabled) { 'TimeRange' } else { 'Disabled' }
            durationSeconds = if ($chunkingEnabled) { $ChunkDurationSeconds } else { 0 }
            resumeMode      = if ($chunkingEnabled) { 'ChunkManifest' } else { 'WholeArchive' }
            state           = 'Planned'
            plannedChunkCount = [int]$chunkPlan.summary.chunkCount
        }
        merge            = [PSCustomObject]@{
            schemaVersion = '1.0'
            strategy      = 'FfmpegConcatCopy'
            state         = 'Planned'
            validation    = [PSCustomObject]@{
                enabled           = $probeTimedMedia
                containerProbe    = 'ffprobe'
                streamPolicy      = 'RequireExpectedPrimaryStreams'
                syncPolicy        = 'DurationDriftWithinTolerance'
                failureAction     = 'FailJobBeforeArchive'
            }
        }
        scheduler        = [PSCustomObject]@{
            schemaVersion   = '1.0'
            enabled         = $MaxParallelJobs -gt 1
            mode            = if ($MaxParallelJobs -gt 1) { 'WorkerPool' } else { 'SingleWorker' }
            maxParallelJobs = $MaxParallelJobs
            queuePriority   = $Priority
            policy          = [PSCustomObject]@{
                primaryVideo = 'OneChunkAtATime'
                secondaryMedia = 'ParallelWithinWorkerPool'
                imagesAndPreviews = 'ParallelDerivativeLane'
                checksums     = 'ParallelDiskReadLane'
                overloadAction = 'ThrottleByLaneLimits'
            }
            resourceLimits  = [PSCustomObject]@{
                maxCpuPercent = $MaxCpuPercent
                maxGpuPercent = $MaxGpuPercent
                maxDiskActivePercent = $MaxDiskActivePercent
                maxTemperatureCelsius = $MaxTemperatureCelsius
                diskPolicy    = 'LimitHeavyDiskStages'
                requireIdle   = [bool]$RequireIdle
                minIdleMinutes = $MinIdleMinutes
                allowedStartTime = $AllowedStartTime
                allowedEndTime = $AllowedEndTime
                systemRulePollSeconds = $SystemRulePollSeconds
            }
        }
        progress         = [PSCustomObject]@{
            schemaVersion = '1.0'
            state         = 'Planned'
            statePath     = $null
            source        = [PSCustomObject]@{
                ffmpegProgress = 'pipe:1'
                copyProgress   = 'byte-callback'
                chunkProgress  = 'chunk-index'
            }
            metrics       = @(
                'StageName',
                'OverallPercent',
                'ChunkPercent',
                'EtaSeconds',
                'Speed',
                'ActiveCommands',
                'BytesCompleted',
                'BytesTotal'
            )
            stages        = @(
                'PlanningEncoding',
                'Encoding',
                'Merging',
                'ValidatingMerge',
                'QualityDecode',
                'QualityMetrics',
                'QualityValidationComplete',
                'CreatingProxy',
                'CreatingPreview',
                'CopyingToStorageTier',
                'VerifyingStorageTier',
                'CopyVerifyComplete',
                'EncodingComplete'
            )
        }
        control          = [PSCustomObject]@{
            schemaVersion = '1.0'
            statePath     = $null
            pause         = [PSCustomObject]@{
                enabled = $true
                mode    = 'ProcessSuspendWhenSupported'
            }
            resume        = [PSCustomObject]@{
                enabled = $true
                mode    = 'SkipCompletedChunksFromChunkIndex'
            }
            cancel        = [PSCustomObject]@{
                enabled = $true
                mode    = 'OrderedStopActiveProcesses'
            }
            retry         = [PSCustomObject]@{
                maxAttemptsPerChunk = 3
                retryDelaySeconds   = 1
            }
        }
        background        = [PSCustomObject]@{
            schemaVersion = '1.0'
            enabled       = $true
            queueName     = 'backup'
            worker        = [PSCustomObject]@{
                mode              = 'LocalWorker'
                startCommand      = 'Start-RenderKitJobWorker'
                statusCommand     = 'Get-RenderKitJobStatus'
                workerStatusCommand = 'Get-RenderKitJobWorkerStatus'
                supportsDetached  = $true
                stateRoot         = $null
                logRoot           = $null
            }
            recovery      = [PSCustomObject]@{
                leaseHeartbeat       = 'ProgressExtendsLease'
                staleRunningJobMode  = 'RequeueAfterExpiredLease'
                crashedWorkerState   = 'DetectPreviousWorkerPid'
            }
            logs          = [PSCustomObject]@{
                persistent = $true
                format     = 'jsonl'
                tailCommand = 'Get-RenderKitJobStatus -IncludeLogs'
            }
        }
        systemRules       = $systemRules
        copyVerify        = $copyVerify
        safeDelete        = $safeDelete
        mediaAnalysis    = [PSCustomObject]@{
            schemaVersion = [string]$mediaAnalysis.schemaVersion
            probe         = $mediaAnalysis.probe
            summary       = $mediaAnalysis.summary
            files         = @($mediaAnalysis.files)
        }
        chunkPlan        = $chunkPlan
        resume           = [PSCustomObject]@{
            schemaVersion = '1.0'
            strategy      = if ($probeTimedMedia) { 'ChunkManifest' } else { 'WholeArchive' }
            state         = 'Planned'
            jobId         = $null
            statePath     = $null
            progressStatePath = $null
            lastCompletedChunkId = $null
        }
        storageTiers     = @($storageTiers)
        storageCascade   = $storageCascade
        execution        = [PSCustomObject]@{
            mode                   = if ($Background) { 'Background' } else { 'Immediate' }
            queueName              = $QueueName
            priority               = $Priority
            dryRun                 = [bool]$DryRun
            maxParallelJobs        = $MaxParallelJobs
            requireIdle            = [bool]$RequireIdle
            allowOnBattery         = [bool]$AllowOnBattery
            thermalThrottleEnabled = -not [bool]$DisableThermalThrottle
            resourceLimits         = [PSCustomObject]@{
                maxCpuPercent = $MaxCpuPercent
                maxGpuPercent = $MaxGpuPercent
                maxDiskActivePercent = $MaxDiskActivePercent
                maxTemperatureCelsius = $MaxTemperatureCelsius
            }
            systemRules             = $systemRules
        }
        advancedFeatures = [PSCustomObject]@{
            gpuDetection      = $gpuDetection
            deduplication     = [PSCustomObject]@{ enabled = $true; state = 'Planned' }
            qualityValidation = $qualityValidation
            tapeTargets       = [PSCustomObject]@{ enabled = $true; state = 'AdapterPlanned' }
            cloudTargets      = [PSCustomObject]@{ enabled = $true; state = 'AdapterPlanned' }
            idleDetection     = [PSCustomObject]@{ enabled = [bool]$RequireIdle; state = 'Planned' }
        }
    }
}

function New-BackupProjectJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Payload,
        [string]$QueueName = 'backup',
        [int]$Priority = 0,
        [string]$CorrelationId,
        [object]$RequestedBy
    )

    if ([string]::IsNullOrWhiteSpace($QueueName)) {
        $QueueName = 'backup'
    }

    $job = New-RenderKitJob `
        -JobType 'BackupProject' `
        -Payload $Payload `
        -PayloadSchemaVersion ([string]$Payload.schemaVersion) `
        -QueueName $QueueName `
        -Priority $Priority `
        -CorrelationId $CorrelationId `
        -RequestedBy $RequestedBy

    if ($Payload.PSObject.Properties.Name -contains 'resume' -and $Payload.resume) {
        $resumeStatePath = Get-BackupResumeStatePath -JobId ([string]$job.id)
        $progressStatePath = Get-BackupProgressStatePath -JobId ([string]$job.id)
        $controlStatePath = Get-BackupControlStatePath -JobId ([string]$job.id)
        $Payload.resume.jobId = [string]$job.id
        $Payload.resume.statePath = $resumeStatePath
        $Payload.resume.progressStatePath = $progressStatePath
        if ($Payload.PSObject.Properties.Name -contains 'progress' -and $Payload.progress) {
            $Payload.progress.statePath = $progressStatePath
        }
        if ($Payload.PSObject.Properties.Name -contains 'control' -and $Payload.control) {
            $Payload.control.statePath = $controlStatePath
        }
        if ($Payload.PSObject.Properties.Name -contains 'background' -and $Payload.background) {
            $Payload.background.queueName = $QueueName
            $Payload.background.worker.stateRoot = Get-RenderKitWorkerStateRoot
            $Payload.background.worker.logRoot = Get-RenderKitWorkerLogRoot
        }
        if ($Payload.chunkPlan -and $Payload.chunkPlan.index) {
            $Payload.chunkPlan.index.jobId = [string]$job.id
            $Payload.chunkPlan.index.statePath = Get-BackupChunkIndexPath -JobId ([string]$job.id)
            Save-BackupChunkIndex `
                -JobId ([string]$job.id) `
                -ChunkIndex $Payload.chunkPlan.index |
                Out-Null
        }
        $job.payload = $Payload

        Save-BackupResumeState `
            -JobId ([string]$job.id) `
            -State (New-BackupResumeState -Job $job -Payload $Payload) |
            Out-Null
        Save-BackupControlState `
            -JobId ([string]$job.id) `
            -State (New-BackupControlState -JobId ([string]$job.id) -StatePath $controlStatePath) |
            Out-Null
    }

    return Add-RenderKitJob -Job $job
}
