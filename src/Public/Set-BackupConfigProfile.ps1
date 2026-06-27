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
        [ValidateRange(1, [int]::MaxValue)]
        [int]$ExpectedGeneration,
        [ValidateSet('None', 'Patch', 'Minor', 'Major')]
        [string]$BumpVersion = 'Patch',
        [switch]$Interactive
    )

    $canonicalName = ConvertTo-BackupConfigProfileName -Name $Name
    $profile = Get-BackupUserConfigProfileByName -Name $canonicalName
    if ($PSBoundParameters.ContainsKey('ExpectedGeneration') -and
        [int]$profile.revision.generation -ne $ExpectedGeneration) {
        $message = (
            "Backup config profile '$canonicalName' changed after it was loaded. " +
            "Expected generation $ExpectedGeneration but found $($profile.revision.generation)."
        )
        $exception = [System.InvalidOperationException]::new($message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'RK_PROFILE_CONFLICT',
            [System.Management.Automation.ErrorCategory]::ResourceExists,
            $canonicalName
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
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
