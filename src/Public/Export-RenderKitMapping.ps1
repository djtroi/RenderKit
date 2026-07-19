Register-RenderKitFunction 'Export-RenderKitMapping'
function Export-RenderKitMapping {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][ValidateSet('System', 'User')][string]$Source, [Parameter(Mandatory)][string]$Path)
    Export-RenderKitResourceDocument -Kind Mapping @PSBoundParameters
}
