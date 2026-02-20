function Add-RenderKitMappingToTemplate {
    param(
        [string]$TemplateName,
        [string]$MappingId
    )

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
