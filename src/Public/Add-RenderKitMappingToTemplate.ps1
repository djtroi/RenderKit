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

    if (-not $template.Mappings) {
        $template | Add-Member -MemberType NoteProperty -Name Mappings -Value @() -Force
    }
    $template.Mappings += $MappingId

    Write-RenderKitTemplateFile -Template $template -Path $templatePath

    Write-RenderKitLog -Level Info -Message "Mapping $MappingId inserted into the template. "
}
