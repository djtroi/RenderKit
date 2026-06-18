function Get-RenderKitProjectTemplateContext {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)

    $metadataPath = Get-RenderKitProjectMetadataPath -ProjectRoot $ProjectRoot
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        Write-RenderKitLog -Level Warning -Message "Project metadata not found. Using default template."
        return Get-ProjectTemplate
    }

    $metadata = Read-RenderKitJsonFile -Path $metadataPath
    if ($metadata.template -and $metadata.template.name) {
        return Get-ProjectTemplate -TemplateName ([string]$metadata.template.name)
    }

    return Get-ProjectTemplate
}

function ConvertTo-RenderKitArrayList {
    param([object]$Value)
    if ($null -eq $Value) { return [System.Collections.ArrayList]::new() }
    if ($Value -is [System.Collections.ArrayList]) { return $Value }
    return [System.Collections.ArrayList]@($Value)
}

function Get-RenderKitDeliverableFallbackRule {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Template)

    $candidateNames = @('05_Exports', '06_Review', '07_Publish', '02_Exports', 'Exports', 'Review', 'Publish')
    $sourceFolders = New-Object System.Collections.Generic.List[string]
    foreach ($folder in @($Template.Folders)) {
        if ($candidateNames -contains ([string]$folder.Name)) {
            $sourceFolders.Add([string]$folder.Name)
        }
    }

    if ($sourceFolders.Count -eq 0) { return @() }

    return @([PSCustomObject]@{
        Id                = 'exports'
        Name              = 'Exports'
        SourceFolders     = $sourceFolders.ToArray()
        Recursive         = $true
        MappingIds        = @('video', 'audio', 'image', 'document')
        TypeNames         = @()
        IncludeExtensions = @('.mp4', '.mov', '.m4v', '.mkv', '.webm', '.mp3', '.wav', '.m4a', '.aac', '.jpg', '.jpeg', '.png', '.webp', '.pdf', '.txt')
        ExcludePatterns   = @('*_draft*', '*_proxy*', '*.tmp')
        DefaultPackage    = $true
    })
}

function Get-RenderKitDeliverableRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Template,
        [string]$DeliveryRule,
        [switch]$AllDeliverables
    )

    $rules = @($Template.Deliverables)
    if ($rules.Count -eq 0) { $rules = @(Get-RenderKitDeliverableFallbackRule -Template $Template) }

    if ($AllDeliverables) { return $rules }
    if (-not [string]::IsNullOrWhiteSpace($DeliveryRule)) {
        $match = @($rules | Where-Object { $_.Id -eq $DeliveryRule -or $_.Name -eq $DeliveryRule })
        if ($match.Count -eq 0) { throw "Deliverable rule '$DeliveryRule' not found in template '$($Template.Name)'." }
        return $match
    }

    $default = @($rules | Where-Object { $_.DefaultPackage })
    if ($default.Count -gt 0) { return $default }
    if ($rules.Count -gt 0) { return @($rules[0]) }
    throw "Template '$($Template.Name)' does not define deliverables and no fallback deliverable folder was found."
}

function Get-RenderKitMappingExtensionIndex {
    [CmdletBinding()]
    param([string[]]$MappingIds)

    $index = @{}
    foreach ($mappingId in @($MappingIds | Where-Object { $_ } | Sort-Object -Unique)) {
        $mapping = Read-RenderKitMappingFile -MappingId $mappingId
        if (-not $mapping) { continue }
        foreach ($type in @($mapping.Types)) {
            foreach ($extension in @($type.Extensions)) {
                if ([string]::IsNullOrWhiteSpace($extension)) { continue }
                $index[$extension.ToLowerInvariant()] = [PSCustomObject]@{
                    MappingId = [string]$mapping.Id
                    TypeName  = [string]$type.Name
                }
            }
        }
    }
    return $index
}

function Test-RenderKitWildcardMatch {
    param([string]$Value, [string[]]$Patterns)
    foreach ($pattern in @($Patterns | Where-Object { $_ })) {
        if ($Value -like $pattern) { return $true }
    }
    return $false
}

function Find-RenderKitDeliverableFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)]$Rules,
        [string[]]$MappingId,
        [string[]]$TypeName,
        [string[]]$IncludeExtension,
        [string[]]$ExcludePattern
    )

    $selectedMappingIds = New-Object System.Collections.Generic.List[string]
    foreach ($rule in @($Rules)) { foreach ($id in @($rule.MappingIds)) { if ($id -and -not $selectedMappingIds.Contains($id)) { $selectedMappingIds.Add($id) } } }
    foreach ($id in @($MappingId)) { if ($id -and -not $selectedMappingIds.Contains($id)) { $selectedMappingIds.Add($id) } }
    if ($selectedMappingIds.Count -eq 0) { @('video', 'audio', 'image', 'document') | ForEach-Object { $selectedMappingIds.Add($_) } }
    $extensionIndex = Get-RenderKitMappingExtensionIndex -MappingIds $selectedMappingIds.ToArray()

    $explicitExtensions = @($IncludeExtension | Where-Object { $_ } | ForEach-Object { if ($_.StartsWith('.')) { $_.ToLowerInvariant() } else { ".$($_.ToLowerInvariant())" } })
    $seen = @{}
    $seenPackagePaths = @{}
    $result = New-Object System.Collections.Generic.List[object]

    foreach ($rule in @($Rules)) {
        $ruleExtensions = @($rule.IncludeExtensions | Where-Object { $_ } | ForEach-Object { if ($_.StartsWith('.')) { $_.ToLowerInvariant() } else { ".$($_.ToLowerInvariant())" } })
        $allowedExtensions = if ($explicitExtensions.Count -gt 0) { $explicitExtensions } elseif ($ruleExtensions.Count -gt 0) { $ruleExtensions } else { @($extensionIndex.Keys) }
        $allowedMappings = if ($MappingId) { @($MappingId) } else { @($rule.MappingIds) }
        $allowedTypes = if ($TypeName) { @($TypeName) } else { @($rule.TypeNames) }
        $excludes = @($rule.ExcludePatterns) + @($ExcludePattern)

        foreach ($folder in @($rule.SourceFolders)) {
            if ([string]::IsNullOrWhiteSpace($folder)) { continue }
            if (-not (Test-RenderKitProjectSafeRelativePath -RelativePath $folder)) { throw "Unsafe deliverable source folder '$folder'." }
            $sourceRoot = Join-Path -Path $ProjectRoot -ChildPath $folder
            if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
                Write-RenderKitLog -Level Warning -Message "Deliverable source folder not found: $sourceRoot"
                continue
            }
            $files = if ($rule.Recursive) {
                Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -Force -ErrorAction SilentlyContinue
            }
            else {
                Get-ChildItem -LiteralPath $sourceRoot -File -Force -ErrorAction SilentlyContinue
            }
            foreach ($file in @($files)) {
                $extension = $file.Extension.ToLowerInvariant()
                if ($allowedExtensions.Count -gt 0 -and $allowedExtensions -notcontains $extension) { continue }
                if (Test-RenderKitWildcardMatch -Value $file.Name -Patterns $excludes) { continue }
                $mappingInfo = $extensionIndex[$extension]
                if ($allowedMappings.Count -gt 0 -and $mappingInfo -and $allowedMappings -notcontains $mappingInfo.MappingId) { continue }
                if ($allowedTypes.Count -gt 0 -and $mappingInfo -and $allowedTypes -notcontains $mappingInfo.TypeName) { continue }
                if ($seen.ContainsKey($file.FullName)) { continue }
                $seen[$file.FullName] = $true
                $projectRelativePath = ConvertTo-RenderKitProjectRelativePath -BasePath $ProjectRoot -Path $file.FullName
                $deliverableRelativePath = ConvertTo-RenderKitProjectRelativePath -BasePath $sourceRoot -Path $file.FullName
                $packageRelativePath = $deliverableRelativePath
                if ($seenPackagePaths.ContainsKey($packageRelativePath)) {
                    $packageRelativePath = (Join-Path -Path $folder -ChildPath $deliverableRelativePath) -replace '\\', '/'
                }
                if ($seenPackagePaths.ContainsKey($packageRelativePath)) { continue }
                $seenPackagePaths[$packageRelativePath] = $true
                $result.Add([PSCustomObject]@{
                    SourcePath              = $file.FullName
                    ProjectRelativePath     = $projectRelativePath
                    DeliverableRelativePath = $deliverableRelativePath
                    PackageRelativePath     = $packageRelativePath
                    SourceFolder            = $folder
                    Name                    = $file.Name
                    Extension               = $extension
                    SizeBytes               = [int64]$file.Length
                    MappingId               = $(if ($mappingInfo) { $mappingInfo.MappingId } else { $null })
                    TypeName                = $(if ($mappingInfo) { $mappingInfo.TypeName } else { $null })
                })
            }
        }
    }

    return @($result.ToArray() | Sort-Object ProjectRelativePath)
}

function New-RenderKitDeliverableManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)]$Template,
        [Parameter(Mandatory)]$Rules,
        [Parameter(Mandatory)]$Files,
        [Parameter(Mandatory)][string]$PackageMode,
        [Parameter(Mandatory)][string]$DestinationPath,
        [string[]]$HashAlgorithm = @('SHA256')
    )

    $projectInfo = Get-Item -LiteralPath $ProjectRoot -ErrorAction Stop
    $manifestFiles = New-Object System.Collections.Generic.List[object]
    foreach ($file in @($Files)) {
        $hashes = Get-RenderKitProjectFileHashSet -Path $file.SourcePath -Algorithms $HashAlgorithm
        $manifestFiles.Add([PSCustomObject]@{
            sourceRelativePath      = $file.ProjectRelativePath
            deliverableRelativePath = $file.DeliverableRelativePath
            packageRelativePath     = $file.PackageRelativePath
            sourceFolder            = $file.SourceFolder
            name                    = $file.Name
            extension               = $file.Extension
            sizeBytes               = $file.SizeBytes
            mappingId               = $file.MappingId
            typeName                = $file.TypeName
            hashes                  = $hashes
        })
    }

    return [PSCustomObject]@{
        schemaVersion = '1.0'
        deliveryId    = ([guid]::NewGuid()).Guid
        createdAtUtc  = (Get-Date).ToUniversalTime().ToString('o')
        project       = [PSCustomObject]@{ name = $projectInfo.Name; rootName = $projectInfo.Name }
        template      = [PSCustomObject]@{ name = $Template.Name; version = $Template.Version; source = $Template.Source }
        rules         = @($Rules | ForEach-Object { [PSCustomObject]@{ id = $_.Id; name = $_.Name; sourceFolders = @($_.SourceFolders) } })
        package       = [PSCustomObject]@{ mode = $PackageMode; destinationPath = $DestinationPath; hashAlgorithms = @($HashAlgorithm) }
        files         = $manifestFiles.ToArray()
    }
}

function Copy-RenderKitDeliverableFileSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Files,
        [Parameter(Mandatory)][string]$DestinationRoot
    )
    foreach ($file in @($Files)) {
        $target = Join-Path -Path $DestinationRoot -ChildPath $file.PackageRelativePath
        $targetDirectory = Split-Path -Path $target -Parent
        if (-not (Test-Path -LiteralPath $targetDirectory -PathType Container)) { New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null }
        Copy-Item -LiteralPath $file.SourcePath -Destination $target -Force -ErrorAction Stop
    }
}

function Write-RenderKitDeliverableManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$Path
    )
    $directory = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    Write-RenderKitJsonFileAtomic `
        -Value $Manifest `
        -Path $Path `
        -Depth 20 |
        Out-Null
}

function Write-RenderKitDeliverableChecksumFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$Path
    )
    $lines = foreach ($file in @($Manifest.files)) {
        if ($file.hashes.SHA256) { "$($file.hashes.SHA256)  $($file.packageRelativePath)" }
    }
    if ($lines) { $lines | Set-Content -LiteralPath $Path -Encoding ASCII }
}

function Export-RenderKitDeliverableZip {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Files,
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$DestinationPath,
        [ValidateSet('NoCompression', 'Fastest', 'Optimal')][string]$CompressionLevel = 'Optimal'
    )
    $directory = Split-Path -Path $DestinationPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    if (Test-Path -LiteralPath $DestinationPath -PathType Leaf) { Remove-Item -LiteralPath $DestinationPath -Force }
    $stagingRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("RenderKitDelivery_{0}" -f ([guid]::NewGuid().Guid))
    $stagingFilesRoot = Join-Path -Path $stagingRoot -ChildPath 'files'
    New-Item -ItemType Directory -Path $stagingFilesRoot -Force | Out-Null
    try {
        Copy-RenderKitDeliverableFileSet -Files $Files -DestinationRoot $stagingFilesRoot
        $zip = [System.IO.Compression.ZipFile]::Open($DestinationPath, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            $manifestEntry = $zip.CreateEntry('manifest.json', [System.IO.Compression.CompressionLevel]::Optimal)
            $stream = $manifestEntry.Open()
            try {
                $writer = [System.IO.StreamWriter]::new($stream, [System.Text.UTF8Encoding]::new($false))
                try { $writer.Write(($Manifest | ConvertTo-Json -Depth 20)) } finally { $writer.Dispose() }
            }
            finally { $stream.Dispose() }

            foreach ($file in @($Files)) {
                $stagedPath = Join-Path -Path $stagingFilesRoot -ChildPath $file.PackageRelativePath
                Add-RenderKitFileToZipArchive -Archive $zip -SourcePath $stagedPath -EntryName ('files/{0}' -f $file.PackageRelativePath) -DefaultCompressionLevel $CompressionLevel
            }
        }
        finally { $zip.Dispose() }
    }
    finally {
        if (Test-Path -LiteralPath $stagingRoot -PathType Container) {
            Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
