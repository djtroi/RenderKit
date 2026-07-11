Register-RenderKitFunction "Update-MetadataCache"
function Update-MetadataCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [ValidateRange(1, 64)]
        [int]$ThrottleLimit = 4,

        [switch]$IncludeUnsupported
    )

    return Update-RenderKitProjectMetadataCache `
        -ProjectRoot $ProjectRoot `
        -ThrottleLimit $ThrottleLimit `
        -IncludeUnsupported:$IncludeUnsupported
}
