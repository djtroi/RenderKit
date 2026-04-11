Register-RenderKitFunction "New-RenderKitMapping"
function New-RenderKitMapping {
    <#
.SYNOPSIS
Creates a new user mapping file.

.DESCRIPTION
Ensures mapping storage exists, creates an empty mapping object, and persists it as JSON.

.PARAMETER Id
Mapping id / filename to create (with or without `.json` extension).

.EXAMPLE
New-RenderKitMapping -Id "camera"
Creates a new mapping file for id `camera`.

.EXAMPLE
New-RenderKitMapping -Id "audio.json"
Creates mapping file `audio.json` in the user mappings folder.

.INPUTS
None. You cannot pipe input to this command.

.OUTPUTS
None. The command creates or updates a mapping file on disk.

.LINK
Add-RenderKitTypeToMapping

.LINK
Add-RenderKitMappingToTemplate

.LINK
https://github.com/djtroi/RenderKit
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    Write-RenderKitLog -Level Debug -Message "New-RenderKitMapping started: Id='$Id'."

    $mappingPath = Get-RenderKitUserMappingPath -MappingId $Id
    $mappingFolder = Get-RenderKitUserMappingsRoot

    if (Test-Path $mappingPath) {
        if($PSCmdlet.ShouldProcess($Id, "Create a new mapping Folder")){
        Write-RenderKitLog -Level Error -Message "Mapping '$Id' already exists."
    }
}
    if (!(Test-Path $mappingFolder)){
        if($PSCmdlet.ShouldProcess($mappingFolder, "Create a new mapping Folder")){
            New-Item -ItemType Directory -Path $mappingFolder -ErrorAction Stop | Out-Null
        }
        Write-RenderKitLog -Level Error -Message "No mapping folder found... creating one."
    }
    $mapping = [RenderKitMapping]::new($Id)
    if($PSCmdlet.ShouldProcess($mappingPath, "Create a new mapping File")){
        Write-RenderKitMappingFile -Mapping $mapping -MappingId $Id
    }

Write-RenderKitLog -Level Info -Message "Mapping '$Id' created successfully"
}

