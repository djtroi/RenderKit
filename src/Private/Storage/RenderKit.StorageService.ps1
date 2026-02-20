function Get-RenderKitRoot {
    $root = Join-Path $env:APPDATA "RenderKit"

    if (!(Test-Path $root)) {
        New-Item -ItemType Directory -Path $root | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root "mappings") | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root "templates") | Out-Null
    }

    return $root
}

function Get-RenderKitUserTemplatesRoot {
    $root = Get-RenderKitRoot
    $path = Join-Path $root "templates"

    if (!(Test-Path $path)) {
        New-Item -ItemType Directory -Path $path | Out-Null
    }

    return $path
}

function Get-RenderKitUserMappingsRoot {
    $root = Get-RenderKitRoot
    $path = Join-Path $root "mappings"

    if (!(Test-Path $path)) {
        New-Item -ItemType Directory -Path $path | Out-Null
    }

    return $path
}

function Get-RenderKitSystemTemplatesRoot {
    if (-not $script:RenderKitModuleRoot) {
        $script:RenderKitModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    }

    return Join-Path $script:RenderKitModuleRoot "Resources/Templates"
}

function Resolve-RenderKitTemplateFileName {
    param(
        [Parameter(Mandatory)]
        [string]$TemplateName
    )

    $file = [IO.Path]::GetFileName($TemplateName)
    if ([string]::IsNullOrWhiteSpace($file)) {
        return $null
    }

    if ([IO.Path]::GetExtension($file) -ne ".json") {
        $file = "$file.json"
    }

    return $file
}

function Resolve-RenderKitMappingFileName {
    param(
        [Parameter(Mandatory)]
        [string]$MappingId
    )

    $file = [IO.Path]::GetFileName($MappingId)
    if ([string]::IsNullOrWhiteSpace($file)) {
        return $null
    }

    if ([IO.Path]::GetExtension($file) -ne ".json") {
        $file = "$file.json"
    }

    return $file
}

function Get-RenderKitUserTemplatePath {
    param(
        [Parameter(Mandatory)]
        [string]$TemplateName
    )

    $file = Resolve-RenderKitTemplateFileName -TemplateName $TemplateName
    return Join-Path (Get-RenderKitUserTemplatesRoot) $file
}

function Get-RenderKitUserMappingPath {
    param(
        [Parameter(Mandatory)]
        [string]$MappingId
    )

    $file = Resolve-RenderKitMappingFileName -MappingId $MappingId
    return Join-Path (Get-RenderKitUserMappingsRoot) $file
}
