Register-RenderKitFunction 'Get-RenderKitClient'
function Get-RenderKitClient {
    <#
.SYNOPSIS
Lists or resolves clients from the global RenderKit client registry.

.DESCRIPTION
Reads the module-owned client registry under the active RenderKit state root.
No project names or metadata values are promoted into client records.

.PARAMETER Id
Returns the client with this stable identifier.

.PARAMETER Search
Filters identifier, display name, legal name, and tags.

.PARAMETER Status
Filters by the canonical Active, Inactive, or Archived state.

.PARAMETER Tag
Filters by an exact tag.
#>
    [CmdletBinding()]
    param(
        [string]$Id,
        [string]$Search,
        [ValidateSet('Active', 'Inactive', 'Archived')]
        [string]$Status,
        [string]$Tag
    )

    if (-not [string]::IsNullOrWhiteSpace($Id)) {
        return Get-RenderKitClientRecord -Id $Id
    }
    $parameters = @{}
    if (-not [string]::IsNullOrWhiteSpace($Search)) {
        $parameters.Search = $Search
    }
    if (-not [string]::IsNullOrWhiteSpace($Status)) {
        $parameters.Status = $Status
    }
    if (-not [string]::IsNullOrWhiteSpace($Tag)) {
        $parameters.Tag = $Tag
    }
    return @(Get-RenderKitClientRecordList @parameters)
}
