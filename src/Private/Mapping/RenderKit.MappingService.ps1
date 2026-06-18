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
        Confirm-RenderKitMapping -Mapping $mapping | Out-Null
        return $mapping
    }
    catch {
        Write-RenderKitLog -Level Error -Message (
            "Mapping '$MappingId' could not be read: $($_.Exception.Message)"
        )
        throw
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
    Confirm-RenderKitMapping -Mapping $Mapping -RequireWritable | Out-Null
    $path = Get-RenderKitUserMappingPath -MappingId $MappingId

 Write-RenderKitJsonFileAtomic `
        -Value $Mapping `
        -Path $path `
        -Depth 5 |
        Out-Null
}

function Confirm-RenderKitMapping {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Mapping,
        [switch]$RequireWritable
    )

    foreach ($property in @('Version', 'Id', 'Types')) {
        if (-not ($Mapping.PSObject.Properties.Name -contains $property) -or
            $null -eq $Mapping.$property) {
            throw "Mapping is missing '$property' property."
        }
    }

    $compatibility = Test-RenderKitArtifactCompatibility `
        -ArtifactType Mapping `
        -Version ([string]$Mapping.Version)
    if (-not $compatibility.CanRead -or
        ($RequireWritable -and -not $compatibility.CanWrite)) {
        throw "Mapping version '$($Mapping.Version)' is not supported for this operation (status: $($compatibility.Status))."
    }

    return $compatibility
 }
