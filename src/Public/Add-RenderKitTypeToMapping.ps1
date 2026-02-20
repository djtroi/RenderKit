function Add-RenderKitTypeToMapping {
    param(
        [string]$MappingId,
        [string]$TypeName,
        [string[]]$Extensions # TODO: Validate and structure extensions
    )

    $mappingPath = Get-RenderKitUserMappingPath -MappingId $MappingId
    if (!(Test-Path $mappingPath)) {
        Write-RenderKitLog -Level Error -Message "Mapping $MappingId not found"
    }

    $json = Read-RenderKitMappingFile -MappingId $MappingId

    $json.Types += @{
        Name        =   $TypeName
        Extensions  =   $Extensions
    }

    Write-RenderKitMappingFile -Mapping $json -MappingId $MappingId
    
    Write-RenderKitLog -Level Info -Message "Type ""$TypeName"" added to $MappingId."
}
