Register-RenderKitFunction "Export-Project"
function Export-Project {
    <#
.SYNOPSIS
Exports a RenderKit project manifest or self-contained project package.
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$DestinationPath,
        [ValidateSet('ManifestOnly', 'SelfContained')][string]$Mode = 'ManifestOnly',
        [ValidateSet('Zip')][string]$CompressionMethod = 'Zip',
        [ValidateSet('NoCompression', 'Fastest', 'Optimal')][string]$CompressionLevel = 'Optimal',
        [ValidateSet('SHA256', 'MD5')][string[]]$HashAlgorithm = @('SHA256'),
        [switch]$IncludeMd5,
        [switch]$IncludeAbsolutePaths,
        [bool]$IncludeMetadata = $true
    )

    if ($IncludeMd5 -and $HashAlgorithm -notcontains 'MD5') {
        $HashAlgorithm = @($HashAlgorithm + 'MD5')
    }

    $resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot -ErrorAction Stop).ProviderPath
    if (-not (Test-Path -LiteralPath $resolvedProjectRoot -PathType Container)) {
        throw "Project root '$ProjectRoot' is not a directory."
    }

    $requestedDestinationPath = $DestinationPath
    $DestinationPath = Resolve-RenderKitProjectExportDestination `
        -ProjectRoot $resolvedProjectRoot `
        -DestinationPath $DestinationPath `
        -Mode $Mode
    if ($DestinationPath -cne $requestedDestinationPath) {
        Write-RenderKitLog `
            -Level Info `
            -Message "Normalized project export destination to '$DestinationPath'."
    }

    if ($PSCmdlet.ShouldProcess($resolvedProjectRoot, "Export RenderKit project to '$DestinationPath'")) {
        $manifest = New-RenderKitProjectManifest `
            -ProjectRoot $resolvedProjectRoot `
            -Mode $Mode `
            -DestinationPath $DestinationPath `
            -HashAlgorithm $HashAlgorithm `
            -IncludeAbsolutePaths:$IncludeAbsolutePaths `
            -IncludeMetadata $IncludeMetadata

        $archive = Export-RenderKitProjectArchive `
            -Manifest $manifest `
            -DestinationPath $DestinationPath `
            -Mode $Mode `
            -CompressionLevel $CompressionLevel

        Write-RenderKitLog -Level Info -Message "Exported project '$resolvedProjectRoot' to '$($archive.Path)'."
        return [PSCustomObject]@{
            Path              = $archive.Path
            SizeBytes         = $archive.SizeBytes
            SHA256            = $archive.SHA256
            Mode              = $Mode
            CompressionMethod = $CompressionMethod
            CompressionLevel  = $CompressionLevel
            FileCount         = @($manifest.Files).Count
            TemplateCount     = @($manifest.Templates).Count
            MappingCount      = @($manifest.Mappings).Count
            MetadataFileCount = @($manifest.MetadataFiles).Count
            IncludeMetadata   = [bool]$IncludeMetadata
        }
    }
}
