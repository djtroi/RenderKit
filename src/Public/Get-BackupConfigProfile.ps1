Register-RenderKitFunction "Get-BackupConfigProfile"
function Get-BackupConfigProfile {
    <#
.SYNOPSIS
Lists built-in backup configuration profiles.

.DESCRIPTION
Returns the built-in backup presets and their effective parameter defaults.
Use a returned profile name with `Backup-Project -ConfigProfile`.

.PARAMETER Name
Optional profile name. Aliases such as `proxy` and `archive` are accepted.

.EXAMPLE
Get-BackupConfigProfile

.EXAMPLE
Get-BackupConfigProfile -Name smallest
#>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name
    )

    process {
        $requestedNames = if ($Name) {
            @($Name)
        }
        else {
            @((Get-BackupBuiltInConfigProfileCatalog).Keys)
        }

        foreach ($requestedName in $requestedNames) {
            $profile = Get-BackupConfigProfileDefinition -Name ([string]$requestedName)
            [PSCustomObject]@{
                Name               = [string]$profile.name
                DisplayName        = [string]$profile.displayName
                Description        = [string]$profile.description
                Intent             = [string]$profile.intent
                SchemaVersion      = [string]$profile.schemaVersion
                ProfileVersion     = [string]$profile.profileVersion
                Source             = [string]$profile.source
                RequiresBackground = [bool]$profile.requiresBackground
                Settings           = Copy-BackupConfigProfileSettings -Settings $profile.settings
            }
        }
    }
}
