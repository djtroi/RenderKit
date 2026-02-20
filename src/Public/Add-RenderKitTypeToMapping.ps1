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

    if (-not ($json.PSObject.Properties.Name -contains "Types")) {
        $json | Add-Member -MemberType NoteProperty -Name Types -Value ([System.Collections.ArrayList]::new()) -Force
    }
    elseif ($json.Types -isnot [System.Collections.ArrayList]) {
        $json.Types = [System.Collections.ArrayList]@($json.Types)
    }

    $null = $json.Types.Add(@{
        Name        =   $TypeName
        Extensions  =   $Extensions
    })

    Write-RenderKitMappingFile -Mapping $json -MappingId $MappingId
    
    Write-RenderKitLog -Level Info -Message "Type ""$TypeName"" added to $MappingId."
}
