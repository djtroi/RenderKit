function Resolve-RenderKitMappingFileName {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [string]$MappingId
    )

    $normalizedName = [System.IO.Path]::GetFileNameWithoutExtension(
        $MappingId.Trim())
    if ([string]::IsNullOrWhiteSpace($normalizedName)) {
        return $null
    }

    return "$normalizedName.json"
}
