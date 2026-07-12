Register-RenderKitFunction 'Test-RenderKitMapping'
function Test-RenderKitMapping {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][ValidateSet('System', 'User')][string]$Source)
    Test-RenderKitStoredResource -Kind Mapping @PSBoundParameters
}
