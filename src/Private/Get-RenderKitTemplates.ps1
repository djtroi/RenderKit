function Get-RenderKitTemplates {
    param(
        [string]$TemplateRoot = (Join-Path $PSScriptRoot "..\Templates")
    )

    Get-ChildItem $TemplateRoot -Filter "*.json" | Foreach-Object {
        [PSCustomObject]@{
            Name = $_.BaseName
            PAth = $_.FullName
        }
    }
}