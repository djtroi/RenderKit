function Get-ProjectTemplate {
    param(
        [Parameter(Mandatory)]
        [string]$TemplateName
    )
    $root = Get-RenderKitRoot
    $templatePath = Join-Path $root "templates\$TemplateName.json" 

    if(!(Test-Path $templatePath)) {
        Write-RenderKitLog -Level Error -Message " $TemplateName not found at $templatePath"
    }

    $raw = Get-Content $templatePath -Raw 

    try {
        $json = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-RenderKitLog -Level Error -Message " Template $TemplateName contains invalid JSON" 
    }

    Validate-ProjectTemplate -Template $json 

    return $json
}

function Confirm-Template {}
    param(
        
    )
}