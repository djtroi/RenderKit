Register-RenderKitFunction "Rename-Project"
function Rename-Project {
    <#
.SYNOPSIS
Renames an existing RenderKit project.

.DESCRIPTION
Resolves a RenderKit project by its current name and optional base path, validates the existing project metadata, renames the project folder, and updates only the project name stored in metadata.
The project GUID is preserved so the project remains uniquely identifiable after the rename.
Supports `-WhatIf` / `-Confirm` via `SupportsShouldProcess`.

.PARAMETER ProjectName
Current name of the project folder to rename.

.PARAMETER NewName
New project folder name and metadata project name.

.PARAMETER Path
Project root directory that contains the project folder.
If omitted, the default project root from config is used.

.PARAMETER DryRun
Simulates project rename without changing files or metadata.

.EXAMPLE
Rename-Project -ProjectName "ClientA_2026" -NewName "ClientA_2026_Final"
Renames project `ClientA_2026` in the configured default project root.

.EXAMPLE
Rename-Project -ProjectName "ClientA_2026" -NewName "ClientA_2026_Final" -Path "D:\Projects" -WhatIf
Shows what would be renamed from the custom project root without changing files.

.EXAMPLE
Rename-Project -ProjectName "ClientA_2026" -NewName "ClientA_2026_Final" -Confirm
Prompts for confirmation before renaming the project.

.INPUTS
None. You cannot pipe input to this command.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns rename result data (project id, old name/path, new name/path, renamed flag, dry-run flag).

.LINK
New-Project

.LINK
Remove-Project

.LINK
Set-ProjectRoot

.LINK
https://github.com/djtroi/RenderKit
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$ProjectName,
        [Parameter(Mandatory, Position = 1)]
        [string]$NewName,
        [string]$Path,
        [switch]$DryRun
    )

    Write-RenderKitLog -Level Info -Message "Starting rename for project '$ProjectName' to '$NewName'."
    Write-RenderKitLog -Level Debug -Message "Rename-Project started: ProjectName='$ProjectName', NewName='$NewName', Path='$Path', DryRun='$DryRun'."

    if ([string]::IsNullOrWhiteSpace($NewName)) {
        Write-RenderKitLog -Level Error -Message "New project name must not be empty."
        throw "New project name must not be empty."
    }

    if ($ProjectName -eq $NewName) {
        Write-RenderKitLog -Level Error -Message "New project name must be different from current project name."
        throw "New project name must be different from current project name."
    }

    $project = Get-RenderKitProject -ProjectName $ProjectName -Path $Path
    $oldProjectRoot = [string]$project.RootPath
    $projectParent = Split-Path -Path $oldProjectRoot -Parent
    $newProjectRoot = Join-Path -Path $projectParent -ChildPath $NewName

    if (Test-Path -LiteralPath $newProjectRoot) {
        Write-RenderKitLog -Level Error -Message "Target project path already exists: $newProjectRoot"
        throw "Target project path already exists: $newProjectRoot"
    }

    $projectId = [string]$project.Id
    $oldMetadataPath = [string]$project.MetadataPath
    $newMetadataPath = Get-RenderKitProjectMetadataPath -ProjectRoot $newProjectRoot

    $actionDescription = if ($DryRun) {
        "Simulate rename of RenderKit project '$ProjectName' to '$NewName'"
    }
    else {
        "Rename RenderKit project '$ProjectName' to '$NewName' while preserving project id '$projectId'"
    }

    if (-not $PSCmdlet.ShouldProcess($oldProjectRoot, $actionDescription)) {
        return $null
    }

    if ($DryRun) {
        Write-RenderKitLog -Level Info -Message "DryRun mode: project folder '$oldProjectRoot' will not be renamed."
        return [PSCustomObject]@{
            ProjectId       = $projectId
            OldProjectName  = [string]$project.Name
            NewProjectName  = $NewName
            OldRootPath     = $oldProjectRoot
            NewRootPath     = $newProjectRoot
            OldMetadataPath = $oldMetadataPath
            NewMetadataPath = $newMetadataPath
            Renamed         = $false
            DryRun          = $true
            IdPreserved     = $true
        }
    }

    $directoryRenamed = $false
    $metadataUpdated = $false

    try {
        Rename-RenderKitProjectDirectory `
            -ProjectRoot $oldProjectRoot `
            -NewProjectRoot $newProjectRoot
        $directoryRenamed = $true

        $metadata = Update-RenderKitProjectName `
            -ProjectRoot $newProjectRoot `
            -NewProjectName $NewName `
            -ExpectedProjectId $projectId
        $metadataUpdated = $true

        $renamed = (Test-Path -LiteralPath $newProjectRoot -PathType Container) -and -not (Test-Path -LiteralPath $oldProjectRoot -PathType Container)
        if (-not $renamed) {
            Write-RenderKitLog -Level Error -Message "Project folder '$oldProjectRoot' could not be renamed to '$newProjectRoot'."
            throw "Project folder '$oldProjectRoot' could not be renamed to '$newProjectRoot'."
        }

        $idPreserved = ([string]$metadata.project.id -eq $projectId)
        if (-not $idPreserved) {
            Write-RenderKitLog -Level Error -Message "Project id changed during rename for '$newProjectRoot'."
            throw "Project id changed during rename for '$newProjectRoot'."
        }

        Write-RenderKitLog -Level Info -Message "Project '$ProjectName' renamed successfully to '$NewName' with preserved id '$projectId'."

        return [PSCustomObject]@{
            ProjectId       = $projectId
            OldProjectName  = [string]$project.Name
            NewProjectName  = [string]$metadata.project.name
            OldRootPath     = $oldProjectRoot
            NewRootPath     = $newProjectRoot
            OldMetadataPath = $oldMetadataPath
            NewMetadataPath = $newMetadataPath
            Renamed         = $true
            DryRun          = $false
            IdPreserved     = $idPreserved
        }
    }
    catch {
        $renameError = $_
        if ($directoryRenamed -and -not $metadataUpdated -and (Test-Path -LiteralPath $newProjectRoot -PathType Container) -and -not (Test-Path -LiteralPath $oldProjectRoot)) {
            try {
                Rename-RenderKitProjectDirectory `
                    -ProjectRoot $newProjectRoot `
                    -NewProjectRoot $oldProjectRoot
                Write-RenderKitLog -Level Warning -Message "Rolled back project folder rename from '$newProjectRoot' to '$oldProjectRoot'."
            }
            catch {
                Write-RenderKitLog -Level Error -Message "Project rename rollback failed: $($_.Exception.Message)"
            }
        }

        Write-RenderKitLog -Level Error -Message "Project rename failed: $($renameError.Exception.Message)"
        throw $renameError
    }
}