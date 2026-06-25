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
        $tierPath = if ($tier.ContainsKey('Path')) { [string]$tier.Path } else { $null }
        if ([string]::IsNullOrWhiteSpace($tierPath)) {
            throw "Backup storage tier '$tierName' must provide a Path value."
        }

        $tiers.Add([PSCustomObject]@{
            id       = if ($tier.ContainsKey('Id')) { [string]$tier.Id } else { "tier-$index" }
            name     = $tierName
            kind     = if ($tier.ContainsKey('Kind')) { [string]$tier.Kind } else { 'LocalFileSystem' }
            role     = if ($tier.ContainsKey('Role')) { [string]$tier.Role } else { if ($index -eq 1) { 'Primary' } else { 'Cascade' } }
            order    = if ($tier.ContainsKey('Order')) { [int]$tier.Order } else { $index }
            path     = $tierPath
            verify   = [PSCustomObject]@{
                enabled   = if ($tier.ContainsKey('Verify')) { [bool]$tier.Verify } else { $true }
                algorithm = if ($tier.ContainsKey('VerifyAlgorithm')) { [string]$tier.VerifyAlgorithm } else { 'SHA256' }
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
            $tiers.Add([PSCustomObject]@{
                id     = 'tier-1'
                name   = 'Primary'
                kind   = 'LocalFileSystem'
                role   = 'Primary'
                order  = 1
                path   = $primaryPath
                verify = [PSCustomObject]@{
                    enabled   = $true
                    algorithm = 'SHA256'
                }
                state  = 'Planned'
            })
        }
    }

    return @($tiers.ToArray() | Sort-Object order, id)
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
        [switch]$RequireIdle,
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
                requiresPrimaryTierVerification = $true
                requiresAllTierVerification    = $false
            }
        }
        profile          = [PSCustomObject]@{
            configProfile     = $ConfigProfile
            cleanupPresets    = @($CleanupPreset)
            compressionPreset = $CompressionPreset
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
            lastCompletedChunkId = $null
        }
        storageTiers     = @($storageTiers)
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
            }
        }
        advancedFeatures = [PSCustomObject]@{
            gpuDetection      = [PSCustomObject]@{ enabled = $true; state = 'Planned' }
            deduplication     = [PSCustomObject]@{ enabled = $true; state = 'Planned' }
            qualityValidation = [PSCustomObject]@{ enabled = $true; state = 'Planned'; metrics = @('DecodeProbe') }
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
        $Payload.resume.jobId = [string]$job.id
        $Payload.resume.statePath = $resumeStatePath
        $job.payload = $Payload

        Save-BackupResumeState `
            -JobId ([string]$job.id) `
            -State (New-BackupResumeState -Job $job -Payload $Payload) |
            Out-Null
    }

    return Add-RenderKitJob -Job $job
}
