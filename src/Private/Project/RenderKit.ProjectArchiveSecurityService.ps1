if ($PSVersionTable.PSVersion.Major -le 5) {
    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
}

function ConvertTo-RenderKitProjectArchiveExpectedSize {
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$EntryName
    )

    $parsed = [int64]0
    if (-not [int64]::TryParse(
            [string]$Value,
            [System.Globalization.NumberStyles]::Integer,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$parsed
        ) -or $parsed -lt 0) {
        throw "Archive entry '$EntryName' has an invalid declared size."
    }
    return [long]$parsed
}

function Get-RenderKitProjectArchiveEntryIndex {
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param(
        [Parameter(Mandatory)][System.IO.Compression.ZipArchive]$Archive,
        [int]$MaximumArchiveEntries = 250000
    )

    if ($MaximumArchiveEntries -le 0) {
        throw 'Maximum archive entry count must be greater than zero.'
    }
    if ($Archive.Entries.Count -gt $MaximumArchiveEntries) {
        throw "Project archive contains $($Archive.Entries.Count) entries; maximum allowed is $MaximumArchiveEntries."
    }

    $index = [System.Collections.Generic.Dictionary[string,System.IO.Compression.ZipArchiveEntry]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($entry in $Archive.Entries) {
        $normalizedName = ([string]$entry.FullName).Replace('\', '/')
        if ([string]::IsNullOrWhiteSpace($normalizedName)) {
            throw 'Project archive contains an entry without a usable name.'
        }
        if ($index.ContainsKey($normalizedName)) {
            throw "Project archive contains duplicate or case-colliding entry '$normalizedName'."
        }
        $index.Add($normalizedName, $entry)
    }
    return $index
}

function Get-RenderKitProjectArchiveRequiredEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Manifest,
        [bool]$IncludeMetadata,
        [bool]$IncludeProjectFiles
    )

    $required = New-Object System.Collections.Generic.List[object]

    foreach ($resourceNode in @(
        @($Manifest.RenderKitProjectManifest.Resources.Templates.Template) +
        @($Manifest.RenderKitProjectManifest.Resources.Mappings.Mapping)
    )) {
        if (-not $resourceNode) { continue }
        $relativePath = [string]$resourceNode.archivePath
        if (-not (Test-RenderKitProjectSafeRelativePath -RelativePath $relativePath)) {
            throw "Unsafe resource path in project manifest: '$relativePath'."
        }
        $entryName = ('resources/{0}' -f $relativePath).Replace('\', '/')
        $required.Add([PSCustomObject]@{
            Name = $entryName
            ExpectedSize = ConvertTo-RenderKitProjectArchiveExpectedSize `
                -Value $resourceNode.sizeBytes `
                -EntryName $entryName
        })
    }

    if ($IncludeMetadata) {
        foreach ($metadataNode in @($Manifest.RenderKitProjectManifest.Metadata.MetadataFile)) {
            if (-not $metadataNode) { continue }
            $archivePath = [string]$metadataNode.archivePath
            if ([string]::IsNullOrWhiteSpace($archivePath)) {
                $archivePath = [string]$metadataNode.relativePath
            }
            if (-not (Test-RenderKitProjectSafeRelativePath -RelativePath $archivePath)) {
                throw "Unsafe metadata archive path in project manifest: '$archivePath'."
            }
            $entryName = ('metadata/{0}' -f $archivePath).Replace('\', '/')
            $required.Add([PSCustomObject]@{
                Name = $entryName
                ExpectedSize = ConvertTo-RenderKitProjectArchiveExpectedSize `
                    -Value $metadataNode.sizeBytes `
                    -EntryName $entryName
            })
        }
    }

    if ($IncludeProjectFiles) {
        foreach ($fileNode in @($Manifest.RenderKitProjectManifest.Files.File)) {
            Test-RenderKitProjectManifestFileEntry -FileNode $fileNode
            $relativePath = [string]$fileNode.relativePath
            $entryName = ('project/{0}' -f $relativePath).Replace('\', '/')
            $required.Add([PSCustomObject]@{
                Name = $entryName
                ExpectedSize = ConvertTo-RenderKitProjectArchiveExpectedSize `
                    -Value $fileNode.sizeBytes `
                    -EntryName $entryName
            })
        }
    }

    return $required.ToArray()
}

function Test-RenderKitProjectArchivePreflight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$DestinationRoot,
        [bool]$IncludeMetadata,
        [bool]$IncludeProjectFiles,
        [int]$MaximumArchiveEntries = 250000,
        [int64]$MinimumFreeSpaceReserveBytes = 256MB
    )

    if ($MinimumFreeSpaceReserveBytes -lt 0) {
        throw 'Minimum free-space reserve must not be negative.'
    }

    $zip = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $index = Get-RenderKitProjectArchiveEntryIndex `
            -Archive $zip `
            -MaximumArchiveEntries $MaximumArchiveEntries
        $requiredEntries = @(Get-RenderKitProjectArchiveRequiredEntry `
            -Manifest $Manifest `
            -IncludeMetadata $IncludeMetadata `
            -IncludeProjectFiles $IncludeProjectFiles)

        $totalRequired = [int64]0
        foreach ($requiredEntry in $requiredEntries) {
            $entry = $null
            if (-not $index.TryGetValue([string]$requiredEntry.Name, [ref]$entry)) {
                throw "Project archive entry '$($requiredEntry.Name)' is missing."
            }
            $expectedSize = [int64]$requiredEntry.ExpectedSize
            if ([int64]$entry.Length -ne $expectedSize) {
                throw (
                    "Project archive entry '$($requiredEntry.Name)' declares $($entry.Length) uncompressed bytes " +
                    "but the manifest expects $expectedSize bytes."
                )
            }
            if ($totalRequired -gt ([int64]::MaxValue - $expectedSize)) {
                throw 'Project archive expanded size exceeds the supported range.'
            }
            $totalRequired += $expectedSize
        }

        try {
            $destinationFullPath = [System.IO.Path]::GetFullPath($DestinationRoot)
            $pathRoot = [System.IO.Path]::GetPathRoot($destinationFullPath)
            if (-not [string]::IsNullOrWhiteSpace($pathRoot)) {
                $drive = [System.IO.DriveInfo]::new($pathRoot)
                if ($drive.IsReady) {
                    $requiredWithReserve = $totalRequired
                    if ($requiredWithReserve -le ([int64]::MaxValue - $MinimumFreeSpaceReserveBytes)) {
                        $requiredWithReserve += $MinimumFreeSpaceReserveBytes
                        if ([int64]$drive.AvailableFreeSpace -lt $requiredWithReserve) {
                            throw (
                                "Project archive requires at least $requiredWithReserve free bytes including reserve; " +
                                "only $($drive.AvailableFreeSpace) bytes are available."
                            )
                        }
                    }
                }
            }
        }
        catch [System.Management.Automation.RuntimeException] {
            throw
        }
        catch {
            Write-Verbose (
                "Unable to determine destination free space for '$DestinationRoot': " +
                $_.Exception.Message
            )
        }

        return [PSCustomObject]@{
            EntryCount = $zip.Entries.Count
            RequiredEntryCount = $requiredEntries.Count
            TotalRequiredBytes = $totalRequired
        }
    }
    finally {
        $zip.Dispose()
    }
}

function Expand-RenderKitProjectArchiveEntryBounded {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.Compression.ZipArchiveEntry]$Entry,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][int64]$ExpectedSize
    )

    if ($ExpectedSize -lt 0) {
        throw "Archive entry '$($Entry.FullName)' has a negative expected size."
    }
    if ([int64]$Entry.Length -ne $ExpectedSize) {
        throw (
            "Archive entry '$($Entry.FullName)' has $($Entry.Length) uncompressed bytes; " +
            "expected $ExpectedSize bytes."
        )
    }

    $parent = Split-Path -Path $DestinationPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent) -and
        -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $inputStream = $null
    $outputStream = $null
    $completed = $false
    try {
        $inputStream = $Entry.Open()
        $outputStream = [System.IO.File]::Open(
            $DestinationPath,
            [System.IO.FileMode]::Create,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        $buffer = New-Object byte[] (1MB)
        $written = [int64]0
        while (($read = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            if ($written -gt ($ExpectedSize - $read)) {
                throw "Archive entry '$($Entry.FullName)' expanded beyond its declared size."
            }
            $outputStream.Write($buffer, 0, $read)
            $written += $read
        }
        if ($written -ne $ExpectedSize) {
            throw "Archive entry '$($Entry.FullName)' expanded to $written bytes; expected $ExpectedSize bytes."
        }
        $outputStream.Flush()
        $completed = $true
    }
    finally {
        if ($outputStream) { $outputStream.Dispose() }
        if ($inputStream) { $inputStream.Dispose() }
        if (-not $completed -and (Test-Path -LiteralPath $DestinationPath -PathType Leaf)) {
            Remove-Item -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue
        }
    }
}
