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

function Get-RenderKitModuleResourceRoot {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    $candidateBasePaths = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace([string]$script:RenderKitModuleRoot)) {
        $candidateBasePaths.Add([string]$script:RenderKitModuleRoot)
    }

    $fallbackBasePath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    if (-not $candidateBasePaths.Contains($fallbackBasePath)) {
        $candidateBasePaths.Add($fallbackBasePath)
    }

    foreach ($basePath in $candidateBasePaths) {
        $resourceCandidates = @(
            (Join-Path $basePath $RelativePath),
            (Join-Path (Join-Path $basePath "src") $RelativePath)
        )

        foreach ($candidatePath in $resourceCandidates) {
            if (Test-Path -LiteralPath $candidatePath -PathType Container) {
                return $candidatePath
            }
        }
    }

    $primaryBasePath = $candidateBasePaths[0]
    $srcBasePath = Join-Path $primaryBasePath "src"
    if (Test-Path -LiteralPath $srcBasePath -PathType Container) {
        return Join-Path $srcBasePath $RelativePath
    }

    return Join-Path $primaryBasePath $RelativePath
}

function Get-RenderKitSystemTemplatesRoot {
    return Get-RenderKitModuleResourceRoot -RelativePath "Resources/Templates"
}

function Get-RenderKitSystemMappingsRoot {
    return Get-RenderKitModuleResourceRoot -RelativePath "Resources/Mappings"
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

function Get-RenderKitSystemMappingPath {
    param(
        [Parameter(Mandatory)]
        [string]$MappingId
    )

    $file = Resolve-RenderKitMappingFileName -MappingId $MappingId
    return Join-Path (Get-RenderKitSystemMappingsRoot) $file
}
