function Get-RenderKitTemplates {

    $systemRoot = Join-Path (Convert-Path "$PSScriptRoot/../../") "Resources/Templates"
    $userRoot   = Join-Path $env:APPDATA "RenderKit/Templates"

    $templates = @()

    if (Test-Path $systemRoot) {
        $templates += Get-ChildItem $systemRoot -Filter "*.json" | ForEach-Object {
            [PSCustomObject]@{
                Name   = $_.BaseName
                Path   = $_.FullName
                Source = "system"
            }
        }
    }

    if (Test-Path $userRoot) {
        $templates += Get-ChildItem $userRoot -Filter "*.json" | ForEach-Object {
            [PSCustomObject]@{
                Name   = $_.BaseName
                Path   = $_.FullName
                Source = "user"
            }
        }
    }

    return $templates
}