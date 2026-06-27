Register-RenderKitFunction "Remove-BackupAdapter"
function Remove-BackupAdapter {
    <#
.SYNOPSIS
Removes a registered backup adapter from the current process.
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('AdapterId')]
        [string[]]$Id,
        [switch]$Force
    )

    process {
        foreach ($adapterId in $Id) {
            if ($PSCmdlet.ShouldProcess($adapterId, 'Remove backup adapter registration')) {
                [PSCustomObject]@{
                    Id      = $adapterId
                    Removed = Remove-BackupAdapterDefinition -Id $adapterId -Force:$Force
                }
            }
        }
    }
}
