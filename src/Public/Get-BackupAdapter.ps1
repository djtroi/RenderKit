Register-RenderKitFunction "Get-BackupAdapter"
function Get-BackupAdapter {
    <#
.SYNOPSIS
Lists registered backup pipeline adapters.

.PARAMETER Id
Optional adapter id, such as storage.filesystem or encoder.ffmpeg.

.PARAMETER Type
Optional adapter type filter.
#>
    [CmdletBinding()]
    param(
        [string[]]$Id,
        [ValidateSet('Storage', 'Encoder', 'Verifier', 'Notifier')]
        [string]$Type
    )

    $adapters = @((Get-BackupAdapterRegistry).Values)
    if ($Id) {
        $requestedIds = @($Id | ForEach-Object { $_.Trim().ToLowerInvariant() })
        $adapters = @($adapters | Where-Object { $requestedIds -contains [string]$_.id })
    }
    if ($Type) {
        $adapters = @($adapters | Where-Object { [string]$_.type -eq $Type })
    }

    foreach ($adapter in @($adapters | Sort-Object Type, Id)) {
        ConvertTo-BackupAdapterPublicView -Adapter $adapter
    }
}
