Register-RenderKitFunction 'Test-RenderKitTemplate'
function Test-RenderKitTemplate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][ValidateSet('System', 'User')][string]$Source)
    Test-RenderKitStoredResource -Kind Template @PSBoundParameters
}
