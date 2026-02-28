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
function Backup-Project{
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$ProjectName,
        [string]$Path,
        [Alias("Software")]
        [string[]]$Profile = @("General"),
        [string]$DestinationRoot,
        [switch]$KeepEmptyFolders,
        [switch]$KeepSourceProject,
        [switch]$DryRun
    )
    Write-RenderKitLog -Level Info -Message "Starting backup for project '$ProjectName'."
    Write-RenderKitLog -Level Debug -Message (
        "Parameters: Path='{0}' Profile='{1}' DestinationRoot='{2}' KeepEmptyFolders='{3}' KeepSourceProject='{4}' DryRun='{5}'." -f
        $Path, ($Profile -join ","), $DestinationRoot, $KeepEmptyFolders, $KeepSourceProject, $DryRun
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

    $rules = Get-CleanupRules -Profile $Profile
    $startedAt = Get-Date
    $archiveDescriptor = Resolve-BackupArchivePath `
        -Project $project `
        -DestinationRoot $DestinationRoot `
        -Timestamp $startedAt

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

        $statsBefore = Get-BackupProjectStatistics -ProjectPath $projectRoot

        Write-RenderKitLog -Level Info -Message "Cleaning project artifacts..."
        $artifactCleanup = Remove-ProjectArtifacts `
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
            $emptyFolderCleanup = Remove-EmptyFolders -Path $projectRoot -DryRun:$DryRun
            Add-Member -InputObject $emptyFolderCleanup -NotePropertyName Skipped -NotePropertyValue $false -Force
        }

        if (-not $DryRun) {
            $sourceIntegrityIndex = Get-BackupFileHashIndex `
                -RootPath $projectRoot `
                -BasePath $projectRoot `
                -Algorithm "SHA256"
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
        }

        if (-not $DryRun) {
            $archiveResult = Compress-Project `
                -ProjectPath $projectRoot `
                -DestinationPath $archiveDescriptor.ArchivePath

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
                -Algorithm "SHA256"

            if (-not $integrityCheck.IsMatch) {
                throw (
                    "Archive integrity check failed. MissingInArchive={0}, ExtraInArchive={1}, HashMismatches={2}." -f
                    $integrityCheck.MissingInArchiveCount,
                    $integrityCheck.ExtraInArchiveCount,
                    $integrityCheck.HashMismatchCount
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
            Get-BackupProjectStatistics -ProjectPath $projectRoot
        }

        if (-not $DryRun -and -not $KeepSourceProject) {
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
                throw "Source project folder '$projectRoot' could not be removed."
            }

            # Reset file logging context because source .renderkit was deleted.
            $script:RenderKitLoggingInitialized = $false
            $script:RenderKitLogFile = $null
            $script:RenderKitDebugLogFile = $null

            Write-Information "Source project folder removed: '$projectRoot'." -InformationAction Continue
        }
        elseif (-not $DryRun -and $KeepSourceProject) {
            Write-RenderKitLog -Level Info -Message "Keeping source project folder: '$projectRoot'."
        }

        $archiveInfo.sourceRemoved = [bool]$sourceRemoved
        $archiveInfo.logInjection = @{
            addedCount = [int]$archiveLogInjection.AddedCount
            addedEntries = @($archiveLogInjection.AddedEntries)
        }
        $archiveInfo.contentIntegrity = @{
            checked = [bool](-not $DryRun)
            isMatch = if ($integrityCheck) { [bool]$integrityCheck.IsMatch } else { $null }
            algorithm = if ($integrityCheck) { [string]$integrityCheck.Algorithm } else { $null }
            sourceFileCount = if ($integrityCheck) { [int]$integrityCheck.SourceFileCount } else { $null }
            archiveFileCount = if ($integrityCheck) { [int]$integrityCheck.ArchiveFileCount } else { $null }
            missingInArchiveCount = if ($integrityCheck) { [int]$integrityCheck.MissingInArchiveCount } else { $null }
            extraInArchiveCount = if ($integrityCheck) { [int]$integrityCheck.ExtraInArchiveCount } else { $null }
            hashMismatchCount = if ($integrityCheck) { [int]$integrityCheck.HashMismatchCount } else { $null }
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
                path             = $projectRoot
                removed          = [bool]$sourceRemoved
                existsAfterRun   = [bool](Test-Path -Path $projectRoot -PathType Container)
            }
            archiveIntegrity = if ($integrityCheck) {
                @{
                    checked = $true
                    isMatch = [bool]$integrityCheck.IsMatch
                    algorithm = [string]$integrityCheck.Algorithm
                    sourceFileCount = [int]$integrityCheck.SourceFileCount
                    archiveFileCount = [int]$integrityCheck.ArchiveFileCount
                    missingInArchiveCount = [int]$integrityCheck.MissingInArchiveCount
                    extraInArchiveCount = [int]$integrityCheck.ExtraInArchiveCount
                    hashMismatchCount = [int]$integrityCheck.HashMismatchCount
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
                profiles         = @($rules.Profiles)
                keepEmptyFolders = [bool]$KeepEmptyFolders
                keepSourceProject = [bool]$KeepSourceProject
                dryRun           = [bool]$DryRun
                destinationRoot  = [string]$archiveDescriptor.DestinationRoot
                removeSourceProject = [bool](-not $KeepSourceProject)
            } `
            -Statistics $statistics `
            -Archive $archiveInfo `
            -CleanupSummary $cleanupSummary

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

        if (-not $sourceRemoved) {
            Write-RenderKitLog -Level Info -Message "Backup process completed successfully."
        }
        else {
            Write-Information "Backup process completed successfully." -InformationAction Continue
        }

        return [PSCustomObject]@{
            ProjectName    = $project.Name
            ProjectId      = $project.Id
            RootPath       = $projectRoot
            BackupPath     = if ($DryRun) { $null } else { $archiveDescriptor.ArchivePath }
            DestinationRoot = $archiveDescriptor.DestinationRoot
            Profiles       = @($rules.Profiles)
            SourceRemoved  = [bool]$sourceRemoved
            KeepSourceProject = [bool]$KeepSourceProject
            DryRun         = [bool]$DryRun
            ManifestPath   = $manifestPath
            ManifestArchiveEntryPath = $manifestArchiveEntryPath
            Manifest       = $manifest
            Statistics     = $statistics
            Archive        = $archiveInfo
            CleanupSummary = $cleanupSummary
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
