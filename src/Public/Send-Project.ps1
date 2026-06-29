Register-RenderKitFunction "Send-Project"
function Send-Project {
    <#
.SYNOPSIS
Prepares template-defined project deliverables for client review or delivery.
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$DestinationPath,
        [string]$DeliveryRule,
        [switch]$AllDeliverables,
        [string[]]$MappingId,
        [string[]]$TypeName,
        [string[]]$IncludeExtension,
        [string[]]$ExcludePattern,
        [ValidateSet('Folder', 'Zip', 'ManifestOnly')][string]$PackageMode = 'Zip',
        [ValidateSet('NoCompression', 'Fastest', 'Optimal')][string]$CompressionLevel = 'Optimal',
        [ValidateSet('SHA256', 'MD5')][string[]]$HashAlgorithm = @('SHA256'),
        [switch]$IncludeMd5,
        [bool]$IncludeMetadata = $true,
        [switch]$PassThru
    )

    if ($IncludeMd5 -and $HashAlgorithm -notcontains 'MD5') {
        $HashAlgorithm = @($HashAlgorithm + 'MD5')
    }

    $resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot -ErrorAction Stop).ProviderPath
    if (-not (Test-Path -LiteralPath $resolvedProjectRoot -PathType Container)) {
        throw "Project root '$ProjectRoot' is not a directory."
    }

    $template = Get-RenderKitProjectTemplateContext -ProjectRoot $resolvedProjectRoot
    $rules = @(Get-RenderKitDeliverableRule -Template $template -DeliveryRule $DeliveryRule -AllDeliverables:$AllDeliverables)
    $files = @(Find-RenderKitDeliverableFile `
        -ProjectRoot $resolvedProjectRoot `
        -Rules $rules `
        -MappingId $MappingId `
        -TypeName $TypeName `
        -IncludeExtension $IncludeExtension `
        -ExcludePattern $ExcludePattern)

    $resolvedDestinationPath = $DestinationPath
    if ($PackageMode -eq 'Zip' -and [System.IO.Path]::GetExtension($resolvedDestinationPath).ToLowerInvariant() -ne '.zip') {
        $resolvedDestinationPath = if (Test-Path -LiteralPath $resolvedDestinationPath -PathType Container) {
            Join-Path -Path $resolvedDestinationPath -ChildPath ((Split-Path -Leaf $resolvedProjectRoot) + '-deliverables.zip')
        }
        else {
            "$resolvedDestinationPath.zip"
        }
    }

    $manifest = New-RenderKitDeliverableManifest `
        -ProjectRoot $resolvedProjectRoot `
        -Template $template `
        -Rules $rules `
        -Files $files `
        -PackageMode $PackageMode `
        -DestinationPath $resolvedDestinationPath `
        -HashAlgorithm $HashAlgorithm `
        -IncludeMetadata $IncludeMetadata

    if ($PSCmdlet.ShouldProcess($resolvedProjectRoot, "Prepare deliverables in '$resolvedDestinationPath'")) {
        switch ($PackageMode) {
            'ManifestOnly' {
                Write-RenderKitDeliverableManifest -Manifest $manifest -Path $resolvedDestinationPath
                $outputPath = $resolvedDestinationPath
            }
            'Folder' {
                if (-not (Test-Path -LiteralPath $resolvedDestinationPath -PathType Container)) {
                    New-Item -ItemType Directory -Path $resolvedDestinationPath -Force | Out-Null
                }
                $filesRoot = Join-Path -Path $resolvedDestinationPath -ChildPath 'files'
                if (-not (Test-Path -LiteralPath $filesRoot -PathType Container)) { New-Item -ItemType Directory -Path $filesRoot -Force | Out-Null }
                Copy-RenderKitDeliverableFileSet -Files $files -DestinationRoot $filesRoot
                if ($IncludeMetadata -and $manifest.metadata -and $manifest.metadata.files) {
                    $metadataRoot = Join-Path -Path $resolvedDestinationPath -ChildPath 'metadata'
                    if (-not (Test-Path -LiteralPath $metadataRoot -PathType Container)) {
                        New-Item -ItemType Directory -Path $metadataRoot -Force | Out-Null
                    }
                    Copy-RenderKitDeliverableMetadataFileSet `
                        -MetadataFiles @($manifest.metadata.files) `
                        -DestinationRoot $metadataRoot
                }
                Write-RenderKitDeliverableManifest -Manifest $manifest -Path (Join-Path -Path $resolvedDestinationPath -ChildPath 'manifest.json')
                Write-RenderKitDeliverableChecksumFile -Manifest $manifest -Path (Join-Path -Path $resolvedDestinationPath -ChildPath 'checksums.sha256')
                $outputPath = $resolvedDestinationPath
            }
            'Zip' {
                Export-RenderKitDeliverableZip -Files $files -Manifest $manifest -DestinationPath $resolvedDestinationPath -CompressionLevel $CompressionLevel
                Write-RenderKitDeliverableChecksumFile -Manifest $manifest -Path ($resolvedDestinationPath + '.sha256')
                $outputPath = $resolvedDestinationPath
            }
        }

        $item = Get-Item -LiteralPath $outputPath -ErrorAction Stop
        $result = [PSCustomObject]@{
            Path              = $item.FullName
            PackageMode       = $PackageMode
            CompressionLevel  = $CompressionLevel
            FileCount         = $files.Count
            MetadataFileCount = if ($manifest.metadata -and $manifest.metadata.files) { @($manifest.metadata.files).Count } else { 0 }
            IncludeMetadata   = [bool]$IncludeMetadata
            TemplateName      = $template.Name
            DeliverableRules  = @($rules | ForEach-Object { $_.Id })
            SHA256            = $(if ($item.PSIsContainer) { $null } else { (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256 -ErrorAction Stop).Hash })
        }
        Write-RenderKitLog -Level Info -Message "Prepared $($files.Count) deliverable file(s) from '$resolvedProjectRoot'."
        return $result
    }
}
