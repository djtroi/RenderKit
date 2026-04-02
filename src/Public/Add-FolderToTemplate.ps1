#todo buggy
<#
.SYNOPSIS
Adds a folder path to an existing RenderKit template.

.DESCRIPTION
Creates missing folder nodes recursively inside the template's `Folders` tree.
If `-MappingId` is provided, the mapping is assigned to the final folder node.

.PARAMETER TemplateName
Name of the user template file (with or without `.json` extension).

.PARAMETER FolderPath
Folder path to add. Supports `\` and `/` separators.

.PARAMETER MappingId
Optional mapping id assigned to the final folder in the given path.

.EXAMPLE
Add-FolderToTemplate -TemplateName "default" -FolderPath "Footage/CameraA"
Adds the folder path `Footage/CameraA` to template `default`.

.EXAMPLE
Add-FolderToTemplate -TemplateName "default" -FolderPath "Audio/VO" -MappingId "audio"
Adds `Audio/VO` and assigns mapping id `audio` to folder `VO`.

.INPUTS
None. You cannot pipe input to this command.

.OUTPUTS
None. The command updates the template file on disk.

.LINK
Add-RenderKitMappingToTemplate

.LINK
https://github.com/djtroi/RenderKit
#>
function Add-FolderToTemplate {
    param(
    [Parameter(Mandatory, Position = 0)]
    [string]$TemplateName,
    [Parameter(Mandatory, Position = 1)]
    [string]$FolderPath,
    [string]$MappingId
    )

    Write-RenderKitLog -Level Debug -Message "Add-FolderToTemplate started: Template='$TemplateName', FolderPath='$FolderPath', MappingId='$MappingId'."

    $templatePath = Get-RenderKitUserTemplatePath -TemplateName $TemplateName

    if (!(Test-Path $templatePath)) {
        Write-RenderKitLog -Level Error -Message "Template '$TemplateName' not found."
    }

    $json = Read-RenderKitTemplateFile -Path $templatePath

    if (!($json.Folders)) {
        $json | Add-Member -MemberType NoteProperty -Name Folders -Value ([System.Collections.ArrayList]::new()) -Force
    }
    elseif ($json.Folders -isnot [System.Collections.ArrayList]) {
        $json.Folders = [System.Collections.ArrayList]@($json.Folders)
    }

    $parts = $FolderPath -split '[\\/]'
    $currentLevel = $json.Folders

    foreach ($part in $parts) {

        $existing = $currentLevel | Where-Object Name -eq $part

        if (!($existing)) {

            $newFolder = [PSCustomObject]@{
                Name            = $part
                MappingId       = $null
                SubFolders      = [System.Collections.ArrayList]::new()
            }

            #$currentLevel += $newFolder
            $null = $currentLevel.Add($newFolder)
            $existing = $newFolder

        }
        if (-not $existing.SubFolders) {
            $existing.SubFolders = [System.Collections.ArrayList]::new()
        }
        elseif ($existing.SubFolders -isnot [System.Collections.ArrayList]) {
            $existing.SubFolders = [System.Collections.ArrayList]@($existing.SubFolders)
        }

        $currentLevel = $existing.SubFolders
    }

    # Mapping nur auf finalem Ordner setzen
    if ($MappingId) {
        $existing.MappingId = $MappingId
        Write-RenderKitLog -Level Debug -Message "Mapping found: $MappingId"
    }

    Write-RenderKitTemplateFile -Template $json -Path $templatePath

    Write-RenderKitLog -Level Info -Message "Folder '$FolderPath' added to '$TemplateName'"
}
