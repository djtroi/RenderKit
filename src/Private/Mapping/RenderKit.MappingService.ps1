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
        return Read-RenderKitJsonFile -Path $path
    }
    catch {
        Write-RenderKitLog -Level Error -Message "Invalid JSON in mapping '$MappingId'."
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

    Write-RenderKitJsonFileAtomic `
        -Value $Mapping `
        -Path $path `
        -Depth 5 |
        Out-Null
}
