function Get-RenderKitTemplates {
    param(
        [string]$TemplateRoot = (Join-Path $PSScriptRoot "..\Resources\Templates\")
    )
    Write-RenderKitLog -Level Debug "Reading templates from $TemplateRoot "
    Get-ChildItem $TemplateRoot -Filter "*.json" | Foreach-Object {
        [PSCustomObject]@{
            Name        = $_.BaseName
            Path        = $_.FullName
            IsSystem    = $_.IsSystem
        }
    }
}