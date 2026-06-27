Register-RenderKitFunction "New-BackupConfigProfile"
function New-BackupConfigProfile {
    <#
.SYNOPSIS
Creates a persistent user backup configuration profile.

.EXAMPLE
New-BackupConfigProfile -Name client-archive -BaseProfile archive-safe

.EXAMPLE
New-BackupConfigProfile -Name compact -BaseProfile smallest -Settings @{ MaxCpuPercent = 70 }

.EXAMPLE
New-BackupConfigProfile -Interactive
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)]
        [string]$Name,
        [string]$DisplayName,
        [string]$Description,
        [string]$BaseProfile = 'balanced',
        [string]$ProfileVersion = '1.0.0',
        [hashtable]$Settings = @{},
        [string[]]$Tag = @(),
        [string]$Author,
        [switch]$Interactive,
        [switch]$Force
    )

    if ($Interactive -and [string]::IsNullOrWhiteSpace($Name)) {
        $Name = Read-Host 'Profile name'
    }
    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw 'Profile name is required. Supply -Name or use -Interactive.'
    }

    $canonicalName = ConvertTo-BackupConfigProfileName -Name $Name
    $existing = Get-BackupUserConfigProfileByName `
        -Name $canonicalName `
        -AllowMissing `
        -Raw
    if ($existing -and -not $Force) {
        throw "Backup config profile '$canonicalName' already exists. Use -Force to replace it."
    }

    $baseDefinition = Get-BackupConfigProfileDefinition -Name $BaseProfile
    $effectiveOverrides = $Settings
    if ($Interactive) {
        $interactiveBase = Merge-BackupConfigProfileSettings `
            -BaseSettings $baseDefinition.settings `
            -Overrides $Settings
        $effectiveOverrides = ConvertTo-BackupConfigProfileSettingsDictionary `
            -Settings (Read-BackupConfigProfileInteractiveSettings -BaseSettings $interactiveBase)
    }
    $document = New-BackupUserConfigProfileDocument `
        -Name $canonicalName `
        -DisplayName $DisplayName `
        -Description $Description `
        -BaseProfile ([string]$baseDefinition.name) `
        -ProfileVersion $ProfileVersion `
        -Settings $effectiveOverrides `
        -Tags $Tag `
        -Author $Author

    if ($PSCmdlet.ShouldProcess(
            (Get-RenderKitBackupConfigProfilePath -Name $canonicalName),
            "Create backup config profile '$canonicalName'")) {
        Save-BackupUserConfigProfile -Profile $document | Out-Null
        return Get-BackupConfigProfile -Name $canonicalName
    }
}
