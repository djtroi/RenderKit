Register-RenderKitFunction "Copy-Project"
function Copy-Project {
    <#
.SYNOPSIS
Copys an existing RenderKit project.

.DESCRIPTION
Resolves a RenderKit project by name and optional base path, validates the existing project metadata, copies the complete project folder, and writes fresh Copy metadata.
The Copyd project receives a new GUID so the source and Copy remain uniquely identifiable.
Supports `-WhatIf` / `-Confirm` via `SupportsShouldProcess`.

.PARAMETER ProjectName
Name of the existing project folder to Copy.

.PARAMETER NewName
Name of the Copyd project folder and metadata project name.
If omitted, `-Copy` is appended to the source project name.

.PARAMETER Path
Project root directory that contains the source project folder and where the Copy is created.
If omitted, the default project root from config is used.

.PARAMETER DryRun
Simulates project cloning without copying files or writing metadata.

.EXAMPLE
Copy-Project -ProjectName "ClientA_2026"
Copys project `ClientA_2026` to `ClientA_2026-Copy` in the configured default project root.

.EXAMPLE
Copy-Project -ProjectName "ClientA_2026" -NewName "ClientA_2026_VariantB"
Copys project `ClientA_2026` using an explicit Copy name.

.EXAMPLE
Copy-Project -ProjectName "ClientA_2026" -NewName "ClientA_2026_VariantB" -Path "D:\Projects" -WhatIf
Shows what would be Copyd from the custom project root without changing files.

.INPUTS
None. You cannot pipe input to this command.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns Copy result data (source project id/path, Copy project id/path, Copyd flag, dry-run flag).

.LINK
New-Project

.LINK
Rename-Project

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
        [Parameter(Position = 1)]
        [string]$NewName,
        [string]$Path,
        [switch]$DryRun
    )

    if ([string]::IsNullOrWhiteSpace($NewName)) {
        $NewName = "$ProjectName-Copy"
    }

    Write-RenderKitLog -Level Info -Message "Starting Copy for project '$ProjectName' to '$NewName'."
    Write-RenderKitLog -Level Debug -Message "Copy-Project started: ProjectName='$ProjectName', NewName='$NewName', Path='$Path', DryRun='$DryRun'."

    if ([string]::IsNullOrWhiteSpace($NewName)) {
        Write-RenderKitLog -Level Error -Message "Copy project name must not be empty."
        throw "Copy project name must not be empty."
    }

    if ($ProjectName -eq $NewName) {
        Write-RenderKitLog -Level Error -Message "Copy project name must be different from source project name."
        throw "Copy project name must be different from source project name."
    }

    $sourceProject = Get-RenderKitProject -ProjectName $ProjectName -Path $Path
    $sourceProjectRoot = [string]$sourceProject.RootPath
    $projectParent = Split-Path -Path $sourceProjectRoot -Parent
    $CopyProjectRoot = Join-Path -Path $projectParent -ChildPath $NewName

    if (Test-Path -LiteralPath $CopyProjectRoot) {
        Write-RenderKitLog -Level Error -Message "Copy project path already exists: $CopyProjectRoot"
        throw "Copy project path already exists: $CopyProjectRoot"
    }

    $sourceProjectId = [string]$sourceProject.Id
    $CopyProjectId = [guid]::NewGuid().Guid
    $sourceMetadataPath = [string]$sourceProject.MetadataPath
    $CopyMetadataPath = Get-RenderKitProjectMetadataPath -ProjectRoot $CopyProjectRoot

    $actionDescription = if ($DryRun) {
        "Simulate Copy of RenderKit project '$ProjectName' to '$NewName'"
    }
    else {
        "Copy RenderKit project '$ProjectName' to '$NewName' with new project id '$CopyProjectId'"
    }

    if (-not $PSCmdlet.ShouldProcess($sourceProjectRoot, $actionDescription)) {
        return $null
    }

    if ($DryRun) {
        Write-RenderKitLog -Level Info -Message "DryRun mode: project folder '$sourceProjectRoot' will not be Copyd."
        return [PSCustomObject]@{
            SourceProjectName  = [string]$sourceProject.Name
            SourceProjectId    = $sourceProjectId
            SourceRootPath     = $sourceProjectRoot
            SourceMetadataPath = $sourceMetadataPath
            CopyProjectName   = $NewName
            CopyProjectId     = $CopyProjectId
            CopyRootPath      = $CopyProjectRoot
            CopyMetadataPath  = $CopyMetadataPath
            Copyd             = $false
            DryRun             = $true
            NewIdCreated       = $true
        }
    }

    $directoryCopyd = $false

    try {
        Copy-RenderKitProjectDirectory `
            -ProjectRoot $sourceProjectRoot `
            -CopyProjectRoot $CopyProjectRoot
        $directoryCopyd = $true

        $metadata = Set-RenderKitProjectCopyMetadata `
            -ProjectRoot $CopyProjectRoot `
            -ProjectName $NewName `
            -ProjectId $CopyProjectId `
            -SourceProjectId $sourceProjectId

        $Copyd = (Test-Path -LiteralPath $CopyProjectRoot -PathType Container) -and (Test-Path -LiteralPath $sourceProjectRoot -PathType Container)
        if (-not $Copyd) {
            Write-RenderKitLog -Level Error -Message "Project folder '$sourceProjectRoot' could not be Copyd to '$CopyProjectRoot'."
            throw "Project folder '$sourceProjectRoot' could not be Copyd to '$CopyProjectRoot'."
        }

        $newIdCreated = ([string]$metadata.project.id -eq $CopyProjectId) -and ([string]$metadata.project.id -ne $sourceProjectId)
        if (-not $newIdCreated) {
            Write-RenderKitLog -Level Error -Message "Copy project id was not created correctly for '$CopyProjectRoot'."
            throw "Copy project id was not created correctly for '$CopyProjectRoot'."
        }

        Write-RenderKitLog -Level Info -Message "Project '$ProjectName' Copyd successfully to '$NewName' with new id '$CopyProjectId'."

        return [PSCustomObject]@{
            SourceProjectName  = [string]$sourceProject.Name
            SourceProjectId    = $sourceProjectId
            SourceRootPath     = $sourceProjectRoot
            SourceMetadataPath = $sourceMetadataPath
            CopyProjectName   = [string]$metadata.project.name
            CopyProjectId     = [string]$metadata.project.id
            CopyRootPath      = $CopyProjectRoot
            CopyMetadataPath  = $CopyMetadataPath
            Copyd             = $true
            DryRun             = $false
            NewIdCreated       = $newIdCreated
        }
    }
    catch {
        $CopyError = $_
        if ($directoryCopyd -and (Test-Path -LiteralPath $CopyProjectRoot -PathType Container)) {
            try {
                Remove-RenderKitProjectDirectory -ProjectRoot $CopyProjectRoot
                Write-RenderKitLog -Level Warning -Message "Rolled back Copyd project folder '$CopyProjectRoot'."
            }
            catch {
                Write-RenderKitLog -Level Error -Message "Project Copy rollback failed: $($_.Exception.Message)"
            }
        }

        Write-RenderKitLog -Level Error -Message "Project Copy failed: $($CopyError.Exception.Message)"
        throw $CopyError
    }
}