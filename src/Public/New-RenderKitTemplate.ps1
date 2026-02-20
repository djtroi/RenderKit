function New-RenderKitTemplate {
    param(
        [Parameter(Mandatory)]
        [string]$Name 
    )

    $templateFolder = Get-RenderKitUserTemplatesRoot
    $templatePath = Get-RenderKitUserTemplatePath -TemplateName $Name

    if (Test-Path $templatePath) {
        Write-RenderKitLog -Level Error -Message "Template $Name already exists."
    }

    if (!(Test-Path $templateFolder)){
        New-Item -ItemType Directory -Path $templateFolder -ErrorAction Stop | Out-Null
        Write-RenderKitLog -Level Debug -Message "No template folder in AppData... creating one."
    }
    $template = [RenderKitTemplate]::new($Name)

    Write-RenderKitTemplateFile -Template $template -Path $templatePath

    Write-RenderKitLog -Level Info -Message "Template $Name created successfully."
}
