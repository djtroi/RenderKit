Register-RenderKitFunction "Rollback-Metadata"
function Rollback-Metadata {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'File')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'File')]
        [Alias('FullName')]
        [string]$Path,

        [Parameter(ParameterSetName = 'File')]
        [Parameter(Mandatory, ParameterSetName = 'Batch')]
        [string]$ProjectRoot,

        [Parameter(Mandatory, ParameterSetName = 'Batch')]
        [string]$BatchId,

        [Parameter(ParameterSetName = 'File')]
        [ValidateRange(1, 2147483647)]
        [int]$Version
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Batch') {
            $resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot -ErrorAction Stop).ProviderPath
            if (-not $PSCmdlet.ShouldProcess($resolvedProjectRoot, "Rollback metadata batch '$BatchId'")) {
                return
            }
            return Invoke-RenderKitMetadataBatchRollback `
                -ProjectRoot $resolvedProjectRoot `
                -BatchId $BatchId
        }

        $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
        $target = if ($Version -gt 0) { "version $Version" } else { 'previous version' }
        if (-not $PSCmdlet.ShouldProcess($resolvedPath, "Rollback metadata to $target")) {
            return
        }

        $result = Restore-RenderKitFileMetadataRecordVersion `
            -Path $resolvedPath `
            -ProjectRoot $ProjectRoot `
            -Version $Version

        return [PSCustomObject]@{
            Path = $resolvedPath
            ProjectRoot = if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $null } else { [System.IO.Path]::GetFullPath($ProjectRoot) }
            StorePath = [string]$result.RecordPath
            StorageMode = [string]$result.StorageMode
            MetadataVersion = [int]$result.Version
            RolledBack = [bool]$result.RolledBack
            RestoredFromVersion = [int]$result.RestoredFromVersion
        }
    }
}
