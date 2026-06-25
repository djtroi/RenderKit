Register-RenderKitFunction "Get-Project"
function Get-Project {
    <#
.SYNOPSIS
Lists projects from the RenderKit discovered project overview.

.DESCRIPTION
Reads the persisted RenderKit discovered project overview and returns one object
per known discovered project. The default command is intentionally cheap: it
only reads the JSON overview and does not scan the file system.

Use -Refresh to trigger the internal project discovery service before reading
the overview. Discovery uses the internal search index and remains an internal
engine function rather than a separate public command.

.PARAMETER AvailableOnly
Only returns projects whose last discovered availability marker is true.

.PARAMETER Refresh
Runs internal project discovery from the project search index before reading the
discovered project overview.

.EXAMPLE
Get-Project
Lists all projects currently present in the discovered project overview.

.EXAMPLE
Get-Project -AvailableOnly | Format-Table
Lists only projects marked available in the discovered project overview.

.EXAMPLE
Get-Project -Refresh
Refreshes the discovered project overview through internal discovery before
listing projects.

.INPUTS
None. You cannot pipe input to this command.

.OUTPUTS
System.Management.Automation.PSCustomObject. Returns project summary objects.

.LINK
New-Project

.LINK
Rename-Project

.LINK
Remove-Project
#>
    [CmdletBinding()]
    param(
        [switch]$AvailableOnly,
        [switch]$Refresh
    )

    Write-RenderKitLog -Level Debug -Message "Get-Project started: AvailableOnly='$AvailableOnly', Refresh='$Refresh'."

    if ($Refresh) {
        Invoke-RenderKitProjectDiscovery | Out-Null
    }

    $store = Read-RenderKitDiscoveredProjectStore
    $projects = @($store.projects)
    if ($AvailableOnly) {
        $projects = @($projects | Where-Object { [bool]$_.available })
    }

    foreach ($project in ($projects | Sort-Object -Property name, rootPath)) {
        [PSCustomObject]@{
            Name                          = [string]$project.name
            Id                            = [string]$project.id
            Available                     = [bool]$project.available
            Version                       = [string]$project.version
            RootPath                      = [string]$project.rootPath
            MetadataPath                  = [string]$project.metadataPath
            Location                      = [string]$project.locationType
            IsInsideConfiguredProjectRoot = [bool]$project.isInsideConfiguredProjectRoot
            ValidationStatus              = [string]$project.validationStatus
            ConflictStatus                = [string]$project.conflictStatus
            UpdatedAtUtc                  = [string]$project.updatedAtUtc
        }
    }
}