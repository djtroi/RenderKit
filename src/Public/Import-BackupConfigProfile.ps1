Register-RenderKitFunction "Import-BackupConfigProfile"
function Import-BackupConfigProfile {
    <#
.SYNOPSIS
Imports and, when necessary, upgrades a portable backup profile.
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,
        [string]$Name,
        [ValidateSet('Error', 'Overwrite', 'Rename')]
        [string]$ConflictAction = 'Error'
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    $imported = Read-RenderKitJsonFile -Path $resolvedPath
    $previousSchemaVersion = if ($imported.PSObject.Properties.Name -contains 'schemaVersion') {
        [string]$imported.schemaVersion
    }
    else {
        '1.0'
    }
    $imported = ConvertTo-BackupConfigProfileCurrentSchema -Profile $imported
    if ($PSBoundParameters.ContainsKey('Name')) {
        $imported.name = ConvertTo-BackupConfigProfileName -Name $Name
        $imported.displayName = $Name
    }
    $targetName = ConvertTo-BackupConfigProfileName -Name ([string]$imported.name)
    if ((Get-BackupBuiltInConfigProfileCatalog).Contains($targetName)) {
        throw "Imported profile name '$targetName' conflicts with a built-in profile."
    }

    $existing = Get-BackupUserConfigProfileByName -Name $targetName -AllowMissing -Raw
    if ($existing -and $ConflictAction -eq 'Error') {
        throw "Backup config profile '$targetName' already exists."
    }
    if ($existing -and $ConflictAction -eq 'Rename') {
        $baseName = $targetName
        $suffix = 2
        do {
            $targetName = "$baseName-$suffix"
            $suffix++
        } while (Get-BackupUserConfigProfileByName -Name $targetName -AllowMissing -Raw)
        $imported.name = $targetName
        $imported.displayName = "$($imported.displayName) ($($suffix - 1))"
    }
    $imported.source = 'User'
    $imported.revision.updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')

    $targetPath = Get-RenderKitBackupConfigProfilePath -Name $targetName
    if ($PSCmdlet.ShouldProcess($targetPath, "Import backup config profile from '$resolvedPath'")) {
        Save-BackupUserConfigProfile -Profile $imported | Out-Null
        return [PSCustomObject]@{
            Name                  = $targetName
            Path                  = $targetPath
            SourcePath            = $resolvedPath
            ConflictAction        = $ConflictAction
            PreviousSchemaVersion = $previousSchemaVersion
            SchemaVersion         = [string]$imported.schemaVersion
            WasUpgraded           = [version]$previousSchemaVersion -lt [version]$imported.schemaVersion
            Profile               = Get-BackupConfigProfile -Name $targetName
        }
    }
}
