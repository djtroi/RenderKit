Register-RenderKitFunction "Export-BackupConfigProfile"
function Export-BackupConfigProfile {
    <#
.SYNOPSIS
Exports a user backup configuration profile as a portable JSON artifact.
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,
        [Parameter(Mandatory, Position = 1)]
        [string]$Path
    )

    $canonicalName = ConvertTo-BackupConfigProfileName -Name $Name
    $profile = Get-BackupUserConfigProfileByName -Name $canonicalName -Raw
    if (-not $profile) {
        throw "User backup config profile '$canonicalName' was not found."
    }
    $profile = ConvertTo-BackupConfigProfileCurrentSchema -Profile $profile

    $destinationPath = [System.IO.Path]::GetFullPath($Path)
    if (Test-Path -LiteralPath $destinationPath -PathType Container) {
        $destinationPath = Join-Path `
            -Path $destinationPath `
            -ChildPath "$canonicalName.rkprofile.json"
    }
    elseif (-not $destinationPath.EndsWith('.rkprofile.json', [System.StringComparison]::OrdinalIgnoreCase)) {
        $destinationPath = "$destinationPath.rkprofile.json"
    }
    $profile |
        Add-Member `
            -NotePropertyName export `
            -NotePropertyValue ([PSCustomObject]@{
                exportedAtUtc           = (Get-Date).ToUniversalTime().ToString('o')
                exportedByModuleVersion = Get-RenderKitCurrentModuleVersion
            }) `
            -Force

    if ($PSCmdlet.ShouldProcess($destinationPath, "Export backup config profile '$canonicalName'")) {
        Write-RenderKitJsonFileAtomic `
            -Value $profile `
            -Path $destinationPath `
            -Depth 30 `
            -Validator { param($value) Test-BackupConfigProfileDocument -Profile $value } |
            Out-Null
        $item = Get-Item -LiteralPath $destinationPath
        return [PSCustomObject]@{
            Name           = $canonicalName
            Path           = $item.FullName
            SizeBytes      = [int64]$item.Length
            SHA256         = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
            SchemaVersion  = [string]$profile.schemaVersion
            ProfileVersion = [string]$profile.profileVersion
        }
    }
}
