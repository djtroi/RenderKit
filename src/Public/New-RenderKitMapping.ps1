function New-RenderKitMapping {
    param(
        [Parameter(Mandatory)]
        [string]$Id 
    )
    $root = Get-RenderKitRoot 
    $mappingPath = Join-Path $root "mappings\$Id.json"
    $mappingFolder = Join-Path $root "mappings\"

    if (Test-Path $mappingPath) {
        Write-RenderKitLog -Level Error -Message "Mapping '$Id' already exists."
    }
    if (!(Test-Path $mappingFolder)){
        New-Item -ItemType Directory -Path $mappingFolder -ErrorAction Stop | Out-Null
        Write-RenderKitLog -Level Error -Message "No mapping folder found... creating one."
    }
    $mapping = [RenderKitMapping]::new($Id)

    $mapping | ConvertTo-Json -Depth 5 | 
    Set-Content -Path $mappingPath -Encoding UTF8 

Write-RenderKitLog -Level Info -Message "Mapping '$Id' created successfully"
}