function New-RenderKitMapping {
    param(
        [Parameter(Mandatory)]
        [string]$Id 
    )
    $root = Get-RenderKitRoot 
    $mappingPath = Join-Path $root "mappings\$Id.json"

    if (Test-Path $mappingPath) {
        New-RenderKitLog -Level Error -Message "Mapping '$Id' already exists."
    }

    $mapping = [RenderKitMapping]::new($Id)

    $mapping | ConvertTo-Json -Depth 5 | 
    Set-Content -Path $mappingPath -Encoding UTF8 

Write-RenderKitLog -Level Info -Message "Mapping '$Id' created successfully"
}