function Get-RenderKitXmpSidecarCandidatePaths {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $resolvedPath = [IO.Path]::GetFullPath($Path)
    $specificPath = "$resolvedPath.xmp"
    $stemPath = [IO.Path]::ChangeExtension($resolvedPath, '.xmp')
    return @(
        @($specificPath, $stemPath) |
            Select-Object -Unique
    )
}

function Resolve-RenderKitXmpSidecar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $candidates = @(
        Get-RenderKitXmpSidecarCandidatePaths -Path $Path
    )
    $existing = @(
        $candidates |
            Where-Object {
                Test-Path -LiteralPath $_ -PathType Leaf
            }
    )
    return [PSCustomObject]@{
        Exists = $existing.Count -gt 0
        ExistingPaths = @($existing)
        EffectivePath = if ($existing.Count -gt 0) {
            [string]$existing[0]
        }
        else {
            [string]$candidates[-1]
        }
        CandidateCount = $candidates.Count
        ExistingCount = $existing.Count
    }
}

function Get-RenderKitXmpSidecarDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$MediaPath,

        [Parameter(Mandatory)]
        [int]$Precedence
    )

    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    $relativeName = [IO.Path]::GetFileName($file.FullName)
    return [PSCustomObject]@{
        Id = ConvertTo-RenderKitSha256Text `
            -Text ($file.FullName.ToLowerInvariant())
        FileName = $relativeName
        Convention = if (
            $file.FullName -ieq "$([IO.Path]::GetFullPath($MediaPath)).xmp"
        ) {
            'FullName'
        }
        else {
            'Stem'
        }
        Precedence = $Precedence
        SizeBytes = [int64]$file.Length
        LastWriteTimeUtc = $file.LastWriteTimeUtc.ToString('o')
    }
}

function ConvertTo-RenderKitXmpComparableJson {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return 'null'
    }
    if ($Value -is [datetime]) {
        return $Value.ToUniversalTime().ToString('o')
    }
    if ($Value -is [string] -or $Value -is [ValueType]) {
        return ([string]$Value).Trim()
    }
    return [string](
        $Value |
            ConvertTo-Json -Depth 50 -Compress
    )
}

function Test-RenderKitXmpValuesEqual {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [object]$Left,

        [AllowNull()]
        [object]$Right
    )

    return (
        ConvertTo-RenderKitXmpComparableJson -Value $Left
    ) -eq (
        ConvertTo-RenderKitXmpComparableJson -Value $Right
    )
}

function Get-RenderKitXmpSidecarProfileFields {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Raw
    )

    $fields = [ordered]@{}
    if (-not $Raw) {
        return $fields
    }
    $xmpRaw = [ordered]@{}
    foreach ($property in @($Raw.PSObject.Properties)) {
        if ([string]$property.Name -match '^XMP(?:-|:)') {
            $xmpRaw[[string]$property.Name] = $property.Value
        }
    }
    if ($xmpRaw.Count -eq 0) {
        return $fields
    }
    $xmpObject = [PSCustomObject]$xmpRaw
    Merge-RenderKitMetadataFieldBag `
        -Target $fields `
        -Source (
            ConvertFrom-RenderKitIptcMetadata -Raw $xmpObject
        )
    Merge-RenderKitMetadataFieldBag `
        -Target $fields `
        -Source (
            ConvertFrom-RenderKitDublinCoreXmpMetadata -Raw $xmpObject
        )
    return $fields
}

function Read-RenderKitXmpSidecarMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $selection = Resolve-RenderKitXmpSidecar -Path $Path
    if (-not [bool]$selection.Exists) {
        return [PSCustomObject]@{
            State = 'Absent'
            Fields = [ordered]@{}
            Conflicts = @()
            Sidecars = @()
            Raw = $null
            InternalEffectivePath = [string]$selection.EffectivePath
        }
    }

    $reader = Resolve-RenderKitExifToolReader
    if (-not [bool]$reader.Available) {
        return [PSCustomObject]@{
            State = 'Unavailable'
            Fields = [ordered]@{}
            Conflicts = @()
            Sidecars = @()
            Raw = $null
            InternalEffectivePath = [string]$selection.EffectivePath
            Error = 'ExifToolNotAvailable'
        }
    }

    $effectiveFields = [ordered]@{}
    $fieldSources = @{}
    $conflicts = New-Object System.Collections.Generic.List[object]
    $descriptors = New-Object System.Collections.Generic.List[object]
    $rawRecords = New-Object System.Collections.Generic.List[object]
    $invalid = $false
    $precedence = 0
    foreach ($sidecarPath in @($selection.ExistingPaths)) {
        $precedence++
        try {
            $read = Invoke-RenderKitExifToolMetadataRead `
                -Path $sidecarPath `
                -Reader $reader `
                -CommandPath ([string]$reader.CommandPath)
            $sidecarFields = Get-RenderKitXmpSidecarProfileFields `
                -Raw $read.Raw
            $descriptor = Get-RenderKitXmpSidecarDescriptor `
                -Path $sidecarPath `
                -MediaPath $Path `
                -Precedence $precedence
            $descriptors.Add($descriptor)
            $rawRecords.Add([PSCustomObject]@{
                SidecarId = [string]$descriptor.Id
                Fields = [PSCustomObject]$sidecarFields
                Backend = [string]$read.Backend
                Source = [string]$read.Source
            })
            foreach ($field in @($sidecarFields.Keys)) {
                if (-not $effectiveFields.Contains($field)) {
                    $effectiveFields[$field] = $sidecarFields[$field]
                    $fieldSources[$field] = [string]$descriptor.Id
                    continue
                }
                if (-not (Test-RenderKitXmpValuesEqual `
                        -Left $effectiveFields[$field] `
                        -Right $sidecarFields[$field])) {
                    $conflicts.Add([PSCustomObject]@{
                        Field = [string]$field
                        Kind = 'MultipleXmpSidecars'
                        Standard = 'XMP'
                        EffectiveSource = 'SidecarXmp'
                        Candidates = @(
                            [PSCustomObject]@{
                                Source = 'SidecarXmp'
                                SidecarId = $fieldSources[$field]
                                Value = $effectiveFields[$field]
                            },
                            [PSCustomObject]@{
                                Source = 'SidecarXmp'
                                SidecarId = [string]$descriptor.Id
                                Value = $sidecarFields[$field]
                            }
                        )
                    })
                }
            }
        }
        catch {
            $invalid = $true
            $descriptor = Get-RenderKitXmpSidecarDescriptor `
                -Path $sidecarPath `
                -MediaPath $Path `
                -Precedence $precedence
            $descriptors.Add($descriptor)
            $rawRecords.Add([PSCustomObject]@{
                SidecarId = [string]$descriptor.Id
                Error = $_.Exception.Message
            })
        }
    }

    $state = if ($invalid) {
        'Invalid'
    }
    elseif ($conflicts.Count -gt 0) {
        'Conflicting'
    }
    elseif ($effectiveFields.Count -eq 0) {
        'Absent'
    }
    else {
        'Sidecar'
    }
    return [PSCustomObject]@{
        State = $state
        Fields = $effectiveFields
        Conflicts = @($conflicts.ToArray())
        Sidecars = @($descriptors.ToArray())
        Raw = @($rawRecords.ToArray())
        InternalEffectivePath = [string]$selection.EffectivePath
        Error = $null
    }
}

function Merge-RenderKitXmpSidecarFields {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Fields,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.IDictionary]$EmbeddedFields,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Provenance,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Conflicts,

        [Parameter(Mandatory)]
        [object]$SidecarRead
    )

    foreach ($conflict in @($SidecarRead.Conflicts)) {
        $Conflicts.Add($conflict)
    }
    foreach ($field in @($SidecarRead.Fields.Keys)) {
        $sidecarValue = $SidecarRead.Fields[$field]
        $hasEmbedded = $EmbeddedFields.Contains($field)
        $embeddedValue = if ($hasEmbedded) {
            $EmbeddedFields[$field]
        }
        else {
            $null
        }
        if ($hasEmbedded -and
            -not (Test-RenderKitXmpValuesEqual `
                -Left $embeddedValue `
                -Right $sidecarValue)) {
            $Conflicts.Add([PSCustomObject]@{
                Field = [string]$field
                Kind = 'EmbeddedVsXmpSidecar'
                Standard = 'XMP'
                EffectiveSource = 'SidecarXmp'
                Candidates = @(
                    [PSCustomObject]@{
                        Source = 'EmbeddedXmp'
                        Value = $embeddedValue
                    },
                    [PSCustomObject]@{
                        Source = 'SidecarXmp'
                        Value = $sidecarValue
                    }
                )
            })
        }
        $Fields[$field] = $sidecarValue
        $Provenance[$field] = [PSCustomObject]@{
            EffectiveSource = 'SidecarXmp'
            EmbeddedValue = $embeddedValue
            SidecarValue = $sidecarValue
            Conflict = (
                $hasEmbedded -and
                -not (Test-RenderKitXmpValuesEqual `
                    -Left $embeddedValue `
                    -Right $sidecarValue)
            )
        }
    }
}

function Test-RenderKitXmpSidecarWrite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Metadata
    )

    $reader = Resolve-RenderKitExifToolReader
    if (-not [bool]$reader.Available) {
        throw 'ExifTool is unavailable for XMP sidecar verification.'
    }
    $read = Invoke-RenderKitExifToolMetadataRead `
        -Path $Path `
        -Reader $reader `
        -CommandPath ([string]$reader.CommandPath)
    $fields = ConvertFrom-RenderKitDublinCoreXmpMetadata -Raw $read.Raw
    foreach ($key in @($Metadata.Keys)) {
        $field = [string]$key
        if (-not $fields.Contains($field)) {
            if (Test-RenderKitMetadataValueIsEmpty -Value $Metadata[$key]) {
                continue
            }
            throw "XMP sidecar verification did not read field '$field' back."
        }
        $definition = Get-RenderKitDublinCoreXmpFieldDefinition `
            -Field $field
        $expected = $Metadata[$key]
        $actual = $fields[$field]
        if ([string]$definition.readStrategy -eq 'All') {
            $expected = @($expected | ForEach-Object { [string]$_ })
            $actual = @($actual | ForEach-Object { [string]$_ })
        }
        if (-not (Test-RenderKitXmpValuesEqual `
                -Left $expected `
                -Right $actual)) {
            throw "XMP sidecar verification failed for field '$field'."
        }
    }
    return [PSCustomObject]@{
        Fields = $fields
        Backend = [string]$read.Backend
        Source = [string]$read.Source
        ReaderPath = [string]$read.Path
    }
}

function Invoke-RenderKitXmpSidecarMetadataWrite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Metadata
    )

    $resolvedMediaPath = (
        Resolve-Path -LiteralPath $Path -ErrorAction Stop
    ).ProviderPath
    $definitions = @{}
    foreach ($key in @($Metadata.Keys)) {
        $definition = Get-RenderKitDublinCoreXmpFieldDefinition `
            -Field ([string]$key)
        if ($definition -and @($definition.writeTags).Count -gt 0) {
            $definitions[[string]$key] = $definition
        }
    }
    if ($definitions.Count -eq 0) {
        throw 'The metadata set contains no writable Dublin Core or XMP fields.'
    }
    $reader = Resolve-RenderKitExifToolReader
    if (-not [bool]$reader.Available) {
        throw 'ExifTool is unavailable for XMP sidecar writes.'
    }

    $selection = Resolve-RenderKitXmpSidecar -Path $resolvedMediaPath
    $targetPath = [IO.Path]::GetFullPath(
        [string]$selection.EffectivePath
    )
    $directory = Split-Path -Parent $targetPath
    $temporaryPath = Join-Path `
        -Path $directory `
        -ChildPath (
            '.{0}.renderkit-{1}.tmp.xmp' -f
                [IO.Path]::GetFileNameWithoutExtension($targetPath),
                [guid]::NewGuid().ToString('N')
        )
    $backupPath = Join-Path `
        -Path $directory `
        -ChildPath (
            '.{0}.renderkit-{1}.bak' -f
                [IO.Path]::GetFileName($targetPath),
                [guid]::NewGuid().ToString('N')
        )
    $lockHandle = Enter-RenderKitFileLock `
        -Path "$targetPath.renderkit-metadata" `
        -TimeoutMilliseconds 30000
    $targetExisted = Test-Path -LiteralPath $targetPath -PathType Leaf
    $replacementComplete = $false
    $preserveBackup = $false
    try {
        $arguments = New-Object System.Collections.Generic.List[string]
        if ($targetExisted) {
            [IO.File]::Copy($targetPath, $temporaryPath, $false)
            $arguments.Add('-overwrite_original')
            $arguments.Add('-P')
        }
        else {
            $arguments.Add('-o')
            $arguments.Add($temporaryPath)
        }
        foreach ($key in @($Metadata.Keys | Sort-Object)) {
            $field = [string]$key
            if (-not $definitions.ContainsKey($field)) {
                continue
            }
            $definition = $definitions[$field]
            foreach ($tag in @(
                $definition.writeTags |
                    ForEach-Object { [string]$_ }
            )) {
                Add-RenderKitExifToolTagWriteArguments `
                    -Arguments $arguments `
                    -Tag $tag `
                    -Value $Metadata[$key]
            }
        }
        $arguments.Add(
            $(if ($targetExisted) {
                $temporaryPath
            }
            else {
                $resolvedMediaPath
            })
        )
        $write = Invoke-RenderKitExifToolCommand `
            -Reader $reader `
            -Arguments @($arguments.ToArray())
        $output = @($write.Output) -join "`n"
        if ($output -notmatch
            '\b[1-9][0-9]*\s+image files?\s+(updated|created)\b') {
            throw "ExifTool did not confirm an XMP sidecar write: $output"
        }
        $candidate = Test-RenderKitXmpSidecarWrite `
            -Path $temporaryPath `
            -Metadata $Metadata

        if ($targetExisted) {
            try {
                [IO.File]::Replace(
                    $temporaryPath,
                    $targetPath,
                    $backupPath,
                    $true
                )
                $replacementComplete = $true
            }
            catch {
                [IO.File]::Move($targetPath, $backupPath)
                try {
                    [IO.File]::Move($temporaryPath, $targetPath)
                    $replacementComplete = $true
                }
                catch {
                    [IO.File]::Move($backupPath, $targetPath)
                    throw
                }
            }
        }
        else {
            [IO.File]::Move($temporaryPath, $targetPath)
            $replacementComplete = $true
        }
        $final = Test-RenderKitXmpSidecarWrite `
            -Path $targetPath `
            -Metadata $Metadata
        if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
            Remove-Item -LiteralPath $backupPath -Force
        }
        $descriptor = Get-RenderKitXmpSidecarDescriptor `
            -Path $targetPath `
            -MediaPath $resolvedMediaPath `
            -Precedence 1
        return [PSCustomObject]@{
            Adapter = 'ExifToolXmpSidecar'
            Backend = [string]$write.Backend
            BackendSource = [string]$write.Source
            BackendPath = [string]$write.Path
            Fields = @($definitions.Keys | Sort-Object)
            Verified = $true
            Created = -not $targetExisted
            Sidecar = $descriptor
            CandidateFields = $candidate.Fields
            FieldsRead = $final.Fields
        }
    }
    catch {
        $failure = $_
        if ($targetExisted -and $replacementComplete -and
            (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            try {
                [IO.File]::Replace(
                    $backupPath,
                    $targetPath,
                    $null,
                    $true
                )
            }
            catch {
                $preserveBackup = $true
                throw "XMP sidecar write failed and backup restoration also failed. Original error: $($failure.Exception.Message). Restore error: $($_.Exception.Message). Backup: '$backupPath'."
            }
        }
        elseif (-not $targetExisted -and $replacementComplete -and
            (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
            Remove-Item `
                -LiteralPath $targetPath `
                -Force `
                -ErrorAction SilentlyContinue
        }
        throw $failure
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item `
                -LiteralPath $temporaryPath `
                -Force `
                -ErrorAction SilentlyContinue
        }
        if (-not $preserveBackup -and
            (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            Remove-Item `
                -LiteralPath $backupPath `
                -Force `
                -ErrorAction SilentlyContinue
        }
        Exit-RenderKitFileLock -LockHandle $lockHandle
    }
}
