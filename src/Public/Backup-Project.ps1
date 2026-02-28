<#
.SYNOPSIS
Cleans and archives a RenderKit project.

.DESCRIPTION
Resolves a project, removes configured artifacts, optionally removes empty folders, creates a ZIP, and writes a backup manifest.
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

.INPUTS
None. You cannot pipe input to this command.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns project and backup result data (project id, root path, backup path, dry-run flag).

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
        [Parameter(Mandatory)]
        [string]$ProjectName,
        [string]$Path,
        [Alias("Software")]
        [string[]]$Profile = @("General"),
        [string]$DestinationRoot,
        [switch]$KeepEmptyFolders,
        [switch]$DryRun
    )
    Write-RenderKitLog -Level Info -Message "Starting backup for project '$ProjectName'."
    Write-RenderKitLog -Level Debug -Message (
        "Parameters: Path='{0}' Profile='{1}' DestinationRoot='{2}' KeepEmptyFolders='{3}' DryRun='{4}'." -f
        $Path, ($Profile -join ","), $DestinationRoot, $KeepEmptyFolders, $DryRun
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

    $actionDescription = "Clean project artifacts and create backup archive '$($archiveDescriptor.ArchivePath)'"
    if (-not $PSCmdlet.ShouldProcess($projectRoot, $actionDescription)) {
        return $null
    }

    $lockHandle = $null
    $manifestPath = $null

    try {
        if (-not $DryRun) {
            if (-not (Test-Path -Path $archiveDescriptor.DestinationRoot -PathType Container)) {
                New-Item -ItemType Directory -Path $archiveDescriptor.DestinationRoot -Force | Out-Null
            }

            $lockHandle = Get-BackupLock -ProjectRoot $projectRoot
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

        $archiveInfo = @{
            destinationRoot = $archiveDescriptor.DestinationRoot
            fileName        = $archiveDescriptor.ArchiveFileName
            path            = $archiveDescriptor.ArchivePath
            created         = $false
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
        }

        $statsAfter = if ($DryRun) {
            $statsBefore
        }
        else {
            Get-BackupProjectStatistics -ProjectPath $projectRoot
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
                fileCount      = [int]$statsAfter.FileCount
                directoryCount = [int]$statsAfter.DirectoryCount
                totalBytes     = [int64]$statsAfter.TotalBytes
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
                dryRun           = [bool]$DryRun
                destinationRoot  = [string]$archiveDescriptor.DestinationRoot
            } `
            -Statistics $statistics `
            -Archive $archiveInfo `
            -CleanupSummary $cleanupSummary

        if (-not $DryRun) {
            $manifestPath = Save-BackupManifest `
                -Manifest $manifest `
                -ProjectRoot $projectRoot
        }
        else {
            Write-RenderKitLog -Level Info -Message "DryRun mode: manifest was generated in-memory but not written to disk."
        }

        Write-RenderKitLog -Level Info -Message "Backup process completed successfully."

        return [PSCustomObject]@{
            ProjectName    = $project.Name
            ProjectId      = $project.Id
            RootPath       = $projectRoot
            BackupPath     = if ($DryRun) { $null } else { $archiveDescriptor.ArchivePath }
            DestinationRoot = $archiveDescriptor.DestinationRoot
            Profiles       = @($rules.Profiles)
            DryRun         = [bool]$DryRun
            ManifestPath   = $manifestPath
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
