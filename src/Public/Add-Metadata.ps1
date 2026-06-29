Register-RenderKitFunction "Add-Metadata"
function Add-Metadata {
    <#
.SYNOPSIS
Adds a RenderKit metadata value to a media file.

.DESCRIPTION
Writes to the RenderKit metadata store first. If an embedded write capability
exists for the field and media type, the command then attempts to write the
value into the file through the configured adapter.
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]$Path,

        [Parameter(Mandatory, Position = 2)]
        [AllowNull()]
        [object]$Value,

        [string]$ProjectRoot,

        [switch]$Override,

        [switch]$NoEmbedded,

        [switch]$Force
    )

    dynamicparam {
        New-RenderKitMetadataFieldDynamicParameter `
            -Name 'Field' `
            -Position 1 `
            -Mandatory
    }

    process {
        $field = [string]$PSBoundParameters['Field']
        Assert-RenderKitMetadataFieldWrite `
            -Field $field `
            -Value $Value `
            -Force:$Force |
            Out-Null

        $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
        $metadata = [ordered]@{}
        Set-RenderKitMetadataFieldValue `
            -Fields $metadata `
            -Name $field `
            -Value $Value

        if ($metadata.Count -eq 0) {
            throw "Metadata value for '$field' must not be empty."
        }

        if (-not $PSCmdlet.ShouldProcess($resolvedPath, "Add metadata field '$field'")) {
            return
        }

        $storeResult = Set-RenderKitFileMetadataRecordField `
            -Path $resolvedPath `
            -ProjectRoot $ProjectRoot `
            -Metadata $metadata `
            -Override:$Override

        $changedMetadata = [ordered]@{}
        foreach ($change in @($storeResult.Changes)) {
            Set-RenderKitMetadataFieldValue `
                -Fields $changedMetadata `
                -Name ([string]$change.Field) `
                -Value $change.NewValue
        }

        $embeddedResults = @()
        if (-not $NoEmbedded -and $changedMetadata.Count -gt 0) {
            $embeddedResults = @(Invoke-RenderKitEmbeddedMetadataWrite `
                -Path $resolvedPath `
                -Metadata $changedMetadata)
        }

        return [PSCustomObject]@{
            Path = $resolvedPath
            Field = $field
            Value = $metadata[$field]
            ProjectRoot = if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $null } else { [System.IO.Path]::GetFullPath($ProjectRoot) }
            Override = [bool]$Override
            StorePath = [string]$storeResult.RecordPath
            StorageMode = [string]$storeResult.StorageMode
            MetadataVersion = [int]$storeResult.Version
            StoreWritten = [bool]$storeResult.Written
            Changes = @($storeResult.Changes)
            Skipped = @($storeResult.Skipped)
            Embedded = @($embeddedResults)
        }
    }
}
