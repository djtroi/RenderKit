function Get-RenderKitEmbeddedMetadataWriteMapPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Path
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return Join-Path -Path $script:RenderKitModuleRoot `
        -ChildPath 'src/Resources/Metadata/embedded-write-map.json'
}

function Test-RenderKitEmbeddedMetadataWriteMapSchema {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object]$Map
    )

    if ([string]$Map.artifactType -ne 'MetadataEmbeddedWriteMap') {
        return $false
    }
    if ([string]::IsNullOrWhiteSpace([string]$Map.schemaVersion)) {
        return $false
    }
    if (-not $Map.fields) {
        return $false
    }
    return $true
}

function Read-RenderKitEmbeddedMetadataWriteMap {
    [CmdletBinding()]
    param(
        [string]$Path,
        [switch]$Reload
    )

    $resolvedPath = Get-RenderKitEmbeddedMetadataWriteMapPath -Path $Path
    if (-not $Reload -and
        $script:RenderKitEmbeddedMetadataWriteMapCache -and
        $script:RenderKitEmbeddedMetadataWriteMapCachePath -eq $resolvedPath) {
        return $script:RenderKitEmbeddedMetadataWriteMapCache
    }

    $map = Read-RenderKitJsonFile `
        -Path $resolvedPath `
        -MaximumBytes 1048576 `
        -Validator { param($value) Test-RenderKitEmbeddedMetadataWriteMapSchema -Map $value }

    Test-RenderKitArtifactCompatibility `
        -ArtifactType MetadataEmbeddedWriteMap `
        -Version ([string]$map.schemaVersion) |
        Out-Null

    $script:RenderKitEmbeddedMetadataWriteMapCache = $map
    $script:RenderKitEmbeddedMetadataWriteMapCachePath = $resolvedPath
    return $map
}

function Get-RenderKitEmbeddedMetadataWriteCapability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Field,

        [string]$MediaKind,

        [object]$Map
    )

    if (-not $Map) {
        $Map = Read-RenderKitEmbeddedMetadataWriteMap
    }

    $capability = @(
        $Map.fields |
            Where-Object { [string]$_.field -ieq $Field } |
            Select-Object -First 1
    )
    if (-not $capability) {
        return $null
    }

    $mediaKinds = @($capability.mediaKinds | ForEach-Object { [string]$_ })
    if ($mediaKinds.Count -gt 0 -and
        $mediaKinds -notcontains 'All' -and
        -not [string]::IsNullOrWhiteSpace($MediaKind) -and
        $mediaKinds -notcontains $MediaKind) {
        return $null
    }

    return $capability
}

function ConvertTo-RenderKitExifToolValue {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($Value -is [datetime]) {
        return $Value.ToString('yyyy:MM:dd HH:mm:ss')
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        return (@($Value | ForEach-Object { [string]$_ }) -join ', ')
    }
    return [string]$Value
}

function Invoke-RenderKitEmbeddedMetadataWrite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Metadata
    )

    $route = Resolve-RenderKitMetadataAdapterRoute -Path $Path
    $routing = Read-RenderKitMetadataAdapterRouting
    $exifToolDefinition = Get-RenderKitMetadataAdapterDefinition `
        -Id 'ExifTool' `
        -Routing $routing
    $exifToolCommand = if ($exifToolDefinition) {
        Get-RenderKitMetadataCommand `
            -CommandName @($exifToolDefinition.commandNames | ForEach-Object { [string]$_ })
    }
    else {
        $null
    }
    $map = Read-RenderKitEmbeddedMetadataWriteMap
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($key in @($Metadata.Keys | Sort-Object)) {
        $field = [string]$key
        $value = $Metadata[$key]
        $capability = Get-RenderKitEmbeddedMetadataWriteCapability `
            -Field $field `
            -MediaKind ([string]$route.MediaKind) `
            -Map $map
        if (-not $capability) {
            $results.Add([PSCustomObject]@{
                Field = $field
                Embedded = $false
                Status = 'Skipped'
                Reason = 'NoEmbeddedWriteCapability'
                Adapter = $null
                Tags = @()
            })
            continue
        }
        if (-not $exifToolCommand) {
            $results.Add([PSCustomObject]@{
                Field = $field
                Embedded = $false
                Status = 'Skipped'
                Reason = 'ExifToolNotAvailable'
                Adapter = 'ExifTool'
                Tags = @($capability.tags)
            })
            continue
        }

        $arguments = New-Object System.Collections.Generic.List[string]
        $arguments.Add('-overwrite_original')
        $arguments.Add('-P')
        foreach ($tag in @($capability.tags | ForEach-Object { [string]$_ })) {
            $arguments.Add('-{0}={1}' -f $tag, (ConvertTo-RenderKitExifToolValue -Value $value))
        }
        $arguments.Add($Path)

        try {
            $output = & ([string]$exifToolCommand.Source) @arguments 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "ExifTool failed with exit code $LASTEXITCODE`: $($output -join "`n")"
            }
            $results.Add([PSCustomObject]@{
                Field = $field
                Embedded = $true
                Status = 'Written'
                Reason = $null
                Adapter = 'ExifTool'
                Tags = @($capability.tags)
            })
        }
        catch {
            $results.Add([PSCustomObject]@{
                Field = $field
                Embedded = $false
                Status = 'Failed'
                Reason = $_.Exception.Message
                Adapter = 'ExifTool'
                Tags = @($capability.tags)
            })
        }
    }

    return @($results.ToArray())
}
