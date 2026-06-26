Register-RenderKitFunction "Backup-Project"
function Backup-Project{
    <#
.SYNOPSIS
Cleans and archives a RenderKit project.

.DESCRIPTION
Resolves a project, removes configured artifacts, optionally removes empty folders, creates a ZIP backup, verifies archive content integrity, injects log files into the archive, writes a backup manifest, and optionally removes the source project folder.
Supports `-WhatIf` / `-Confirm` via `SupportsShouldProcess`.

.PARAMETER ProjectName
Name of the project folder to back up.

.PARAMETER Path
Project root directory that contains the project folder.
If omitted, the default path from RenderKit config is used.

.PARAMETER Profile
Cleanup profile names used to decide which artifacts are removed before archiving.

.PARAMETER DestinationRoot
Destination directory for the created backup archive.
If omitted, the parent directory of the project root is used.

.PARAMETER KeepEmptyFolders
Keeps empty folders after cleanup when set.

.PARAMETER KeepSourceProject
Keeps the source project folder after backup.
If omitted, source project folder is removed after successful backup.

.PARAMETER DryRun
Simulates cleanup and archive operations without changing files.

.PARAMETER Background
Queues a BackupProject job instead of running the backup immediately.

.PARAMETER StartWorker
Starts a detached local BackupProject worker after queuing a background job.

.PARAMETER Watch
Watches the queued background job with a CLI progress bar until it reaches a terminal state.

.PARAMETER PollIntervalSeconds
Polling interval used by `-Watch` and by the detached worker started through `-StartWorker`.

.PARAMETER NoProgressBar
Suppresses the CLI progress bar when `-Watch` is used.

.PARAMETER ConfigProfile
Backup configuration profile name. This is reserved for user-defined importable/exportable profiles.

.PARAMETER ArchiveFormat
Archive output format. Immediate execution currently supports Zip; other formats are queued for worker execution.

.PARAMETER CompressionMode
Pipeline mode for future media handling and archive-only backups.

.PARAMETER CompressionPreset
Compression intent used by the job payload and manifest.

.PARAMETER VideoCodec
Target video codec for chunk encoding.

.PARAMETER EncoderDevice
Encoder device class used for chunk encoding.

.PARAMETER QualityPreset
Quality intent used for encoder arguments.

.PARAMETER AudioProfile
Audio compression profile used during chunk encoding.

.PARAMETER CreateProxy
Plans proxy media generation for encoded assets.

.PARAMETER CreatePreview
Plans preview thumbnail generation for encoded assets.

.PARAMETER ChunkDurationSeconds
Target chunk duration used by the resumable media pipeline.

.PARAMETER StorageTier
Inline storage tier definitions for cascading backup targets.

.PARAMETER StorageTierProfile
Built-in storage tier profiles to create, such as FastSSD, HDD, NAS, ColdStorage, Tape, or CloudS3.

.PARAMETER StorageTierPath
Target paths or URIs matching StorageTierProfile order.

.PARAMETER ConfigureStorageTiers
Starts an interactive CLI prompt for building storage tier targets.

.PARAMETER RequireIdle
Only lets the background media worker run when the user has been idle long enough.

.PARAMETER MinIdleMinutes
Minimum user-idle duration required when `-RequireIdle` is used.

.PARAMETER AllowedStartTime
Optional local start time for background processing, formatted as HH:mm.

.PARAMETER AllowedEndTime
Optional local end time for background processing, formatted as HH:mm.

.PARAMETER ReportFormat
Audit report formats to write. Defaults to Json, Html, and Text.

.PARAMETER ReportRoot
Optional directory for audit report sidecar files. Defaults to the backup archive destination directory.

.PARAMETER SimulateFailure
Injects controlled backup failures for recovery testing.

.PARAMETER MaxChunkRetryAttempts
Maximum attempts per failed encoding chunk before the job fails.

.PARAMETER ChunkRetryDelaySeconds
Delay between chunk retry attempts.

.EXAMPLE
Backup-Project -ProjectName "ClientA_2026"
Backs up project `ClientA_2026` from the configured default project root.

.EXAMPLE
Backup-Project -ProjectName "ClientA_2026" -Path "D:\Projects" -Profile DaVinci -DryRun
Simulates a DaVinci-focused backup for the given path.

.EXAMPLE
Backup-Project -ProjectName "ClientA_2026" -Path "D:\Projects" -DestinationRoot "E:\Backups" -KeepEmptyFolders -Confirm
Runs backup and asks for confirmation because of `SupportsShouldProcess`.

.EXAMPLE
Backup-Project -ProjectName "ClientA_2026" -KeepSourceProject
Runs backup but keeps the source project folder.

.INPUTS
None. You cannot pipe input to this command.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns project and backup result data (project id, source path, backup path, source removal flag, dry-run flag).

.LINK
Set-ProjectRoot

.LINK
New-Project

.LINK
https://github.com/djtroi/RenderKit
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$ProjectName,
        [string]$Path,
        [Alias("Software")]
        [string[]]$Preset = @("General"),
        [string]$DestinationRoot,
        [Alias("AsJob")]
        [switch]$Background,
        [switch]$StartWorker,
        [switch]$Watch,
        [ValidateRange(1, 3600)]
        [int]$PollIntervalSeconds = 2,
        [switch]$NoProgressBar,
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
        [switch]$DisableChunking,
        [ValidateRange(10, 86400)]
        [int]$ChunkDurationSeconds = 600,
        [hashtable[]]$StorageTier,
        [ValidateSet('FastSSD', 'HDD', 'NAS', 'ColdStorage', 'Tape', 'CloudS3')]
        [string[]]$StorageTierProfile,
        [string[]]$StorageTierPath,
        [switch]$ConfigureStorageTiers,
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
        [ValidatePattern('^\d{2}:\d{2}$')]
        [string]$AllowedStartTime,
        [ValidatePattern('^\d{2}:\d{2}$')]
        [string]$AllowedEndTime,
        [ValidateRange(1, 3600)]
        [int]$SystemRulePollSeconds = 5,
        [switch]$AllowOnBattery,
        [switch]$DisableThermalThrottle,
        [ValidateSet('Json', 'Html', 'Text')]
        [string[]]$ReportFormat = @('Json', 'Html', 'Text'),
        [string]$ReportRoot,
        [ValidateSet('None', 'AbortRequested', 'MissingTarget', 'FullDisk', 'CorruptChunk', 'TransientStorageCopy')]
        [string[]]$SimulateFailure = @(),
        [ValidateRange(1, 20)]
        [int]$MaxChunkRetryAttempts = 3,
        [ValidateRange(0, 3600)]
        [int]$ChunkRetryDelaySeconds = 1,
        [ValidateRange(1, 20)]
        [int]$SimulatedFailureCount = 1,
        [string]$QueueName = 'backup',
        [ValidateRange(-1000, 1000)]
        [int]$Priority = 0,
        [switch]$KeepEmptyFolders,
        [switch]$KeepSourceProject,
        [switch]$DryRun
    )
    Write-RenderKitLog -Level Info -Message "Starting backup for project '$ProjectName'."
    Write-RenderKitLog -Level Debug -Message (
        "Parameters: Path='{0}' Preset='{1}' DestinationRoot='{2}' Background='{3}' ConfigProfile='{4}' ArchiveFormat='{5}' CompressionMode='{6}' CompressionPreset='{7}' DisableChunking='{8}' ChunkDurationSeconds='{9}' KeepEmptyFolders='{10}' KeepSourceProject='{11}' DryRun='{12}'." -f
        $Path,
        ($Preset -join ","),
        $DestinationRoot,
        $Background,
        $ConfigProfile,
        $ArchiveFormat,
        $CompressionMode,
        $CompressionPreset,
        $DisableChunking,
        $ChunkDurationSeconds,
        $KeepEmptyFolders,
        $KeepSourceProject,
        $DryRun
    )

    $config = Get-RenderKitConfig
    if ([string]::IsNullOrWhiteSpace($Path)) {
        if ([string]::IsNullOrWhiteSpace([string]$config.DefaultProjectPath)) {
            Write-RenderKitLog -Level Error -Message "No project path was provided and no default project path is configured."
            throw "No project path was provided and no default project path is configured."
        }

        $Path = [string]$config.DefaultProjectPath
        Write-RenderKitLog -Level Info -Message "Using default project path '$Path'."
    }

    $project = Get-RenderKitProject -ProjectName $ProjectName -Path $Path
    $projectRoot = [string]$project.RootPath

    $rules = Get-CleanupRule -Preset $Preset
    $startedAt = Get-Date
    $effectiveStorageTier = @()
    if ($StorageTier) {
        $effectiveStorageTier += @($StorageTier)
    }
    if ($StorageTierProfile) {
        $effectiveStorageTier += @(
            ConvertTo-BackupStorageTierProfileInput `
                -Profile $StorageTierProfile `
                -Path $StorageTierPath
        )
    }
    if ($ConfigureStorageTiers) {
        $effectiveStorageTier += @(
            Read-BackupStorageTierInteractiveConfiguration
        )
    }
    $effectiveDestinationRoot = $DestinationRoot
    if ([string]::IsNullOrWhiteSpace($effectiveDestinationRoot) -and @($effectiveStorageTier).Count -gt 0) {
        $firstTierTarget = if ($effectiveStorageTier[0].ContainsKey('Path')) {
            [string]$effectiveStorageTier[0].Path
        }
        elseif ($effectiveStorageTier[0].ContainsKey('Uri')) {
            [string]$effectiveStorageTier[0].Uri
        }
        else {
            $null
        }
        if (-not (Test-BackupPathLooksLikeUri -Path $firstTierTarget) -and
            -not [string]::IsNullOrWhiteSpace($firstTierTarget)) {
            $effectiveDestinationRoot = $firstTierTarget
        }
    }

    $archiveDescriptor = Resolve-BackupArchivePath `
        -Project $project `
        -DestinationRoot $effectiveDestinationRoot `
        -Timestamp $startedAt `
        -ArchiveFormat $ArchiveFormat

    $backupJobPayload = New-BackupProjectJobPayload `
        -Project $project `
        -ArchiveDescriptor $archiveDescriptor `
        -CleanupPreset @($rules.Profiles) `
        -ConfigProfile $ConfigProfile `
        -ArchiveFormat $ArchiveFormat `
        -CompressionMode $CompressionMode `
        -CompressionPreset $CompressionPreset `
        -VideoCodec $VideoCodec `
        -EncoderDevice $EncoderDevice `
        -QualityPreset $QualityPreset `
        -AudioProfile $AudioProfile `
        -CreateProxy:$CreateProxy `
        -CreatePreview:$CreatePreview `
        -KeepEmptyFolders:$KeepEmptyFolders `
        -KeepSourceProject:$KeepSourceProject `
        -DryRun:$DryRun `
        -Background:$Background `
        -DisableChunking:$DisableChunking `
        -ChunkDurationSeconds $ChunkDurationSeconds `
        -StorageTier $effectiveStorageTier `
        -MaxParallelJobs $MaxParallelJobs `
        -MaxCpuPercent $MaxCpuPercent `
        -MaxGpuPercent $MaxGpuPercent `
        -MaxDiskActivePercent $MaxDiskActivePercent `
        -MaxTemperatureCelsius $MaxTemperatureCelsius `
        -RequireIdle:$RequireIdle `
        -MinIdleMinutes $MinIdleMinutes `
        -AllowedStartTime $AllowedStartTime `
        -AllowedEndTime $AllowedEndTime `
        -SystemRulePollSeconds $SystemRulePollSeconds `
        -AllowOnBattery:$AllowOnBattery `
        -DisableThermalThrottle:$DisableThermalThrottle `
        -ReportFormat $ReportFormat `
        -ReportRoot $ReportRoot `
        -SimulateFailure $SimulateFailure `
        -MaxChunkRetryAttempts $MaxChunkRetryAttempts `
        -ChunkRetryDelaySeconds $ChunkRetryDelaySeconds `
        -SimulatedFailureCount $SimulatedFailureCount `
        -QueueName $QueueName `
        -Priority $Priority

    if ($Background) {
        $queueActionDescription = "Queue BackupProject job for archive '$($archiveDescriptor.ArchivePath)'"
        if (-not $PSCmdlet.ShouldProcess($projectRoot, $queueActionDescription)) {
            return $null
        }

        $queuedJob = New-BackupProjectJob `
            -Payload $backupJobPayload `
            -QueueName $QueueName `
            -Priority $Priority `
            -RequestedBy ([PSCustomObject]@{
                user    = [string]$env:USERNAME
                machine = [string]$env:COMPUTERNAME
                command = 'Backup-Project'
            })

        Write-RenderKitLog -Level Info -Message "Queued BackupProject job '$($queuedJob.id)' for project '$ProjectName'."

        $worker = $null
        if ($StartWorker) {
            $worker = Start-RenderKitJobWorker `
                -JobType 'BackupProject' `
                -QueueName $QueueName `
                -PollIntervalSeconds $PollIntervalSeconds `
                -MaxJobs 1 `
                -Detached
        }

        $quotedJobId = "'" + ([string]$queuedJob.id -replace "'", "''") + "'"
        $commands = [PSCustomObject]@{
            Status = "Get-BackupJob -JobId $quotedJobId"
            Watch  = "Get-BackupJob -JobId $quotedJobId -Watch"
            Pause  = "Pause-BackupJob -JobId $quotedJobId"
            Resume = "Resume-BackupJob -JobId $quotedJobId"
            Stop   = "Stop-BackupJob -JobId $quotedJobId"
            Worker = "Start-RenderKitJobWorker -JobType BackupProject -QueueName '$QueueName' -MaxJobs 1 -Detached"
        }

        $backgroundResult = [PSCustomObject]@{
            ProjectName     = $project.Name
            ProjectId       = $project.Id
            RootPath        = $projectRoot
            JobId           = $queuedJob.id
            JobType         = $queuedJob.jobType
            Status          = $queuedJob.status
            QueueName       = $queuedJob.queueName
            Priority        = $queuedJob.priority
            ConfigProfile   = $ConfigProfile
            ArchiveFormat   = $ArchiveFormat
            ArchivePath     = $archiveDescriptor.ArchivePath
            Worker          = $worker
            Commands        = $commands
            Payload         = $backupJobPayload
            Job             = $queuedJob
        }

        if ($Watch) {
            $latest = Get-BackupJob `
                -JobId ([string]$queuedJob.id) `
                -Watch `
                -PollIntervalSeconds $PollIntervalSeconds `
                -NoProgressBar:$NoProgressBar
            if ($latest) {
                $backgroundResult.Status = [string]$latest.Status
                $backgroundResult | Add-Member `
                    -NotePropertyName Progress `
                    -NotePropertyValue $latest `
                    -Force
                $backgroundResult.Job = Get-RenderKitJob -JobId ([string]$queuedJob.id)
            }
        }

        return $backgroundResult
    }

    if ($ArchiveFormat -ne 'Zip') {
        throw "Archive format '$ArchiveFormat' is only supported for background backup jobs in this version."
    }

    $actionDescription = if ($KeepSourceProject) {
        "Clean project artifacts, create backup archive '$($archiveDescriptor.ArchivePath)', verify integrity, inject logs into archive, and keep source project folder"
    }
    else {
        "Clean project artifacts, create backup archive '$($archiveDescriptor.ArchivePath)', verify integrity, inject logs into archive, and remove source project folder"
    }
    if (-not $PSCmdlet.ShouldProcess($projectRoot, $actionDescription)) {
        return $null
    }

    $lockHandle = $null
    $manifestPath = $null
    $manifestArchiveEntryPath = $null
    $sourceRemoved = $false
    $integrityCheck = $null
    $sourceIntegrityIndex = $null
    $deduplicationPlan = $null
    $storageVerification = $null
    $safeDeleteDecision = $null
    $auditReport = $null
    $reportResult = $null
    $archiveLogInjection = [PSCustomObject]@{
        AddedCount = 0
        AddedEntries = @()
    }

    try {
        if (-not $DryRun) {
            if (-not (Test-Path -Path $archiveDescriptor.DestinationRoot -PathType Container)) {
                New-Item -ItemType Directory -Path $archiveDescriptor.DestinationRoot -Force | Out-Null
            }

            $lockHandle = Get-BackupLock -ProjectRoot $projectRoot
            Initialize-RenderKitLogging -ProjectRoot $projectRoot
        }
        else {
            Write-RenderKitLog -Level Info -Message "DryRun mode: no files will be modified, created, or deleted."
        }

        $statsBefore = Get-BackupProjectStatistic -ProjectPath $projectRoot

        Write-RenderKitLog -Level Info -Message "Cleaning project artifacts..."
        $artifactCleanup = Remove-ProjectArtifact `
            -ProjectPath $projectRoot `
            -Rules $rules `
            -DryRun:$DryRun

        $emptyFolderCleanup = [PSCustomObject]@{
            CandidateCount = 0
            RemovedCount   = 0
            FailedCount    = 0
            Mode           = if ($DryRun) { "DryRun" } else { "Execute" }
            Skipped        = $true
        }

        if (-not $KeepEmptyFolders) {
            $emptyFolderCleanup = Remove-EmptyFolder -Path $projectRoot -DryRun:$DryRun
            Add-Member -InputObject $emptyFolderCleanup -NotePropertyName Skipped -NotePropertyValue $false -Force
        }

        if (-not $DryRun) {
            $sourceIntegrityIndex = Get-BackupFileHashIndex `
                -RootPath $projectRoot `
                -BasePath $projectRoot `
                -Algorithm "SHA256"
            $deduplicationPlan = New-BackupDeduplicationPlan `
                -SourceIndex $sourceIntegrityIndex `
                -Policy $backupJobPayload.deduplication
        }

        $archiveInfo = @{
            destinationRoot = $archiveDescriptor.DestinationRoot
            fileName        = $archiveDescriptor.ArchiveFileName
            path            = $archiveDescriptor.ArchivePath
            created         = $false
            sourceRemoved   = $false
            exists          = $false
            sizeBytes       = [int64]0
            hashAlgorithm   = $null
            hash            = $null
            deduplication   = $deduplicationPlan
        }

        if (-not $DryRun) {
            $archiveResult = Compress-Project `
                -ProjectPath $projectRoot `
                -DestinationPath $archiveDescriptor.ArchivePath `
                -DeduplicationPlan $deduplicationPlan

            $archiveInfo.created = $true
            $archiveInfo.exists = Test-Path -Path $archiveDescriptor.ArchivePath -PathType Leaf
            $archiveInfo.sizeBytes = [int64]$archiveResult.SizeBytes
            $archiveInfo.hashAlgorithm = [string]$archiveResult.HashAlgorithm
            $archiveInfo.hash = [string]$archiveResult.Hash

            Write-RenderKitLog -Level Info -Message "Backup archive created: $($archiveDescriptor.ArchivePath)"

            $integrityCheck = Test-BackupArchiveContentIntegrity `
                -ProjectPath $projectRoot `
                -ArchivePath $archiveDescriptor.ArchivePath `
                -SourceIndex $sourceIntegrityIndex `
                -DeduplicationPlan $deduplicationPlan `
                -Algorithm "SHA256"

            if (-not $integrityCheck.IsMatch) {
                Write-RenderKitLog -Level Error -Message (
                    "Archive integrity check failed. MissingInArchive={0}, ExtraInArchive={1}, HashMismatches={2}, DedupMismatches={3}." -f
                    $integrityCheck.MissingInArchiveCount,
                    $integrityCheck.ExtraInArchiveCount,
                    $integrityCheck.HashMismatchCount,
                    $integrityCheck.DeduplicationMismatchCount
                )
                throw (
                    "Archive integrity check failed. MissingInArchive={0}, ExtraInArchive={1}, HashMismatches={2}, DedupMismatches={3}." -f
                    $integrityCheck.MissingInArchiveCount,
                    $integrityCheck.ExtraInArchiveCount,
                    $integrityCheck.HashMismatchCount,
                    $integrityCheck.DeduplicationMismatchCount
                )
            }

            Write-RenderKitLog -Level Info -Message (
                "Archive integrity check passed (Algorithm={0}, Files={1})." -f
                $integrityCheck.Algorithm,
                $integrityCheck.SourceFileCount
            )

            $archiveLogInjection = Add-BackupLogsToArchive `
                -ArchivePath $archiveDescriptor.ArchivePath `
                -ProjectRoot $projectRoot

            if ($archiveLogInjection.AddedCount -gt 0) {
                Write-RenderKitLog -Level Info -Message "Added $($archiveLogInjection.AddedCount) log file(s) to archive."
            }
            else {
                Write-RenderKitLog -Level Info -Message "No log files found to inject into archive."
            }

            $finalArchiveItem = Get-Item -Path $archiveDescriptor.ArchivePath -ErrorAction Stop
            $finalArchiveHash = Get-FileHash -Path $archiveDescriptor.ArchivePath -Algorithm SHA256 -ErrorAction Stop
            $archiveInfo.sizeBytes = [int64]$finalArchiveItem.Length
            $archiveInfo.hashAlgorithm = "SHA256"
            $archiveInfo.hash = [string]$finalArchiveHash.Hash
        }

        $statsAfterCleanup = if ($DryRun) {
            $statsBefore
        }
        else {
            Get-BackupProjectStatistic -ProjectPath $projectRoot
        }

        $willRemoveSource = (-not $DryRun -and -not $KeepSourceProject)

        $archiveInfo.sourceRemoved = $false
        $archiveInfo.logInjection = @{
            addedCount   = [int]$archiveLogInjection.AddedCount
            addedEntries = @($archiveLogInjection.AddedEntries)
        }
        $archiveInfo.contentIntegrity = @{
            checked              = [bool](-not $DryRun)
            isMatch              = if ($integrityCheck) { [bool]$integrityCheck.IsMatch } else { $null }
            algorithm            = if ($integrityCheck) { [string]$integrityCheck.Algorithm } else { $null }
            sourceFileCount      = if ($integrityCheck) { [int]$integrityCheck.SourceFileCount } else { $null }
            archiveFileCount     = if ($integrityCheck) { [int]$integrityCheck.ArchiveFileCount } else { $null }
            missingInArchiveCount = if ($integrityCheck) { [int]$integrityCheck.MissingInArchiveCount } else { $null }
            deduplicatedInArchiveCount = if ($integrityCheck) { [int]$integrityCheck.DeduplicatedInArchiveCount } else { $null }
            extraInArchiveCount  = if ($integrityCheck) { [int]$integrityCheck.ExtraInArchiveCount } else { $null }
            hashMismatchCount    = if ($integrityCheck) { [int]$integrityCheck.HashMismatchCount } else { $null }
            deduplicationMismatchCount = if ($integrityCheck) { [int]$integrityCheck.DeduplicationMismatchCount } else { $null }
        }

        $endedAt = Get-Date
        $statistics = @{
            startedAt       = $startedAt.ToString("o")
            endedAt         = $endedAt.ToString("o")
            durationSeconds = [Math]::Round(($endedAt - $startedAt).TotalSeconds, 3)
            before          = @{
                fileCount      = [int]$statsBefore.FileCount
                directoryCount = [int]$statsBefore.DirectoryCount
                totalBytes     = [int64]$statsBefore.TotalBytes
            }
            after           = @{
                fileCount      = [int]$statsAfterCleanup.FileCount
                directoryCount = [int]$statsAfterCleanup.DirectoryCount
                totalBytes     = [int64]$statsAfterCleanup.TotalBytes
            }
            cleanup         = @{
                artifactCandidates = @{
                    files   = [int]$artifactCleanup.CandidateFileCount
                    folders = [int]$artifactCleanup.CandidateFolderCount
                }
                artifactRemoved    = @{
                    files       = [int]$artifactCleanup.RemovedFileCount
                    folders     = [int]$artifactCleanup.RemovedFolderCount
                    bytes       = [int64]$artifactCleanup.RemovedFileBytes
                    failedCount = [int]$artifactCleanup.FailedCount
                }
                emptyFolders       = @{
                    candidates  = [int]$emptyFolderCleanup.CandidateCount
                    removed     = [int]$emptyFolderCleanup.RemovedCount
                    failedCount = [int]$emptyFolderCleanup.FailedCount
                    skipped     = [bool]$emptyFolderCleanup.Skipped
                }
            }
            source          = @{
                path              = $projectRoot
                removed           = $false
                removalScheduled  = $willRemoveSource
                existsAfterRun   = $true
            }
            deduplication   = if ($deduplicationPlan) {
                @{
                    enabled             = [bool]$deduplicationPlan.enabled
                    duplicateFileCount  = [int]$deduplicationPlan.summary.duplicateFileCount
                    duplicateGroupCount = [int]$deduplicationPlan.summary.duplicateGroupCount
                    uniqueFileCount     = [int]$deduplicationPlan.summary.uniqueFileCount
                    estimatedSavedBytes = [int64]$deduplicationPlan.summary.estimatedSavedBytes
                }
            }
            else {
                @{
                    enabled             = $false
                    duplicateFileCount  = 0
                    duplicateGroupCount = 0
                    uniqueFileCount     = 0
                    estimatedSavedBytes = 0
                }
            }
            archiveIntegrity = if ($integrityCheck) {
                @{
                    checked              = $true
                    isMatch              = [bool]$integrityCheck.IsMatch
                    algorithm            = [string]$integrityCheck.Algorithm
                    sourceFileCount      = [int]$integrityCheck.SourceFileCount
                    archiveFileCount     = [int]$integrityCheck.ArchiveFileCount
                    missingInArchiveCount = [int]$integrityCheck.MissingInArchiveCount
                    deduplicatedInArchiveCount = [int]$integrityCheck.DeduplicatedInArchiveCount
                    extraInArchiveCount  = [int]$integrityCheck.ExtraInArchiveCount
                    hashMismatchCount    = [int]$integrityCheck.HashMismatchCount
                    deduplicationMismatchCount = [int]$integrityCheck.DeduplicationMismatchCount
                }
            }
            else {
                @{
                    checked = $false
                }
            }
        }

        $cleanupSummary = @(
            [PSCustomObject]@{
                Step           = "RemoveProjectArtifacts"
                Mode           = [string]$artifactCleanup.Mode
                CandidateFiles = [int]$artifactCleanup.CandidateFileCount
                CandidateDirs  = [int]$artifactCleanup.CandidateFolderCount
                RemovedFiles   = [int]$artifactCleanup.RemovedFileCount
                RemovedDirs    = [int]$artifactCleanup.RemovedFolderCount
                RemovedBytes   = [int64]$artifactCleanup.RemovedFileBytes
                FailedCount    = [int]$artifactCleanup.FailedCount
            }
            [PSCustomObject]@{
                Step           = "RemoveEmptyFolders"
                Mode           = [string]$emptyFolderCleanup.Mode
                CandidateDirs  = [int]$emptyFolderCleanup.CandidateCount
                RemovedDirs    = [int]$emptyFolderCleanup.RemovedCount
                FailedCount    = [int]$emptyFolderCleanup.FailedCount
                Skipped        = [bool]$emptyFolderCleanup.Skipped
            }
        )

        $manifest = New-BackupManifest `
            -Project $project `
            -Options @{
                profiles            = @($rules.Profiles)
                keepEmptyFolders    = [bool]$KeepEmptyFolders
                keepSourceProject   = [bool]$KeepSourceProject
                dryRun              = [bool]$DryRun
                destinationRoot     = [string]$archiveDescriptor.DestinationRoot
                removeSourceProject = [bool](-not $KeepSourceProject)
                configProfile       = [string]$ConfigProfile
                archiveFormat       = [string]$ArchiveFormat
                compressionMode     = [string]$CompressionMode
                compressionPreset   = [string]$CompressionPreset
                videoCodec          = [string]$VideoCodec
                encoderDevice       = [string]$EncoderDevice
                qualityPreset       = [string]$QualityPreset
                audioProfile        = [string]$AudioProfile
                createProxy         = [bool]$CreateProxy
                createPreview       = [bool]$CreatePreview
                reportFormat        = @($ReportFormat)
                reportRoot          = [string]$ReportRoot
                simulateFailure     = @($SimulateFailure)
                maxChunkRetryAttempts = [int]$MaxChunkRetryAttempts
                chunkRetryDelaySeconds = [int]$ChunkRetryDelaySeconds
                simulatedFailureCount = [int]$SimulatedFailureCount
            } `
            -Statistics $statistics `
            -Archive $archiveInfo `
            -CleanupSummary $cleanupSummary `
            -Job ([PSCustomObject]@{
                id            = $null
                type          = 'BackupProject'
                executionMode = 'Immediate'
                queued        = $false
                queueName     = $QueueName
                priority      = $Priority
            }) `
            -Profile $backupJobPayload.profile `
            -Pipeline ([PSCustomObject]@{
                archiveFormat    = $ArchiveFormat
                compressionMode  = $CompressionMode
                compressionPreset = $CompressionPreset
                encoding        = $backupJobPayload.encoding
                chunking         = $backupJobPayload.chunking
                merge            = $backupJobPayload.merge
                scheduler        = $backupJobPayload.scheduler
                progress         = $backupJobPayload.progress
                control          = $backupJobPayload.control
                failureRecovery  = $backupJobPayload.failureRecovery
                background       = $backupJobPayload.background
                storageCascade   = $backupJobPayload.storageCascade
                deduplication    = if ($deduplicationPlan) { $deduplicationPlan } else { $backupJobPayload.deduplication }
                reports          = $backupJobPayload.reports
                copyVerify       = $backupJobPayload.copyVerify
                safeDelete       = $backupJobPayload.safeDelete
                mediaAnalysis    = $backupJobPayload.mediaAnalysis
                chunkPlan        = $backupJobPayload.chunkPlan
                resume           = $backupJobPayload.resume
                execution        = $backupJobPayload.execution
                advancedFeatures = $backupJobPayload.advancedFeatures
            }) `
            -StorageTiers @($backupJobPayload.storageTiers) `
            -Safety ([PSCustomObject]@{
                deletePolicy = $backupJobPayload.source.deletePolicy
                safeDelete   = $backupJobPayload.safeDelete
            })

        if (-not $DryRun) {
            $manifestFileName = [System.IO.Path]::ChangeExtension(
                [System.IO.Path]::GetFileName($archiveDescriptor.ArchivePath),
                "manifest.json"
            )
            $manifestTempPath = Join-Path `
                -Path ([System.IO.Path]::GetTempPath()) `
                -ChildPath ("renderkit-manifest-{0}-{1}" -f [guid]::NewGuid().ToString("N"), $manifestFileName)

            try {
                $manifestTempPath = Save-BackupManifest `
                    -Manifest $manifest `
                    -ManifestPath $manifestTempPath

                $manifestArchiveEntryName = "__renderkit_meta/$manifestFileName"
                $manifestArchiveEntry = Add-BackupFileToArchive `
                    -ArchivePath $archiveDescriptor.ArchivePath `
                    -FilePath $manifestTempPath `
                    -EntryPath $manifestArchiveEntryName

                $manifestArchiveEntryPath = [string]$manifestArchiveEntry.EntryPath
            }
            finally {
                if (-not [string]::IsNullOrWhiteSpace($manifestTempPath) -and (Test-Path -Path $manifestTempPath -PathType Leaf)) {
                    Remove-Item -Path $manifestTempPath -Force -ErrorAction SilentlyContinue
                }
            }

            $archiveInfo.manifest = @{
                sidecarPath       = $null
                embeddedInArchive = $true
                archiveEntryPath  = $manifestArchiveEntryPath
            }
            Write-RenderKitLog -Level Info -Message "Embedded manifest into archive entry '$manifestArchiveEntryPath'."
        }
        else {
            $archiveInfo.manifest = @{
                sidecarPath       = $null
                embeddedInArchive = $false
                archiveEntryPath  = $null
            }
            Write-RenderKitLog -Level Info -Message "DryRun mode: manifest was generated in-memory but not written to disk."
        }

        if (-not $DryRun) {
            $verifiedArchiveItem = Get-Item -Path $archiveDescriptor.ArchivePath -ErrorAction Stop
            $verifiedArchiveHash = Get-FileHash -Path $archiveDescriptor.ArchivePath -Algorithm SHA256 -ErrorAction Stop
            $archiveInfo.sizeBytes = [int64]$verifiedArchiveItem.Length
            $archiveInfo.hashAlgorithm = 'SHA256'
            $archiveInfo.hash = [string]$verifiedArchiveHash.Hash

            $storageVerification = Invoke-BackupStorageTierCopyVerifyChain `
                -ArchivePath $archiveDescriptor.ArchivePath `
                -StorageTiers @($backupJobPayload.storageTiers) `
                -StorageCascade $backupJobPayload.storageCascade `
                -ExpectedHash ([string]$archiveInfo.hash) `
                -ExpectedSizeBytes ([int64]$archiveInfo.sizeBytes) `
                -Algorithm 'SHA256' `
                -ArchiveIntegrityPassed ([bool]($integrityCheck -and $integrityCheck.IsMatch))
            $archiveInfo.storageVerification = $storageVerification
        }
        else {
            $archiveInfo.storageVerification = [PSCustomObject]@{
                schemaVersion = '1.0'
                state         = 'DryRun'
                release       = [PSCustomObject]@{
                    canReleaseSource = $false
                    reason           = 'DryRun'
                }
            }
        }

        $safeDeleteDecision = Test-BackupSafeDeletePolicy `
            -Policy $backupJobPayload.safeDelete `
            -ArchiveInfo $archiveInfo `
            -StorageVerification $archiveInfo.storageVerification `
            -MergeValidations @() `
            -DryRun ([bool]$DryRun) `
            -DeleteRequested ([bool]$willRemoveSource)
        $archiveInfo.safeDelete = $safeDeleteDecision
        $statistics.source.safeDelete = @{
            state     = [string]$safeDeleteDecision.state
            canDelete = [bool]$safeDeleteDecision.canDelete
            reason    = [string]$safeDeleteDecision.reason
        }

        $writeBackupAuditReport = {
            $currentEndedAt = Get-Date
            $statistics.endedAt = $currentEndedAt.ToString("o")
            $statistics.durationSeconds = [Math]::Round(($currentEndedAt - $startedAt).TotalSeconds, 3)
            $statistics.source.removed = [bool]$sourceRemoved
            $statistics.source.existsAfterRun = if ([string]::IsNullOrWhiteSpace($projectRoot)) {
                $false
            }
            else {
                Test-Path -LiteralPath $projectRoot -PathType Container
            }

            $createdAuditReport = New-BackupAuditReport `
                -Project $project `
                -Archive $archiveInfo `
                -Statistics $statistics `
                -Manifest $manifest `
                -StorageTiers @($backupJobPayload.storageTiers) `
                -SourceIndex $sourceIntegrityIndex `
                -CleanupSummary $cleanupSummary `
                -ReportPlan $backupJobPayload.reports
            $savedReports = Save-BackupAuditReport `
                -Report $createdAuditReport `
                -Plan $backupJobPayload.reports `
                -DryRun:$DryRun
            $archiveInfo.reports = $savedReports
            $statistics.reports = @{
                state        = [string]$savedReports.state
                writtenCount = [int]$savedReports.summary.writtenCount
                failedCount  = [int]$savedReports.summary.failedCount
                files        = @($savedReports.files | ForEach-Object {
                        @{
                            format  = [string]$_.format
                            path    = [string]$_.path
                            written = [bool]$_.written
                            hash    = [string]$_.hash
                            error   = [string]$_.error
                        }
                    })
            }

            if ([int]$savedReports.summary.failedCount -gt 0) {
                Write-RenderKitLog -Level Warning -Message (
                    "Backup audit report completed with {0} failed file(s)." -f
                    [int]$savedReports.summary.failedCount
                )
            }
            else {
                Write-RenderKitLog -Level Info -Message (
                    "Backup audit report written ({0} file(s))." -f
                    [int]$savedReports.summary.writtenCount
                )
            }

            return [PSCustomObject]@{
                Report = $createdAuditReport
                Result = $savedReports
            }
        }

        if ($willRemoveSource -and -not [bool]$safeDeleteDecision.canDelete) {
            $blockedAuditReport = & $writeBackupAuditReport
            $auditReport = $blockedAuditReport.Report
            $reportResult = $blockedAuditReport.Result

            $failedRuleReasons = @(
                $safeDeleteDecision.failedRules |
                    ForEach-Object { [string]$_.reason } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            ) -join ','
            if ([string]::IsNullOrWhiteSpace($failedRuleReasons)) {
                $failedRuleReasons = [string]$safeDeleteDecision.reason
            }

            throw (
                "Source project was not removed because safe-delete checks failed. Reason={0}; FailedRules={1}." -f
                [string]$safeDeleteDecision.reason,
                $failedRuleReasons
            )
        }

        if ($willRemoveSource -and [bool]$safeDeleteDecision.canDelete) {
            Write-RenderKitLog -Level Info -Message "Removing source project folder '$projectRoot'."

            if ($lockHandle) {
                [void](Unlock-BackupLock -ProjectRoot $projectRoot -OwnerToken $lockHandle.OwnerToken)
                $lockHandle = $null
            }

            if (Test-Path -Path $projectRoot -PathType Container) {
                Remove-Item -Path $projectRoot -Recurse -Force -ErrorAction Stop
            }

            $sourceRemoved = -not (Test-Path -Path $projectRoot -PathType Container)
            if (-not $sourceRemoved) {
                Write-RenderKitLog -Level Error -Message "Source project folder '$projectRoot' could not be removed."
                throw "Source project folder '$projectRoot' could not be removed."
            }

            $script:RenderKitLoggingInitialized = $false
            $script:RenderKitLogFile = $null
            $script:RenderKitDebugLogFile = $null

            $archiveInfo.sourceRemoved = $true
            Remove-RenderKitProjectRegistryEntry `
                -ProjectId ([string]$project.Id)
            Write-Information "Source project folder removed: '$projectRoot'." -InformationAction Continue
        }
        elseif (-not $DryRun -and $KeepSourceProject) {
            Set-RenderKitProjectStatus `
                -ProjectRoot $projectRoot `
                -Status 'Archived' `
                -Reason 'Backup completed' `
                -Source 'Backup-Project' |
                Out-Null
            Write-RenderKitLog -Level Info -Message "Keeping source project folder: '$projectRoot'."
        }

        $finalAuditReport = & $writeBackupAuditReport
        $auditReport = $finalAuditReport.Report
        $reportResult = $finalAuditReport.Result

        if (-not $sourceRemoved) {
            Write-RenderKitLog -Level Info -Message "Backup process completed successfully."
        }
        else {
            Write-Information "Backup process completed successfully." -InformationAction Continue
        }

        return [PSCustomObject]@{
            ProjectName              = $project.Name
            ProjectId                = $project.Id
            RootPath                 = $projectRoot
            BackupPath               = if ($DryRun) { $null } else { $archiveDescriptor.ArchivePath }
            DestinationRoot          = $archiveDescriptor.DestinationRoot
            Profiles                 = @($rules.Profiles)
            SourceRemoved            = [bool]$sourceRemoved
            KeepSourceProject        = [bool]$KeepSourceProject
            DryRun                   = [bool]$DryRun
            ManifestPath             = $manifestPath
            ManifestArchiveEntryPath = $manifestArchiveEntryPath
            Manifest                 = $manifest
            Statistics               = $statistics
            Archive                  = $archiveInfo
            Reports                  = $reportResult
            AuditReport              = $auditReport
            CleanupSummary           = $cleanupSummary
        }
    }
    catch {
        Write-RenderKitLog -Level Error -Message "Backup failed: $($_.Exception.Message)"
        throw
    }
    finally {
        if ($lockHandle) {
            [void](Unlock-BackupLock -ProjectRoot $projectRoot -OwnerToken $lockHandle.OwnerToken)
        }
    }
}
