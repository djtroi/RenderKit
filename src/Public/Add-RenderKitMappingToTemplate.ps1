Register-RenderKitFunction "Add-RenderKitMappingToTemplate"
function Add-RenderKitMappingToTemplate {
    <#
.SYNOPSIS
Adds a mapping reference to a template.

.DESCRIPTION
Loads a user template and appends the given MappingId to its Mappings collection.

.PARAMETER TemplateName
Name of the user template file (with or without `.json` extension).

.PARAMETER MappingId
Mapping id to add to the template's `Mappings` list.

.EXAMPLE
Add-RenderKitMappingToTemplate -TemplateName "default" -MappingId "camera"
Adds mapping id `camera` to template `default`.

.EXAMPLE
Add-RenderKitMappingToTemplate -TemplateName "default.json" -MappingId "audio"
Adds mapping id `audio` to template file `default.json`.

.INPUTS
None. You cannot pipe input to this command.

.OUTPUTS
None. The command updates the template file on disk.

.LINK
Add-FolderToTemplate

.LINK
New-RenderKitMapping

.LINK
https://github.com/djtroi/RenderKit
#>
    param(
        [string]$TemplateName,
        [string]$MappingId
    )

    Write-RenderKitLog -Level Debug -Message "Add-RenderKitMappingToTemplate started: Template='$TemplateName', MappingId='$MappingId'."

    $templatePath = Get-RenderKitUserTemplatePath -TemplateName $TemplateName

    if (!(Test-Path $templatePath)) {
        Write-RenderKitLog -Level Error -Message "Template $TemplateName not found."
    }

    $template = Read-RenderKitTemplateFile -Path $templatePath

    if (-not ($template.PSObject.Properties.Name -contains "Mappings")) {
        $template | Add-Member -MemberType NoteProperty -Name Mappings -Value ([System.Collections.ArrayList]::new()) -Force
    }
    elseif ($template.Mappings -isnot [System.Collections.ArrayList]) {
        $template.Mappings = [System.Collections.ArrayList]@($template.Mappings)
    }

    if ($template.Mappings -contains $MappingId) {
        Write-RenderKitLog -Level Warning -Message "Mapping $MappingId already exists in template $TemplateName."
    }
    else {
        $null = $template.Mappings.Add($MappingId)
    }

    Write-RenderKitTemplateFile -Template $template -Path $templatePath

    Write-RenderKitLog -Level Info -Message "Mapping $MappingId inserted into the template. "
}
