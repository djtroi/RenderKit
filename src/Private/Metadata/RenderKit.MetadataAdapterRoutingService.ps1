function Get-RenderKitMetadataAdapterRoutingPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Path
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return Join-Path -Path $script:RenderKitModuleRoot `
        -ChildPath 'src/Resources/Metadata/adapters.json'
}

function Test-RenderKitMetadataAdapterRoutingSchema {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object]$Routing
    )

    if ([string]$Routing.artifactType -ne 'MetadataAdapterRouting') {
        return $false
    }
    if ([string]::IsNullOrWhiteSpace([string]$Routing.schemaVersion)) {
        return $false
    }
    if (-not $Routing.adapters -or -not $Routing.routes) {
        return $false
    }
    return $true
}

function Read-RenderKitMetadataAdapterRouting {
    [CmdletBinding()]
    param(
        [string]$Path,
        [switch]$Reload
    )

    $resolvedPath = Get-RenderKitMetadataAdapterRoutingPath -Path $Path
    if (-not $Reload -and
        $script:RenderKitMetadataAdapterRoutingCache -and
        $script:RenderKitMetadataAdapterRoutingCachePath -eq $resolvedPath) {
        return $script:RenderKitMetadataAdapterRoutingCache
    }

    $routing = Read-RenderKitJsonFile `
        -Path $resolvedPath `
        -MaximumBytes 1048576 `
        -Validator { param($value) Test-RenderKitMetadataAdapterRoutingSchema -Routing $value }

    Test-RenderKitArtifactCompatibility `
        -ArtifactType MetadataAdapterRouting `
        -Version ([string]$routing.schemaVersion) |
        Out-Null

    $script:RenderKitMetadataAdapterRoutingCache = $routing
    $script:RenderKitMetadataAdapterRoutingCachePath = $resolvedPath
    return $routing
}

function Get-RenderKitMetadataAdapterDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [object]$Routing
    )

    if (-not $Routing) {
        $Routing = Read-RenderKitMetadataAdapterRouting
    }

    return @(
        $Routing.adapters |
            Where-Object { [string]$_.id -ieq $Id } |
            Select-Object -First 1
    )
}

function Get-RenderKitMetadataCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$CommandName
    )

    foreach ($name in $CommandName) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $command = Get-Command -Name $name -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($command) {
            return $command
        }
    }

    return $null
}

function Get-RenderKitMetadataRouteByExtension {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Extension,

        [object]$Routing
    )

    if (-not $Routing) {
        $Routing = Read-RenderKitMetadataAdapterRouting
    }

    $normalizedExtension = $Extension.ToLowerInvariant()
    return @(
        $Routing.routes |
            Where-Object {
                @($_.extensions | ForEach-Object {
                    ([string]$_).ToLowerInvariant()
                }) -contains $normalizedExtension
            } |
            Select-Object -First 1
    )
}

function Get-RenderKitMetadataRouteByMimeType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MimeType,

        [object]$Routing
    )

    if (-not $Routing) {
        $Routing = Read-RenderKitMetadataAdapterRouting
    }

    $normalizedMimeType = $MimeType.ToLowerInvariant()
    return @(
        $Routing.routes |
            Where-Object {
                @($_.mimeTypes | ForEach-Object {
                    ([string]$_).ToLowerInvariant()
                }) -contains $normalizedMimeType
            } |
            Select-Object -First 1
    )
}

function Get-RenderKitMetadataMimeType {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Extension
    )

    switch ($Extension.ToLowerInvariant()) {
        '.mov' { return 'video/quicktime' }
        '.qt' { return 'video/quicktime' }
        '.mp4' { return 'video/mp4' }
        '.m4v' { return 'video/mp4' }
        '.mkv' { return 'video/x-matroska' }
        '.webm' { return 'video/webm' }
        '.mxf' { return 'application/mxf' }
        '.avi' { return 'video/x-msvideo' }
        '.wmv' { return 'video/x-ms-wmv' }
        '.wav' { return 'audio/wav' }
        '.wave' { return 'audio/wav' }
        '.bwf' { return 'audio/wav' }
        '.rf64' { return 'audio/wav' }
        '.mp3' { return 'audio/mpeg' }
        '.m4a' { return 'audio/mp4' }
        '.aac' { return 'audio/aac' }
        '.aif' { return 'audio/aiff' }
        '.aiff' { return 'audio/aiff' }
        '.flac' { return 'audio/flac' }
        '.ogg' { return 'audio/ogg' }
        '.jpg' { return 'image/jpeg' }
        '.jpeg' { return 'image/jpeg' }
        '.png' { return 'image/png' }
        '.tif' { return 'image/tiff' }
        '.tiff' { return 'image/tiff' }
        '.webp' { return 'image/webp' }
        '.heic' { return 'image/heic' }
        '.heif' { return 'image/heif' }
        '.avif' { return 'image/avif' }
        '.gif' { return 'image/gif' }
        '.bmp' { return 'image/bmp' }
        '.svg' { return 'image/svg+xml' }
        default { return $null }
    }
}

function Resolve-RenderKitMetadataAdapterReader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$AdapterId,

        [object]$Routing
    )

    if (-not $Routing) {
        $Routing = Read-RenderKitMetadataAdapterRouting
    }

    $readerIds = New-Object System.Collections.Generic.List[string]
    foreach ($id in $AdapterId) {
        $adapter = Get-RenderKitMetadataAdapterDefinition -Id $id -Routing $Routing
        if (-not $adapter) { continue }
        $readerId = if (-not [string]::IsNullOrWhiteSpace([string]$adapter.readerAdapter)) {
            [string]$adapter.readerAdapter
        }
        else {
            [string]$adapter.id
        }
        if ($readerIds -notcontains $readerId) {
            $readerIds.Add($readerId)
        }
    }

    return @($readerIds.ToArray())
}

function Resolve-RenderKitMetadataAdapterRoute {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$MimeType,

        [switch]$Reload
    )

    $routing = Read-RenderKitMetadataAdapterRouting -Reload:$Reload
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($MimeType)) {
        $MimeType = Get-RenderKitMetadataMimeType -Extension $extension
    }

    $route = $null
    if (-not [string]::IsNullOrWhiteSpace($MimeType)) {
        $route = Get-RenderKitMetadataRouteByMimeType `
            -MimeType $MimeType `
            -Routing $routing
    }
    if (-not $route -and -not [string]::IsNullOrWhiteSpace($extension)) {
        $route = Get-RenderKitMetadataRouteByExtension `
            -Extension $extension `
            -Routing $routing
    }

    $adapterIds = if ($route) {
        @($route.adapters | ForEach-Object { [string]$_ })
    }
    else {
        @($routing.fallbackAdapters | ForEach-Object { [string]$_ })
    }
    $readerIds = Resolve-RenderKitMetadataAdapterReader `
        -AdapterId $adapterIds `
        -Routing $routing

    $readers = @(
        $readerIds |
            ForEach-Object {
                $definition = Get-RenderKitMetadataAdapterDefinition `
                    -Id $_ `
                    -Routing $routing
                $command = if ($definition) {
                    Get-RenderKitMetadataCommand `
                        -CommandName @($definition.commandNames | ForEach-Object { [string]$_ })
                }
                else {
                    $null
                }
                [PSCustomObject]@{
                    Id = [string]$_
                    Available = [bool]$command
                    CommandPath = if ($command) { [string]$command.Source } else { $null }
                    CommandName = if ($command) { [string]$command.Name } else { $null }
                }
            }
    )

    return [PSCustomObject]@{
        Path = [System.IO.Path]::GetFullPath($Path)
        Extension = $extension
        MimeType = $MimeType
        MediaKind = if ($route) { [string]$route.mediaKind } else { 'Unknown' }
        AdapterIds = @($adapterIds)
        ReaderIds = @($readerIds)
        Readers = @($readers)
        IsSupported = [bool]$route
    }
}
