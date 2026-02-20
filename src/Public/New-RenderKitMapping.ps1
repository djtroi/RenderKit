function New-RenderKitMapping {
    param(
        [Parameter(Mandatory)]
        [string]$Id 
    )
    $mappingPath = Get-RenderKitUserMappingPath -MappingId $Id
    $mappingFolder = Get-RenderKitUserMappingsRoot

    if (Test-Path $mappingPath) {
        Write-RenderKitLog -Level Error -Message "Mapping '$Id' already exists."
    }
    if (!(Test-Path $mappingFolder)){
        New-Item -ItemType Directory -Path $mappingFolder -ErrorAction Stop | Out-Null
        Write-RenderKitLog -Level Error -Message "No mapping folder found... creating one."
    }
    $mapping = [RenderKitMapping]::new($Id)

    Write-RenderKitMappingFile -Mapping $mapping -MappingId $Id 

Write-RenderKitLog -Level Info -Message "Mapping '$Id' created successfully"
}
