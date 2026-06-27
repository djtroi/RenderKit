Register-RenderKitFunction "Update-BackupConfigProfile"
function Update-BackupConfigProfile {
    <#
.SYNOPSIS
Upgrades stored user profiles to the current schema and module defaults.
#>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Name')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Name')]
        [string[]]$Name,
        [Parameter(Mandatory, ParameterSetName = 'All')]
        [switch]$All
    )

    $profiles = if ($All) {
        @(Get-ChildItem `
            -LiteralPath (Get-RenderKitBackupConfigProfilesRoot) `
            -File `
            -Filter '*.rkprofile.json' |
            ForEach-Object {
                Get-BackupUserConfigProfileByName `
                    -Name ($_.Name -replace '\.rkprofile\.json$', '') `
                    -Raw
            })
    }
    else {
        @($Name | ForEach-Object {
            Get-BackupUserConfigProfileByName -Name ([string]$_) -Raw
        })
    }

    foreach ($profile in $profiles) {
        $previousSchema = [string]$profile.schemaVersion
        $previousModule = if ($profile.createdWith) {
            [string]$profile.createdWith.moduleVersion
        }
        else {
            $null
        }
        $updated = Update-BackupConfigProfileToCurrentVersion -Profile $profile
        $path = Get-RenderKitBackupConfigProfilePath -Name ([string]$updated.name)
        if ($PSCmdlet.ShouldProcess($path, "Upgrade backup config profile '$($updated.name)'")) {
            Save-BackupUserConfigProfile -Profile $updated | Out-Null
            [PSCustomObject]@{
                Name                  = [string]$updated.name
                Path                  = $path
                PreviousSchemaVersion = $previousSchema
                SchemaVersion         = [string]$updated.schemaVersion
                PreviousModuleVersion = $previousModule
                ModuleVersion         = [string]$updated.createdWith.moduleVersion
                Generation            = [int]$updated.revision.generation
                Updated               = $true
            }
        }
    }
}
