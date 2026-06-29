Register-RenderKitFunction "Get-MetadataTemplate"
function Get-MetadataTemplate {
    [CmdletBinding()]
    param(
        [string]$Name,

        [switch]$IncludeFields
    )

    $templates = @(Get-RenderKitMetadataTemplate -Name $Name)
    foreach ($context in $templates) {
        $template = $context.Template
        $fields = ConvertTo-RenderKitMetadataDictionary -Value $template.fields
        $result = [ordered]@{
            Name = [string]$template.name
            Description = [string]$template.description
            Generation = [int]$template.revision.generation
            FieldCount = $fields.Count
            UpdatedAtUtc = [string]$template.updatedAtUtc
            Path = [string]$context.Path
        }
        if ($IncludeFields) {
            $result['Fields'] = [PSCustomObject]$fields
        }
        [PSCustomObject]$result
    }
}
