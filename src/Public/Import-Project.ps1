Register-RenderKitFunction "Import-Project"
function Import-Project {
    <#
.SYNOPSIS
Imports a RenderKit .rkit manifest package or .rkitpkg self-contained package.
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$DestinationRoot,
        [string]$ProjectName,
        [ValidateSet('Copy', 'LinkOnly')][string]$TransferMode = 'Copy',
        [switch]$VerifyHash,
        [ValidateSet('Error', 'Skip', 'Overwrite')][string]$ConflictAction = 'Error'
    )

    $resolvedArchivePath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    if (-not (Test-Path -LiteralPath $DestinationRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
    }

    $manifest = Read-RenderKitProjectArchiveManifest -Path $resolvedArchivePath
    if ($manifest.RenderKitProjectManifest.schemaVersion -ne '1.0') {
        throw "Unsupported RenderKit project manifest schema version '$($manifest.RenderKitProjectManifest.schemaVersion)'."
    }

    $sourceRootName = [string]$manifest.RenderKitProjectManifest.Project.sourceRootName
    if ([string]::IsNullOrWhiteSpace($ProjectName)) {
        $ProjectName = if (-not [string]::IsNullOrWhiteSpace($sourceRootName)) { $sourceRootName } else { [string]$manifest.RenderKitProjectManifest.Project.name }
    }
    if ([string]::IsNullOrWhiteSpace($ProjectName)) { throw 'Project name could not be resolved from manifest.' }

    $targetRoot = Join-Path -Path $DestinationRoot -ChildPath $ProjectName
    if ((Test-Path -LiteralPath $targetRoot) -and $ConflictAction -eq 'Error') {
        throw "Target project '$targetRoot' already exists. Use -ConflictAction Skip or Overwrite."
    }

    $mode = [string]$manifest.RenderKitProjectManifest.Export.mode
    $isSelfContained = $mode -eq 'SelfContained'
    if ($TransferMode -eq 'Copy' -and -not $isSelfContained) {
        Write-RenderKitLog -Level Warning -Message 'ManifestOnly import cannot copy media because the package does not contain project files. Folder structure and resources will be restored only.'
    }

    if ($PSCmdlet.ShouldProcess($targetRoot, "Import RenderKit project from '$resolvedArchivePath'")) {
        if ((Test-Path -LiteralPath $targetRoot) -and $ConflictAction -eq 'Overwrite') {
            Remove-Item -LiteralPath $targetRoot -Recurse -Force
        }
        if (-not (Test-Path -LiteralPath $targetRoot)) {
            New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
        }

        foreach ($folder in @($manifest.RenderKitProjectManifest.Folders.Folder)) {
            $relativePath = [string]$folder.relativePath
            if (-not (Test-RenderKitProjectSafeRelativePath -RelativePath $relativePath)) { throw "Unsafe relative path in project manifest: '$relativePath'." }
            $folderPath = Join-Path -Path $targetRoot -ChildPath ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path -LiteralPath $folderPath -PathType Container)) {
                New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
            }
        }

        $copied = 0
        $skipped = 0
        $resourceCount = 0
        $hashMismatches = New-Object System.Collections.Generic.List[object]
        $zip = [System.IO.Compression.ZipFile]::OpenRead($resolvedArchivePath)
        try {
            $resourceRoot = Join-Path -Path $targetRoot -ChildPath '.renderkit/exported-resources'
            foreach ($resourceNode in @(@($manifest.RenderKitProjectManifest.Resources.Templates.Template) + @($manifest.RenderKitProjectManifest.Resources.Mappings.Mapping))) {
                if (-not $resourceNode) { continue }
                $resourceRelativePath = [string]$resourceNode.archivePath
                if (-not (Test-RenderKitProjectSafeRelativePath -RelativePath $resourceRelativePath)) { throw "Unsafe resource path in project manifest: '$resourceRelativePath'." }
                $entryName = 'resources/{0}' -f $resourceRelativePath
                $entry = $zip.GetEntry($entryName)
                if (-not $entry) { throw "Archive resource entry '$entryName' is missing." }
                $targetResourceFile = Join-Path -Path $resourceRoot -ChildPath ($resourceRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                $targetResourceDir = Split-Path -Path $targetResourceFile -Parent
                if (-not (Test-Path -LiteralPath $targetResourceDir -PathType Container)) { New-Item -ItemType Directory -Path $targetResourceDir -Force | Out-Null }
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $targetResourceFile, $true)
                if ($VerifyHash) {
                    $expectedResourceSize = [int64]$resourceNode.sizeBytes
                    $resourceItem = Get-Item -LiteralPath $targetResourceFile -ErrorAction Stop
                    if ($resourceItem.Length -ne $expectedResourceSize) {
                        $hashMismatches.Add([PSCustomObject]@{ RelativePath = $resourceRelativePath; Reason = 'ResourceSizeMismatch'; Expected = $expectedResourceSize; Actual = $resourceItem.Length })
                    }
                    elseif ($resourceNode.sha256) {
                        $actualResourceSha = (Get-FileHash -LiteralPath $targetResourceFile -Algorithm SHA256 -ErrorAction Stop).Hash
                        if (-not $actualResourceSha.Equals([string]$resourceNode.sha256, [System.StringComparison]::OrdinalIgnoreCase)) {
                            $hashMismatches.Add([PSCustomObject]@{ RelativePath = $resourceRelativePath; Reason = 'ResourceHashMismatch'; Expected = [string]$resourceNode.sha256; Actual = $actualResourceSha })
                        }
                    }
                }
                $resourceCount++
            }

            if ($isSelfContained -and $TransferMode -eq 'Copy') {
                foreach ($fileNode in @($manifest.RenderKitProjectManifest.Files.File)) {
                    Test-RenderKitProjectManifestFileEntry -FileNode $fileNode
                    $relativePath = [string]$fileNode.relativePath
                    $targetFile = Join-Path -Path $targetRoot -ChildPath ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                    if ((Test-Path -LiteralPath $targetFile -PathType Leaf) -and $ConflictAction -eq 'Skip') { $skipped++; continue }
                    $targetDir = Split-Path -Path $targetFile -Parent
                    if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
                    $entry = $zip.GetEntry(('project/{0}' -f $relativePath))
                    if (-not $entry) { throw "Archive entry for '$relativePath' is missing." }
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $targetFile, $true)
                    $copied++

                    if ($VerifyHash) {
                        $expectedSize = [int64]$fileNode.sizeBytes
                        $item = Get-Item -LiteralPath $targetFile -ErrorAction Stop
                        $expectedShaNode = @($fileNode.Hash | Where-Object { $_.algorithm -eq 'SHA256' } | Select-Object -First 1)
                        $expectedSha = if ($expectedShaNode) { [string]$expectedShaNode.InnerText } else { $null }
                        if ($item.Length -ne $expectedSize) {
                            $hashMismatches.Add([PSCustomObject]@{ RelativePath = $relativePath; Reason = 'SizeMismatch'; Expected = $expectedSize; Actual = $item.Length })
                        }
                        elseif ($expectedSha) {
                            $actualSha = (Get-FileHash -LiteralPath $targetFile -Algorithm SHA256 -ErrorAction Stop).Hash
                            if (-not $actualSha.Equals([string]$expectedSha, [System.StringComparison]::OrdinalIgnoreCase)) {
                                $hashMismatches.Add([PSCustomObject]@{ RelativePath = $relativePath; Reason = 'HashMismatch'; Expected = [string]$expectedSha; Actual = $actualSha })
                            }
                        }
                    }
                }
            }
        }
        finally { $zip.Dispose() }
         $metadataPath = Get-RenderKitProjectMetadataPath -ProjectRoot $targetRoot
        if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
            $metadata = New-RenderKitProjectMetadata `
                -ProjectName $ProjectName `
                -TemplateName 'imported' `
                -TemplateSource 'import'
            $metadata = Set-RenderKitProjectMetadataStatus `
                -Metadata $metadata `
                -Status 'Active' `
                -Reason 'Project imported' `
                -Source 'Import-Project' `
                -Force
            Write-RenderKitProjectMetadata `
                -ProjectRoot $targetRoot `
                -Metadata $metadata
            Write-RenderKitProjectLifecycleEvent `
                -Metadata $metadata `
                -ProjectRoot $targetRoot `
                -FromStatus 'Unknown' `
                -ToStatus 'Active' `
                -Reason 'Project imported' `
                -Source 'Import-Project' |
                Out-Null
        }
        else {
            Set-RenderKitProjectStatus `
                -ProjectRoot $targetRoot `
                -Status 'Active' `
                -Reason 'Project imported' `
                -Source 'Import-Project' `
                -Force |
                Out-Null
        }
        Register-RenderKitProject -ProjectRoot $targetRoot | Out-Null

        return [PSCustomObject]@{
            ProjectRoot       = $targetRoot
            Mode              = $mode
            TransferMode      = $TransferMode
            CopiedFiles       = $copied
            SkippedFiles      = $skipped
            ResourceCount     = $resourceCount
            HashMismatchCount = $hashMismatches.Count
            HashMismatches    = @($hashMismatches.ToArray())
        }
    }
}