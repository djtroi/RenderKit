function Get-RenderKitRoot {
    $root = Join-Path $ENV:APPDATA "RenderKit"

    if (!(Test-Path $root)) {
        New-Item -ItemType Directory -Path $root | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root "mappings") | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root "templates") | Out-Null
    }

    return $root
}