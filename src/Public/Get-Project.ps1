Register-RenderKitFunction "Get-Project"
function Get-Project {
    <#
.SYNOPSIS
Lists projects known to the RenderKit project registry.

.DESCRIPTION
Reads the system-wide RenderKit project registry and returns one object per
known project. The output is intentionally shaped for PowerShell table output
and includes identity, availability, version, path, metadata path, and the last
registry update timestamp.

By default, Get-Project returns every registered project, including projects
that are currently unavailable because a drive or network share is offline. Use
-AvailableOnly to show only projects whose root path currently exists.

.PARAMETER AvailableOnly
Only returns projects whose registered root path currently exists.

.PARAMETER Refresh
Rechecks registered project paths before returning the list and persists the
updated availability markers in the registry.

.EXAMPLE
Get-Project
Lists all projects currently known to RenderKit.

.EXAMPLE
Get-Project -AvailableOnly | Format-Table
Lists only currently available projects in table form.

.EXAMPLE
Get-Project -Refresh
Refreshes path availability in the registry before listing known projects.

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
        $registry = Repair-RenderKitProjectRegistry
    }
    else {
        $registry = Read-RenderKitProjectRegistry
    }

    $projects = @($registry.projects)
    if ($AvailableOnly) {
        $projects = @($projects | Where-Object {
            [bool]$_.exists -and
            (Test-Path -LiteralPath ([string]$_.rootPath) -PathType Container)
        })
    }

    foreach ($project in ($projects | Sort-Object -Property name, rootPath)) {
        [PSCustomObject]@{
            Name         = [string]$project.name
            Id           = [string]$project.id
            Available    = [bool]$project.exists
            Version      = [string]$project.version
            RootPath     = [string]$project.rootPath
            MetadataPath = [string]$project.metadataPath
            UpdatedAtUtc = [string]$project.updatedAtUtc
        }
    }
}