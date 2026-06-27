Register-RenderKitFunction "Get-BackupConfigProfile"
function Get-BackupConfigProfile {
    <#
.SYNOPSIS
Lists built-in and user-created backup configuration profiles.

.DESCRIPTION
Returns backup presets and their effective parameter defaults.
Use a returned profile name with `Backup-Project -ConfigProfile`.

.PARAMETER Name
Optional profile name. Aliases such as `proxy` and `archive` are accepted.

.PARAMETER Source
Filters profiles by BuiltIn or User source.

.EXAMPLE
Get-BackupConfigProfile

.EXAMPLE
Get-BackupConfigProfile -Name smallest
#>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,
        [ValidateSet('All', 'BuiltIn', 'User')]
        [string]$Source = 'All'
    )

    process {
        $profiles = if ($Name) {
            @($Name | ForEach-Object {
                Get-BackupConfigProfileDefinition -Name ([string]$_)
            })
        }
        else {
            @(
                @((Get-BackupBuiltInConfigProfileCatalog).Values) +
                @(Get-BackupUserConfigProfileList)
            )
        }

        foreach ($profile in @($profiles | Sort-Object source, name)) {
            if ($Source -ne 'All' -and [string]$profile.source -ne $Source) {
                continue
            }
            [PSCustomObject]@{
                Name               = [string]$profile.name
                DisplayName        = [string]$profile.displayName
                Description        = [string]$profile.description
                Intent             = [string]$profile.intent
                SchemaVersion      = [string]$profile.schemaVersion
                ProfileVersion     = [string]$profile.profileVersion
                Source             = [string]$profile.source
                BaseProfile        = if ($profile.PSObject.Properties.Name -contains 'baseProfile') { [string]$profile.baseProfile } else { $null }
                RequiresBackground = [bool]$profile.requiresBackground
                Path               = if ($profile.PSObject.Properties.Name -contains 'path') { [string]$profile.path } else { $null }
                Tags               = if ($profile.PSObject.Properties.Name -contains 'tags') { @($profile.tags) } else { @() }
                Compatibility      = if ($profile.PSObject.Properties.Name -contains 'compatibility') { $profile.compatibility } else { $null }
                Revision           = if ($profile.PSObject.Properties.Name -contains 'revision') { $profile.revision } else { $null }
                Settings           = Copy-BackupConfigProfileSettings -Settings $profile.settings
            }
        }
    }
}
