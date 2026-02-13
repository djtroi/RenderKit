function New-RenderKitTemplate {
    param(
        [Parameter(Mandatory)]
        [string]$Name 
    )

    $root = Get-RenderKitRoot
    $templatePath = Join-Path $root "templates\$Name.json"

    if (Test-Path $templatePath) {
        New-RenderKitLog -Level Error -Message "Template $Name already exists."
    }

    $template = [RenderKitTemplate]::new($Name)

    $template | ConvertTo-Json -Depth 5 | 
    Set-Content -Path $templatePath -Encoding UTF8

    New-RenderKitLog -Level Info -Message "Template $Name created successfully."
}