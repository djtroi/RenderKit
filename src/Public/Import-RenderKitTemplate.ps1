Register-RenderKitFunction 'Import-RenderKitTemplate'
function Import-RenderKitTemplate {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Parameter(Mandatory)][string]$Path, [ValidateSet('Error', 'Overwrite', 'Rename')][string]$ConflictAction = 'Error')
    Import-RenderKitResourceDocument -Kind Template @PSBoundParameters
}
