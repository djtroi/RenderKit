Register-RenderKitFunction 'Import-RenderKitMapping'
function Import-RenderKitMapping {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Parameter(Mandatory)][string]$Path, [ValidateSet('Error', 'Overwrite', 'Rename')][string]$ConflictAction = 'Error')
    Import-RenderKitResourceDocument -Kind Mapping @PSBoundParameters
}
