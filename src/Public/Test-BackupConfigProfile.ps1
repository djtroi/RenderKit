Register-RenderKitFunction "Test-BackupConfigProfile"
function Test-BackupConfigProfile {
    <#
.SYNOPSIS
Validates a built-in, stored, imported, or in-memory backup profile.
#>
    [CmdletBinding(DefaultParameterSetName = 'Name')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Name')]
        [string]$Name,
        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string]$Path,
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'InputObject')]
        [object]$InputObject,
        [Parameter(Mandatory, ParameterSetName = 'Draft')]
        [string]$BaseProfile,
        [Parameter(ParameterSetName = 'Draft')]
        [hashtable]$Settings = @{},
        [Parameter(ParameterSetName = 'Draft')]
        [string]$DraftName = 'studio-draft',
        [switch]$CheckAdapters
    )

    process {
        $profile = $null
        $sourcePath = $null
        $source = 'InputObject'
        switch ($PSCmdlet.ParameterSetName) {
            'Name' {
                $profile = Get-BackupConfigProfileDefinition -Name $Name
                $source = [string]$profile.source
                if ($profile.PSObject.Properties.Name -contains 'path') {
                    $sourcePath = [string]$profile.path
                }
            }
            'Path' {
                $sourcePath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
                $profile = Read-RenderKitJsonFile -Path $sourcePath
                $source = 'File'
            }
            'Draft' {
                $profile = New-BackupUserConfigProfileDocument `
                    -Name $DraftName `
                    -BaseProfile $BaseProfile `
                    -Settings $Settings
                $source = 'Draft'
            }
            default {
                $profile = $InputObject
            }
        }

        if ([string]$profile.source -eq 'BuiltIn') {
            $settingsValidation = Test-BackupConfigProfileSettings `
                -Settings $profile.settings `
                -CheckAdapters:$CheckAdapters
            return [PSCustomObject]@{
                Name              = [string]$profile.name
                Source            = 'BuiltIn'
                Path              = $null
                IsValid           = [bool]$settingsValidation.isValid
                SchemaVersion     = [string]$profile.schemaVersion
                ProfileVersion    = [string]$profile.profileVersion
                Compatibility     = 'Current'
                Errors            = @($settingsValidation.errors)
                Warnings          = @($settingsValidation.warnings)
                EffectiveSettings = $settingsValidation.normalizedSettings
            }
        }

        try {
            $currentProfile = ConvertTo-BackupConfigProfileCurrentSchema -Profile $profile
            $validation = Test-BackupConfigProfileDocumentDetailed `
                -Profile $currentProfile `
                -CheckAdapters:$CheckAdapters
            return [PSCustomObject]@{
                Name              = [string]$currentProfile.name
                Source            = $source
                Path              = $sourcePath
                IsValid           = [bool]$validation.isValid
                SchemaVersion     = [string]$currentProfile.schemaVersion
                ProfileVersion    = [string]$currentProfile.profileVersion
                Compatibility     = if ($validation.compatibility) { [string]$validation.compatibility.Status } else { 'Unknown' }
                Errors            = @($validation.errors)
                Warnings          = @($validation.warnings)
                EffectiveSettings = $validation.normalizedSettings
            }
        }
        catch {
            return [PSCustomObject]@{
                Name              = if ($profile) { [string]$profile.name } else { $null }
                Source            = $source
                Path              = $sourcePath
                IsValid           = $false
                SchemaVersion     = if ($profile) { [string]$profile.schemaVersion } else { $null }
                ProfileVersion    = if ($profile) { [string]$profile.profileVersion } else { $null }
                Compatibility     = 'Invalid'
                Errors            = @($_.Exception.Message)
                Warnings          = @()
                EffectiveSettings = $null
            }
        }
    }
}
