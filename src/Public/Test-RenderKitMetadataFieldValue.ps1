Register-RenderKitFunction "Test-RenderKitMetadataFieldValue"
function Test-RenderKitMetadataFieldValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 1)]
        [AllowNull()]
        [object]$Value,

        [switch]$PassThru
    )

    dynamicparam {
        New-RenderKitMetadataFieldDynamicParameter `
            -Name 'Field' `
            -Position 0 `
            -Mandatory
    }

    process {
        $field = [string]$PSBoundParameters['Field']
        $result = Test-RenderKitMetadataFieldValueCore `
            -Field $field `
            -Value $Value

        if ($PassThru) {
            return $result
        }

        return [bool]$result.IsValid
    }
}
