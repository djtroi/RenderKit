function Add-RenderKitTypeToMapping {
    param(
        [string]$MappingId,
        [string]$TypeName,
        [string[]]$Extensions
    )

    $root = Get-RenderKitRoot
    $mappingPath = Join-Path $root "mappings\$MappingId.json"

    if (!(Test-Path $mappingPath)) {
        New-RenderKitLog -Level Error -Message "Mapping $MappingId not found.0"
    }

    $json = Get-Content $mappingPath | ConvertFrom-Json 

    $json.Types += @{
        Name        =   $TypeName
        Extensions  =   $Extensions
    }

    $json | ConvertTo-Json -Depth 5 | 
    Set-Content $mappingPath -Encoding UTF8 .\.vscode
    
    Write-RenderKitLog -Level Info -Message "$TypeName added."
}