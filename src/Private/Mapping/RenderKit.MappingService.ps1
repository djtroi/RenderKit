function Read-RenderKitMappingFile {
    param(
        [Parameter(Mandatory)]
        [string]$MappingId
    )

    $path = Resolve-RenderKitMappingPath -MappingId $MappingId
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

function Resolve-RenderKitMappingPath {
    param(
        [Parameter(Mandatory)]
        [string]$MappingId
    )

    $userPath = Get-RenderKitUserMappingPath -MappingId $MappingId
    if (Test-Path $userPath) {
        return $userPath
    }

    return Get-RenderKitSystemMappingPath -MappingId $MappingId
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
