function Read-RenderKitMappingFile {
    param(
        [Parameter(Mandatory)]
        [string]$MappingId
    )

    $path = Get-RenderKitUserMappingPath -MappingId $MappingId
    if (!(Test-Path $path)) {
        return $null
    }

    try {
        return Get-Content $path -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Invalid JSON in mapping '$MappingId'"
    }
}

function Write-RenderKitMappingFile {
    param(
        [Parameter(Mandatory)]
        [object]$Mapping,
        [Parameter(Mandatory)]
        [string]$MappingId
    )

    $path = Get-RenderKitUserMappingPath -MappingId $MappingId

    $Mapping | ConvertTo-Json -Depth 5 |
        Set-Content -Path $path -Encoding UTF8
}
