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

.PARAMETER Software
Cleanup profile names used to decide which artifacts are removed before archiving.

.PARAMETER KeepEmptyFolders
Keeps empty folders after cleanup when set.

.PARAMETER DryRun
Simulates cleanup and archive operations without changing files.

.EXAMPLE
Backup-Project -ProjectName "ClientA_2026"
Backs up project `ClientA_2026` from the configured default project root.

.EXAMPLE
Backup-Project -ProjectName "ClientA_2026" -Path "D:\Projects" -Software DaVinci -DryRun
Simulates a DaVinci-focused backup for the given path.

.EXAMPLE
Backup-Project -ProjectName "ClientA_2026" -Path "D:\Projects" -KeepEmptyFolders -Confirm
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
        [string]$Software ,#= @("DaVinci", "Adobe", "General"),
        [switch]$KeepEmptyFolders,
        [switch]$DryRun
    )
    #-------------------------------------------------------------
    # PHASE 1 : Command Start 
    #-------------------------------------------------------------
    Write-RenderKitLog -Level Info -Message "Starting backup for project '$ProjectName'"
    Write-RenderKitLog -Level Debug -Message "Parameters: Path='$Path' Software='$Software' Keep empty folders='$KeepEmptyFolders' Dry run='$DryRun'"

    $config = Get-RenderKitConfig

    #-------------------------------------------------------------
    # PHASE 2 : Resolve Path 
    #-------------------------------------------------------------

    If (!($Path)){
        if (!($config.DefaultProjectPath)){
            Write-RenderKitLog -Level Error -Message "No default project path configured"
            return
        }

        Write-RenderKitLog -Level Warning -Message "No path provided. Using default project path"
        $Path = $config.DefaultProjectPath
    }

    #-------------------------------------------------------------
    # PHASE 3 : Resolve Project 
    #-------------------------------------------------------------

    $Project = Get-RenderKitProject -ProjectName $ProjectName -Path $Path

    if (!($Project)){
        Write-RenderKitLog -Level Error -Message "Project '$ProjectName' not found"
        return
    }

    $ProjectRoot = $Project.RootPath

    Write-RenderKitLog -Level Debug -Message "Project validated at $ProjectRoot"

    #-------------------------------------------------------------
    # PHASE 4 : ShouldProcess 
    #-------------------------------------------------------------

    if (!($PSCmdlet.ShouldProcess(
        $ProjectRoot,
        "Clean project artifacts and create backup archive"
    ))){ return }

    #-------------------------------------------------------------
    # PHASE 5 : Execution 
    #-------------------------------------------------------------

    try{
        Get-BackupLock -ProjectRoot $ProjectRoot
        $rules = Get-CleanupRules -Software $Software

        Write-RenderKitLog -Level Info -Message "Cleaning project artifacts..."

        Remove-ProjectArtifacts `
        -ProjectPath $ProjectRoot `
        -Rules $rules `
        -DryRun:$DryRun

        if (!($KeepEmptyFolders)){
            Remove-EmptyFolders -Path $ProjectRoot -DryRun:$DryRun
        }

        $zipPath = $null 

        if (!($DRyRun)){
            $zipPath = "$ProjectRoot.zip"

            Compress-Project `
            -ProjectPath $ProjectRoot `
            -DestinationPath $zipPath

            WRite-RenderKitLog -Level Info -Message "Backup archive created: $zipPath"
        }
        else {
            Write-RenderKitLog -Level Warning -Message "DryRun enabled - no files were deleted or Archived"
        }

    #-------------------------------------------------------------
    # PHASE 6 : Manifest 
    #-------------------------------------------------------------

    $manifest = New-BackupManifest `
    -Project $Project
    -Options @{
        software            =   $Software
        KeepEmptyFolders    =   $KeepEmptyFolders.IsPresent
        dryRun              =   $DryRun.IsPresent
    }

    Save-BackupManifest `
    -Manifest $manifest `
    -ProjectRoot $ProjectRoot

    Write-RenderKitLog -Level Info -Message "Backup process completed successfully."

    #-------------------------------------------------------------
    # PHASE 7 : Result
    #-------------------------------------------------------------

    return [PSCustomObject]@{
        ProjectName =   $Project.Name    
        ProjectId   =   $Project.Id 
        RootPath    =   $ProjectRoot
        BackupPath  =   $zipPath
        DryRun      =   $DryRun.IsPresent
    }

    }

    catch{
        Write-RenderKitLog -Level Error -Message "Backup failed: $_"
        throw
    }
    finally{
        Unlock-BackupLock -ProjectRoot $ProjectRoot 
    }
}
