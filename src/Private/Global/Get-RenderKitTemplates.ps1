function Get-RenderKitTemplates {
    param(
        [string]$TemplateRoot = (Join-Path $PSScriptRoot "..\Resources\Templates")
    )

    Get-ChildItem $TemplateRoot -Filter "*.json" | Foreach-Object {
        [PSCustomObject]@{
            Name        = $_.BaseName
            Path        = $_.FullName
            IsSystem    = $_.IsSystem
        }
    }
}