function New-RenderKitTemplate {
    param(
        [Parameter(Mandatory)]
        [string]$Name 
    )

    $root = Get-RenderKitRoot
    $templateFolder = Join-Path $root "templates\"
    $templatePath = Join-Path $root "templates\$Name.json"

    if (Test-Path $templatePath) {
        Write-RenderKitLog -Level Error -Message "Template $Name already exists."
    }

    if (!(Test-Path $templateFolder)){
        New-Item -ItemType Directory -Path $templateFolder -ErrorAction Stop | Out-Null
        Write-RenderKitLog -Level Debug -Message "No template folder in AppData... creating one."
    }
    $template = [RenderKitTemplate]::new($Name)

    $template | ConvertTo-Json -Depth 5 | 
    Set-Content -Path $templatePath -Encoding UTF8

    Write-RenderKitLog -Level Info -Message "Template $Name created successfully."
}