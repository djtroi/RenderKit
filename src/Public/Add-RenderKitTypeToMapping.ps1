function Add-RenderKitTypeToMapping {
    param(
        [string]$MappingId,
        [string]$TypeName,
        [string[]]$Extensions # TODO: Validate and structure extensions
    )

    $root = Get-RenderKitRoot
    $mappingPath = Join-Path $root "mappings\$MappingId.json"

    if (!(Test-Path $mappingPath)) {
        Write-RenderKitLog -Level Error -Message "Mapping $MappingId not found"
    }

    $json = Get-Content $mappingPath | ConvertFrom-Json 

    $json.Types += @{
        Name        =   $TypeName
        Extensions  =   $Extensions
    }

    $json | ConvertTo-Json -Depth 5 | 
    Set-Content $mappingPath -Encoding UTF8
    
    Write-RenderKitLog -Level Info -Message "Type ""$TypeName"" added to $MappingId."
}