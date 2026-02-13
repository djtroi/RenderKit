function Add-RenderKitMappingToTemplate {
    param(
        [string]$TemplateName,
        [string]$MappingId
    )

    $root = Get-RenderKitRoot 
    $templatePath = Join-Path $root "templates\$TemplateName.json"

    if (!(Test-Path $templatePath)) {
        Write-RenderKitLog -Level Error -Message "Template $TemplateName not found."
    }

    $template = Get-Content $templatePath | ConvertFrom-Json

    $template.Mappings += $MappingId 

    $template | ConvertTo-Json -Depth 5 | 
    Set-Content $templatePath -Encoding UTF8

    Write-RenderKitLog -Level Info -Message "Mapping $MappingId inserted into the template. "
}