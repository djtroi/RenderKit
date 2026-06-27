Register-RenderKitFunction "Remove-BackupConfigProfile"
function Remove-BackupConfigProfile {
    <#
.SYNOPSIS
Removes persistent user backup configuration profiles.
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name
    )

    process {
        foreach ($profileName in $Name) {
            $canonicalName = ConvertTo-BackupConfigProfileName -Name $profileName
            if ((Get-BackupBuiltInConfigProfileCatalog).Contains($canonicalName)) {
                throw "Built-in backup config profile '$canonicalName' cannot be removed."
            }
            $path = Get-RenderKitBackupConfigProfilePath -Name $canonicalName
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                throw "User backup config profile '$canonicalName' was not found."
            }
            if ($PSCmdlet.ShouldProcess($path, "Remove backup config profile '$canonicalName'")) {
                Remove-Item -LiteralPath $path -Force -ErrorAction Stop
                [PSCustomObject]@{
                    Name    = $canonicalName
                    Path    = $path
                    Removed = -not (Test-Path -LiteralPath $path)
                }
            }
        }
    }
}
