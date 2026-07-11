Register-RenderKitFunction "Set-MetadataTemplateField"
function Set-MetadataTemplateField {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory, Position = 2)]
        [AllowNull()]
        [object]$Value,

        [switch]$Force
    )

    dynamicparam {
        New-RenderKitMetadataFieldDynamicParameter `
            -Name 'Field' `
            -Position 1 `
            -Mandatory
    }

    process {
        $field = [string]$PSBoundParameters['Field']
        if (-not $PSCmdlet.ShouldProcess($Name, "Set metadata template field '$field'")) {
            return
        }

        $result = Set-RenderKitMetadataTemplateField `
            -Name $Name `
            -Field $field `
            -Value $Value `
            -Force:$Force
        $fields = ConvertTo-RenderKitMetadataDictionary -Value $result.Template.fields
        return [PSCustomObject]@{
            Name = [string]$result.Template.name
            Field = $field
            Value = $fields[$field]
            Generation = [int]$result.Template.revision.generation
            FieldCount = $fields.Count
            Path = [string]$result.Path
        }
    }
}
