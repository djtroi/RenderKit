Register-RenderKitFunction "Remove-Project"
function Remove-Project {
    <#
.SYNOPSIS
Removes an existing RenderKit project.

.DESCRIPTION
Resolves a RenderKit project by name and optional base path, validates the project metadata, and removes the complete project folder from disk.
Supports `-WhatIf` / `-Confirm` via `SupportsShouldProcess`.

.PARAMETER ProjectName
Name of the project folder to remove.

.PARAMETER Path
Project root directory that contains the project folder.
If omitted, the default project root from config is used.

.PARAMETER DryRun
Simulates project removal without deleting files.

.EXAMPLE
Remove-Project -ProjectName "ClientA_2026"
Removes project `ClientA_2026` from the configured default project root.

.EXAMPLE
Remove-Project -ProjectName "ClientA_2026" -Path "D:\Projects" -WhatIf
Shows what would be removed from the custom project root without deleting the project.

.EXAMPLE
Remove-Project -ProjectName "ClientA_2026" -Confirm
Prompts for confirmation before removing the project.

.INPUTS
None. You cannot pipe input to this command.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns removal result data (project id, project name, root path, removed flag, dry-run flag).

.LINK
New-Project

.LINK
Set-ProjectRoot

.LINK
https://github.com/djtroi/RenderKit
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$ProjectName,
        [string]$Path,
        [switch]$DryRun
    )

    Write-RenderKitLog -Level Info -Message "Starting removal for project '$ProjectName'."
    Write-RenderKitLog -Level Debug -Message "Remove-Project started: ProjectName='$ProjectName', Path='$Path', DryRun='$DryRun'."

    $project = Get-RenderKitProject -ProjectName $ProjectName -Path $Path
    $projectRoot = [string]$project.RootPath
    $metadataPath = [string]$project.MetadataPath

    $actionDescription = if ($DryRun) {
        "Simulate removal of RenderKit project folder '$projectRoot'"
    }
    else {
        "Remove RenderKit project folder '$projectRoot'"
    }

    if (-not $PSCmdlet.ShouldProcess($projectRoot, $actionDescription)) {
        return $null
    }

    if ($DryRun) {
        Write-RenderKitLog -Level Info -Message "DryRun mode: project folder '$projectRoot' will not be removed."
        return [PSCustomObject]@{
            ProjectName  = [string]$project.Name
            ProjectId    = [string]$project.Id
            RootPath     = $projectRoot
            MetadataPath = $metadataPath
            Removed      = $false
            DryRun       = $true
            ExistsAfter  = [bool](Test-Path -LiteralPath $projectRoot -PathType Container)
        }
    }

    try {
        Remove-RenderKitProjectDirectory -ProjectRoot $projectRoot

        $removed = -not (Test-Path -LiteralPath $projectRoot -PathType Container)
        if (-not $removed) {
            Write-RenderKitLog -Level Error -Message "Project folder '$projectRoot' could not be removed."
            throw "Project folder '$projectRoot' could not be removed."
        }

        Write-RenderKitLog -Level Info -Message "Project '$($project.Name)' removed successfully from '$projectRoot'."

        return [PSCustomObject]@{
            ProjectName  = [string]$project.Name
            ProjectId    = [string]$project.Id
            RootPath     = $projectRoot
            MetadataPath = $metadataPath
            Removed      = $true
            DryRun       = $false
            ExistsAfter  = $false
        }
    }
    catch {
        Write-RenderKitLog -Level Error -Message "Project removal failed: $($_.Exception.Message)"
        throw
    }
}
