Register-RenderKitFunction "Set-BackupConfigProfile"
function Set-BackupConfigProfile {
    <#
.SYNOPSIS
Updates a persistent user backup configuration profile.
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,
        [string]$BaseProfile,
        [hashtable]$Settings = @{},
        [string]$DisplayName,
        [string]$Description,
        [string[]]$Tag,
        [string]$Author,
        [ValidateSet('None', 'Patch', 'Minor', 'Major')]
        [string]$BumpVersion = 'Patch',
        [switch]$Interactive
    )

    $canonicalName = ConvertTo-BackupConfigProfileName -Name $Name
    $profile = Get-BackupUserConfigProfileByName -Name $canonicalName
    $baseSettings = $profile.settings
    if ($PSBoundParameters.ContainsKey('BaseProfile')) {
        $baseDefinition = Get-BackupConfigProfileDefinition -Name $BaseProfile
        $profile.baseProfile = [string]$baseDefinition.name
        $baseSettings = $baseDefinition.settings
    }
    $merged = Merge-BackupConfigProfileSettings `
        -BaseSettings $baseSettings `
        -Overrides $Settings
    if ($Interactive) {
        $merged = Read-BackupConfigProfileInteractiveSettings -BaseSettings $merged
    }
    $profile.settings = $merged
    if ($PSBoundParameters.ContainsKey('DisplayName')) {
        $profile.displayName = $DisplayName
    }
    if ($PSBoundParameters.ContainsKey('Description')) {
        $profile.description = $Description
    }
    if ($PSBoundParameters.ContainsKey('Tag')) {
        $profile.tags = @($Tag | Sort-Object -Unique)
    }
    if ($PSBoundParameters.ContainsKey('Author')) {
        $profile.author = $Author
    }
    $profile.profileVersion = Get-NextBackupConfigProfileVersion `
        -Version ([string]$profile.profileVersion) `
        -Bump $BumpVersion
    $profile.revision.generation = [int]$profile.revision.generation + 1
    $profile.revision.updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')

    if ($PSCmdlet.ShouldProcess(
            [string]$profile.path,
            "Update backup config profile '$canonicalName'")) {
        Save-BackupUserConfigProfile -Profile $profile | Out-Null
        return Get-BackupConfigProfile -Name $canonicalName
    }
}
