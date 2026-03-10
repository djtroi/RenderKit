function Save-BackupManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Manifest,
        [string]$ProjectRoot,
        [string]$ManifestPath
    )

    Write-RenderKitLog -Level Debug -Message "Save-BackupManifest started: ProjectRoot='$ProjectRoot', ManifestPath='$ManifestPath'."

    $targetPath = $ManifestPath
    if ([string]::IsNullOrWhiteSpace($targetPath)) {
        if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
            Write-RenderKitLog -Level Error -Message "Either -ProjectRoot or -ManifestPath must be provided."
            throw "Either -ProjectRoot or -ManifestPath must be provided."
        }

        $renderKitPath = Join-Path $ProjectRoot ".renderkit"
        if (-not (Test-Path -Path $renderKitPath -PathType Container)) {
            Write-RenderKitLog -Level Warning -Message "RenderKit metadata folder not found at '$renderKitPath'. Creating it to store the manifest."
            New-Item -ItemType Directory -Path $renderKitPath | Out-Null
        }

        $targetPath = Join-Path $renderKitPath "backup.manifest.json"
    }
    else {
        $manifestDirectory = Split-Path -Path $targetPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($manifestDirectory) -and -not (Test-Path -Path $manifestDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $manifestDirectory -Force | Out-Null
        }
    }

    $Manifest |
        ConvertTo-Json -Depth 10 |
        Set-Content -Path $targetPath -Encoding UTF8

    Write-RenderKitLog -Level Info -Message "Backup manifest written to '$targetPath'."

    return $targetPath
}
