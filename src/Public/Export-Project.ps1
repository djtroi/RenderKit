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

    $destinationIsDirectory = Test-Path -LiteralPath $DestinationPath -PathType Container
    $trimmedDestination = $DestinationPath.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    if ($destinationIsDirectory -or $trimmedDestination.Length -ne $DestinationPath.Length) {
        $destinationDirectory = if ($destinationIsDirectory) {
            (Resolve-Path -LiteralPath $DestinationPath -ErrorAction Stop).ProviderPath
        }
        else {
            [System.IO.Path]::GetFullPath($trimmedDestination)
        }
        $destinationExtension = if ($Mode -eq 'SelfContained') { '.rkitpkg' } else { '.rkit' }
        $DestinationPath = Join-Path `
            -Path $destinationDirectory `
            -ChildPath ("{0}{1}" -f (Split-Path -Path $resolvedProjectRoot -Leaf), $destinationExtension)
    }
    
    $extension = [System.IO.Path]::GetExtension($DestinationPath).ToLowerInvariant()
    if ($Mode -eq 'ManifestOnly' -and $extension -ne '.rkit') {
        Write-RenderKitLog -Level Warning -Message "ManifestOnly exports should use the .rkit extension."
    }
    if ($Mode -eq 'SelfContained' -and $extension -ne '.rkitpkg') {
        Write-RenderKitLog -Level Warning -Message "SelfContained exports should use the .rkitpkg extension."
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
