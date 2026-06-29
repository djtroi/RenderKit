if ($PSVersionTable.PSVersion.Major -le 5) {
    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
} # Powershell 5.1 Support guard. T_T 

function ConvertTo-RenderKitProjectRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [Parameter(Mandatory)][string]$Path
    )

    $baseFull = [System.IO.Path]::GetFullPath($BasePath).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $pathFull = [System.IO.Path]::GetFullPath($Path)
    $baseUri = [System.Uri]::new($baseFull + [System.IO.Path]::DirectorySeparatorChar)
    $pathUri = [System.Uri]::new($pathFull)
    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace('\\', '/')
}

function Test-RenderKitProjectSafeRelativePath {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$RelativePath)

    if ([string]::IsNullOrWhiteSpace($RelativePath)) { return $false }
    if ([System.IO.Path]::IsPathRooted($RelativePath)) { return $false }
    $parts = $RelativePath -split '[\\/]+'
    return -not ($parts -contains '..')
}

function Get-RenderKitProjectFileHashSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$Algorithms = @('SHA256')
    )

    $hashes = @{}
    foreach ($algorithm in @($Algorithms | Where-Object { $_ } | Sort-Object -Unique)) {
        $hashes[$algorithm.ToUpperInvariant()] = (Get-FileHash -LiteralPath $Path -Algorithm $algorithm -ErrorAction Stop).Hash
    }
    return $hashes
}

function Get-RenderKitProjectArchiveCompressionLevel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$File,
        [ValidateSet('NoCompression', 'Fastest', 'Optimal')]
        [string]$DefaultCompressionLevel = 'Optimal'
    )

    $compressedExtensions = @(
        '.mp4', '.mov', '.m4v', '.mkv', '.avi', '.wmv', '.mp3', '.aac', '.m4a', '.ogg', '.flac',
        '.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.zip', '.rar', '.7z', '.gz', '.bz2', '.xz', '.zst',
        '.pdf', '.iso'
    )

    if ($compressedExtensions -contains $File.Extension.ToLowerInvariant()) {
        return [System.IO.Compression.CompressionLevel]::NoCompression
    }

    if ($File.Length -lt 16MB) {
        return [System.IO.Compression.CompressionLevel]::Optimal
    }

    switch ($DefaultCompressionLevel) {
        'NoCompression' { return [System.IO.Compression.CompressionLevel]::NoCompression }
        'Fastest' { return [System.IO.Compression.CompressionLevel]::Fastest }
        default { return [System.IO.Compression.CompressionLevel]::Optimal }
    }
}

function Get-RenderKitProjectTemplateSnapshot {
    [CmdletBinding()]
    param()

    $snapshots = New-Object System.Collections.Generic.List[object]
    foreach ($template in @(Get-RenderKitTemplate -Source all)) {
        try {
            $item = Get-Item -LiteralPath $template.Path -ErrorAction Stop
            $snapshots.Add([PSCustomObject]@{
                Name         = [string]$template.Name
                Source       = [string]$template.Source
                RelativePath = ('templates/{0}/{1}' -f $template.Source, $item.Name)
                OriginalPath = [string]$item.FullName
                SizeBytes    = [int64]$item.Length
                Sha256       = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
            })
        }
        catch {
            Write-RenderKitLog -Level Warning -Message "Could not snapshot template '$($template.Name)': $($_.Exception.Message)"
        }
    }
    return $snapshots.ToArray()
}

function Get-RenderKitProjectMappingSnapshot {
    [CmdletBinding()]
    param()

    $snapshots = New-Object System.Collections.Generic.List[object]
    $roots = @(
        [PSCustomObject]@{ Source = 'system'; Path = Get-RenderKitSystemMappingsRoot },
        [PSCustomObject]@{ Source = 'user'; Path = Get-RenderKitUserMappingsRoot }
    )

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root.Path -PathType Container)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $root.Path -Filter '*.json' -File -Force -ErrorAction SilentlyContinue)) {
            try {
                $snapshots.Add([PSCustomObject]@{
                    Id           = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                    Source       = [string]$root.Source
                    RelativePath = ('mappings/{0}/{1}' -f $root.Source, $file.Name)
                    OriginalPath = [string]$file.FullName
                    SizeBytes    = [int64]$file.Length
                    Sha256       = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
                })
            }
            catch {
                Write-RenderKitLog -Level Warning -Message "Could not snapshot mapping '$($file.Name)': $($_.Exception.Message)"
            }
        }
    }
    return $snapshots.ToArray()
}

function Get-RenderKitProjectMetadataSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    $snapshots = New-Object System.Collections.Generic.List[object]
    $metadataRoot = Join-Path -Path $ProjectRoot -ChildPath '.renderkit/metadata'
    if (-not (Test-Path -LiteralPath $metadataRoot -PathType Container)) {
        return @()
    }

    foreach ($file in @(Get-ChildItem -LiteralPath $metadataRoot -Recurse -File -Filter '*.json' -Force -ErrorAction SilentlyContinue)) {
        try {
            $relativePath = ConvertTo-RenderKitProjectRelativePath `
                -BasePath $metadataRoot `
                -Path $file.FullName
            if (-not (Test-RenderKitProjectSafeRelativePath -RelativePath $relativePath)) {
                Write-RenderKitLog -Level Warning -Message "Skipping unsafe metadata path '$relativePath'."
                continue
            }
            $snapshots.Add([PSCustomObject]@{
                RelativePath = $relativePath
                OriginalPath = [string]$file.FullName
                ArchivePath  = $relativePath
                SizeBytes    = [int64]$file.Length
                Sha256       = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
            })
        }
        catch {
            Write-RenderKitLog -Level Warning -Message "Could not snapshot metadata '$($file.FullName)': $($_.Exception.Message)"
        }
    }

    return $snapshots.ToArray()
}

function New-RenderKitProjectManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][ValidateSet('ManifestOnly', 'SelfContained')][string]$Mode,
        [Parameter(Mandatory)][string]$DestinationPath,
        [string[]]$HashAlgorithm = @('SHA256'),
        [switch]$IncludeAbsolutePaths,
        [bool]$IncludeMetadata = $true
    )

    $resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot -ErrorAction Stop).ProviderPath
    $projectInfo = Get-Item -LiteralPath $resolvedProjectRoot -ErrorAction Stop
    $metadataPath = Get-RenderKitProjectMetadataPath -ProjectRoot $resolvedProjectRoot
    $metadata = $null
    if (Test-Path -LiteralPath $metadataPath -PathType Leaf) {
        $metadata = Read-RenderKitJsonFile -Path $metadataPath
    }

    $doc = [System.Xml.XmlDocument]::new()
    $declaration = $doc.CreateXmlDeclaration('1.0', 'utf-8', $null)
    [void]$doc.AppendChild($declaration)
    $root = $doc.CreateElement('RenderKitProjectManifest')
    $root.SetAttribute('schemaVersion', '1.0')
    $root.SetAttribute('createdAtUtc', (Get-Date).ToUniversalTime().ToString('o'))
    [void]$doc.AppendChild($root)

    $tool = $doc.CreateElement('Tool')
    $tool.SetAttribute('name', 'RenderKit')
    $tool.SetAttribute('version', [string]$script:RenderKitModuleVersion)
    [void]$root.AppendChild($tool)

    $project = $doc.CreateElement('Project')
    $projectId = if ($metadata -and $metadata.project -and $metadata.project.id) { [string]$metadata.project.id } else { [guid]::NewGuid().Guid }
    $projectName = if ($metadata -and $metadata.project -and $metadata.project.name) { [string]$metadata.project.name } else { [string]$projectInfo.Name }
    $project.SetAttribute('id', $projectId)
    $project.SetAttribute('name', $projectName)
    $project.SetAttribute('sourceRootName', $projectInfo.Name)
    if ($metadata -and $metadata.template) {
        $project.SetAttribute('templateName', [string]$metadata.template.name)
        $project.SetAttribute('templateSource', [string]$metadata.template.source)
    }
    [void]$root.AppendChild($project)

    $export = $doc.CreateElement('Export')
    $export.SetAttribute('id', [guid]::NewGuid().Guid)
    $export.SetAttribute('mode', $Mode)
    $export.SetAttribute('destinationName', [System.IO.Path]::GetFileName($DestinationPath))
    $export.SetAttribute('hashAlgorithms', (($HashAlgorithm | ForEach-Object { $_.ToUpperInvariant() }) -join ','))
    [void]$root.AppendChild($export)

    $filesElement = $doc.CreateElement('Files')
    [void]$root.AppendChild($filesElement)
    $files = @(
        Get-ChildItem -LiteralPath $resolvedProjectRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object {
                $relativePath = ConvertTo-RenderKitProjectRelativePath `
                    -BasePath $resolvedProjectRoot `
                    -Path $_.FullName
                -not ($relativePath -like '.renderkit/metadata/*')
            }
    )
    foreach ($file in $files) {
        $relativePath = ConvertTo-RenderKitProjectRelativePath -BasePath $resolvedProjectRoot -Path $file.FullName
        $hashes = Get-RenderKitProjectFileHashSet -Path $file.FullName -Algorithms $HashAlgorithm
        $fileElement = $doc.CreateElement('File')
        $fileElement.SetAttribute('relativePath', $relativePath)
        $fileElement.SetAttribute('name', $file.Name)
        $fileElement.SetAttribute('extension', $file.Extension)
        $fileElement.SetAttribute('sizeBytes', [string][int64]$file.Length)
        $fileElement.SetAttribute('creationTimeUtc', $file.CreationTimeUtc.ToString('o'))
        $fileElement.SetAttribute('lastWriteTimeUtc', $file.LastWriteTimeUtc.ToString('o'))
        if ($IncludeAbsolutePaths) { $fileElement.SetAttribute('originalAbsolutePath', $file.FullName) }
        foreach ($key in @($hashes.Keys | Sort-Object)) {
            $hashElement = $doc.CreateElement('Hash')
            $hashElement.SetAttribute('algorithm', $key)
            $hashElement.InnerText = [string]$hashes[$key]
            [void]$fileElement.AppendChild($hashElement)
        }
        [void]$filesElement.AppendChild($fileElement)
    }

    $foldersElement = $doc.CreateElement('Folders')
    [void]$root.InsertBefore($foldersElement, $filesElement)
    foreach ($directory in @(
        Get-ChildItem -LiteralPath $resolvedProjectRoot -Recurse -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object {
                $relativePath = ConvertTo-RenderKitProjectRelativePath `
                    -BasePath $resolvedProjectRoot `
                    -Path $_.FullName
                -not ($relativePath -eq '.renderkit/metadata' -or
                    $relativePath -like '.renderkit/metadata/*')
            }
    )) {
        $folderElement = $doc.CreateElement('Folder')
        $folderElement.SetAttribute('relativePath', (ConvertTo-RenderKitProjectRelativePath -BasePath $resolvedProjectRoot -Path $directory.FullName))
        $folderElement.SetAttribute('creationTimeUtc', $directory.CreationTimeUtc.ToString('o'))
        $folderElement.SetAttribute('lastWriteTimeUtc', $directory.LastWriteTimeUtc.ToString('o'))
        [void]$foldersElement.AppendChild($folderElement)
    }

    $templateSnapshots = @(Get-RenderKitProjectTemplateSnapshot)
    $mappingSnapshots = @(Get-RenderKitProjectMappingSnapshot)

    $resources = $doc.CreateElement('Resources')
    [void]$root.AppendChild($resources)
    $templatesElement = $doc.CreateElement('Templates')
    [void]$resources.AppendChild($templatesElement)
    foreach ($template in $templateSnapshots) {
        $element = $doc.CreateElement('Template')
        $element.SetAttribute('name', $template.Name)
        $element.SetAttribute('source', $template.Source)
        $element.SetAttribute('archivePath', $template.RelativePath)
        $element.SetAttribute('sizeBytes', [string]$template.SizeBytes)
        $element.SetAttribute('sha256', $template.Sha256)
        [void]$templatesElement.AppendChild($element)
    }
    $mappingsElement = $doc.CreateElement('Mappings')
    [void]$resources.AppendChild($mappingsElement)
    foreach ($mapping in $mappingSnapshots) {
        $element = $doc.CreateElement('Mapping')
        $element.SetAttribute('id', $mapping.Id)
        $element.SetAttribute('source', $mapping.Source)
        $element.SetAttribute('archivePath', $mapping.RelativePath)
        $element.SetAttribute('sizeBytes', [string]$mapping.SizeBytes)
        $element.SetAttribute('sha256', $mapping.Sha256)
        [void]$mappingsElement.AppendChild($element)
    }

    $metadataSnapshots = if ($IncludeMetadata) {
        @(Get-RenderKitProjectMetadataSnapshot -ProjectRoot $resolvedProjectRoot)
    }
    else {
        @()
    }
    $metadataElement = $doc.CreateElement('Metadata')
    $metadataElement.SetAttribute('included', ([bool]$IncludeMetadata).ToString().ToLowerInvariant())
    [void]$root.AppendChild($metadataElement)
    foreach ($metadataFile in $metadataSnapshots) {
        $element = $doc.CreateElement('MetadataFile')
        $element.SetAttribute('relativePath', [string]$metadataFile.RelativePath)
        $element.SetAttribute('archivePath', [string]$metadataFile.ArchivePath)
        $element.SetAttribute('sizeBytes', [string]$metadataFile.SizeBytes)
        $element.SetAttribute('sha256', [string]$metadataFile.Sha256)
        [void]$metadataElement.AppendChild($element)
    }

    return [PSCustomObject]@{
        Document      = $doc
        Files         = $files
        Templates     = $templateSnapshots
        Mappings      = $mappingSnapshots
        MetadataFiles = $metadataSnapshots
        ProjectRoot = $resolvedProjectRoot
    }
}

function Add-RenderKitFileToZipArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.Compression.ZipArchive]$Archive,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$EntryName,
        [ValidateSet('NoCompression', 'Fastest', 'Optimal')]
        [string]$DefaultCompressionLevel = 'Optimal'
    )

    $file = Get-Item -LiteralPath $SourcePath -ErrorAction Stop
    $level = Get-RenderKitProjectArchiveCompressionLevel -File $file -DefaultCompressionLevel $DefaultCompressionLevel
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($Archive, $file.FullName, ($EntryName -replace '\\', '/'), $level)
}

function Export-RenderKitProjectArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][ValidateSet('ManifestOnly', 'SelfContained')][string]$Mode,
        [ValidateSet('NoCompression', 'Fastest', 'Optimal')]
        [string]$CompressionLevel = 'Optimal'
    )

    $destinationDirectory = Split-Path -Path $DestinationPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($destinationDirectory) -and -not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }
    if (Test-Path -LiteralPath $DestinationPath -PathType Leaf) { Remove-Item -LiteralPath $DestinationPath -Force }

    $zip = [System.IO.Compression.ZipFile]::Open($DestinationPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $projectEntry = $zip.CreateEntry('project.xml', [System.IO.Compression.CompressionLevel]::Optimal)
        $stream = $projectEntry.Open()
        try {
            $writer = [System.IO.StreamWriter]::new($stream, [System.Text.UTF8Encoding]::new($false))
            try { $Manifest.Document.Save($writer) } finally { $writer.Dispose() }
        }
        finally { $stream.Dispose() }

        foreach ($template in @($Manifest.Templates)) {
            Add-RenderKitFileToZipArchive -Archive $zip -SourcePath $template.OriginalPath -EntryName ('resources/{0}' -f $template.RelativePath) -DefaultCompressionLevel Optimal
        }
        foreach ($mapping in @($Manifest.Mappings)) {
            Add-RenderKitFileToZipArchive -Archive $zip -SourcePath $mapping.OriginalPath -EntryName ('resources/{0}' -f $mapping.RelativePath) -DefaultCompressionLevel Optimal
        }
        foreach ($metadataFile in @($Manifest.MetadataFiles)) {
            Add-RenderKitFileToZipArchive `
                -Archive $zip `
                -SourcePath $metadataFile.OriginalPath `
                -EntryName ('metadata/{0}' -f $metadataFile.ArchivePath) `
                -DefaultCompressionLevel Optimal
        }

        if ($Mode -eq 'SelfContained') {
            foreach ($file in @($Manifest.Files)) {
                $relativePath = ConvertTo-RenderKitProjectRelativePath -BasePath $Manifest.ProjectRoot -Path $file.FullName
                Add-RenderKitFileToZipArchive -Archive $zip -SourcePath $file.FullName -EntryName ('project/{0}' -f $relativePath) -DefaultCompressionLevel $CompressionLevel
            }
        }
    }
    finally {
        $zip.Dispose()
    }

    $archive = Get-Item -LiteralPath $DestinationPath -ErrorAction Stop
    return [PSCustomObject]@{
        Path      = $archive.FullName
        SizeBytes = [int64]$archive.Length
        SHA256    = (Get-FileHash -LiteralPath $archive.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
    }
}

function Read-RenderKitProjectArchiveManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $zip.GetEntry('project.xml')
        if (-not $entry) { throw "Archive '$Path' does not contain project.xml." }
        $stream = $entry.Open()
        try {
            $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
            try { [xml]$xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
        }
        finally { $stream.Dispose() }
        return $xml
    }
    finally { $zip.Dispose() }
}

function Test-RenderKitProjectManifestFileEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$FileNode)

    $relativePath = [string]$FileNode.relativePath
    if (-not (Test-RenderKitProjectSafeRelativePath -RelativePath $relativePath)) {
        throw "Unsafe relative path in project manifest: '$relativePath'."
    }
}
