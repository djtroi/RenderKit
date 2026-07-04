function Get-RenderKitEmbeddedMetadataWriteMapPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Path
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return Join-Path -Path $script:RenderKitModuleRoot `
        -ChildPath 'src/Resources/Metadata/embedded-write-map.json'
}

function Test-RenderKitEmbeddedMetadataWriteMapSchema {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object]$Map
    )

    if ([string]$Map.artifactType -ne 'MetadataEmbeddedWriteMap') {
        return $false
    }
    if ([string]::IsNullOrWhiteSpace([string]$Map.schemaVersion)) {
        return $false
    }
    if (-not $Map.fields) {
        return $false
    }
    return $true
}

function Read-RenderKitEmbeddedMetadataWriteMap {
    [CmdletBinding()]
    param(
        [string]$Path,
        [switch]$Reload
    )

    $resolvedPath = Get-RenderKitEmbeddedMetadataWriteMapPath -Path $Path
    if (-not $Reload -and
        $script:RenderKitEmbeddedMetadataWriteMapCache -and
        $script:RenderKitEmbeddedMetadataWriteMapCachePath -eq $resolvedPath) {
        return $script:RenderKitEmbeddedMetadataWriteMapCache
    }

    $map = Read-RenderKitJsonFile `
        -Path $resolvedPath `
        -MaximumBytes 1048576 `
        -Validator { param($value) Test-RenderKitEmbeddedMetadataWriteMapSchema -Map $value }

    Test-RenderKitArtifactCompatibility `
        -ArtifactType MetadataEmbeddedWriteMap `
        -Version ([string]$map.schemaVersion) |
        Out-Null

    $script:RenderKitEmbeddedMetadataWriteMapCache = $map
    $script:RenderKitEmbeddedMetadataWriteMapCachePath = $resolvedPath
    return $map
}

function Get-RenderKitEmbeddedMetadataWriteCapability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Field,

        [string]$MediaKind,

        [string]$Path,

        [object]$Map
    )

    if (-not $Map) {
        $Map = Read-RenderKitEmbeddedMetadataWriteMap
    }

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        $riffCapability =
            Get-RenderKitRiffEmbeddedMetadataWriteCapability `
                -Field $Field `
                -Path $Path
        if ($riffCapability) {
            return $riffCapability
        }

        $mkvToolNixCapability =
            Get-RenderKitMkvToolNixEmbeddedMetadataWriteCapability `
                -Field $Field `
                -Path $Path
        if ($mkvToolNixCapability) {
            return $mkvToolNixCapability
        }

        $tagLibCapability =
            Get-RenderKitTagLibSharpEmbeddedMetadataWriteCapability `
                -Field $Field `
                -Path $Path
        if ($tagLibCapability) {
            return $tagLibCapability
        }
    }

    $profileTags = New-Object System.Collections.Generic.List[string]
    $profileStandards = New-Object System.Collections.Generic.List[string]
    $profileTagSet = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $profileFieldType = $null
    $iptcDefinition = $null

    $dublinCoreDefinition = Get-RenderKitDublinCoreXmpFieldDefinition -Field $Field
    if ($dublinCoreDefinition -and @($dublinCoreDefinition.writeTags).Count -gt 0) {
        foreach ($tag in @($dublinCoreDefinition.writeTags)) {
            if ($profileTagSet.Add([string]$tag)) {
                $profileTags.Add([string]$tag)
            }
        }
        $profileStandards.Add('DublinCoreXmp')
        $profileFieldType = [string]$dublinCoreDefinition.fieldType
    }

    if ([string]$MediaKind -ieq 'Image') {
        $iptcDefinition = Get-RenderKitIptcMetadataFieldDefinition -Field $Field
        if ($iptcDefinition -and @($iptcDefinition.writeTags).Count -gt 0) {
            foreach ($tag in @($iptcDefinition.writeTags)) {
                if ($profileTagSet.Add([string]$tag)) {
                    $profileTags.Add([string]$tag)
                }
            }
            $profileStandards.Add('IPTC')
            if ([string]::IsNullOrWhiteSpace($profileFieldType)) {
                $profileFieldType = [string]$iptcDefinition.fieldType
            }
        }
    }

    if ($profileTags.Count -gt 0) {
        return [PSCustomObject]@{
            field = $Field
            adapter = 'ExifTool'
            tags = @($profileTags.ToArray())
            mediaKinds = if ([string]::IsNullOrWhiteSpace($MediaKind)) {
                @('All')
            } else {
                @($MediaKind)
            }
            fieldType = $profileFieldType
            standards = @($profileStandards.ToArray())
            writeMode = if ($iptcDefinition) {
                [string]$iptcDefinition.writeMode
            } else {
                $null
            }
            structureMembers = if ($iptcDefinition) {
                $iptcDefinition.structureMembers
            } else {
                $null
            }
            controlledVocabulary = if ($iptcDefinition) {
                [string]$iptcDefinition.controlledVocabulary
            } else {
                $null
            }
        }
    }

    $capability = @(
        $Map.fields |
            Where-Object { [string]$_.field -ieq $Field } |
            Select-Object -First 1
    )
    if (-not $capability) {
        return $null
    }

    $mediaKinds = @($capability.mediaKinds | ForEach-Object { [string]$_ })
    if ($mediaKinds.Count -gt 0 -and
        $mediaKinds -notcontains 'All' -and
        -not [string]::IsNullOrWhiteSpace($MediaKind) -and
        $mediaKinds -notcontains $MediaKind) {
        return $null
    }

    return $capability
}

function ConvertTo-RenderKitExifToolValue {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($Value -is [datetime]) {
        return $Value.ToString('yyyy:MM:dd HH:mm:ss')
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        return (@($Value | ForEach-Object { [string]$_ }) -join ', ')
    }
    return [string]$Value
}

function Add-RenderKitExifToolTagWriteArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[string]]$Arguments,

        [Parameter(Mandatory)]
        [string]$Tag,

        [AllowNull()]
        [object]$Value
    )

    $values = New-Object System.Collections.Generic.List[object]
    if ($Value -is [System.Collections.IEnumerable] -and
        -not ($Value -is [string])) {
        foreach ($item in @($Value)) {
            $values.Add($item)
        }
    }
    else {
        $values.Add($Value)
    }

    for ($index = 0; $index -lt $values.Count; $index++) {
        $operator = if ($index -eq 0) { '=' } else { '+=' }
        $Arguments.Add((
            '-{0}{1}{2}' -f
                $Tag,
                $operator,
                (ConvertTo-RenderKitExifToolValue -Value $values[$index])
        ))
    }
}

function ConvertTo-RenderKitIptcStructureObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Value,

        [AllowNull()]
        [object]$MemberMap
    )

    $result = [ordered]@{}
    $properties = if ($Value -is [System.Collections.IDictionary]) {
        @($Value.Keys | ForEach-Object {
            [PSCustomObject]@{
                Name = [string]$_
                Value = $Value[$_]
            }
        })
    }
    else {
        @($Value.PSObject.Properties)
    }

    foreach ($property in $properties) {
        $name = [string]$property.Name
        $targetName = $name
        if ($MemberMap) {
            $mapped = @(
                $MemberMap.PSObject.Properties |
                    Where-Object { $_.Name -ieq $name } |
                    Select-Object -First 1
            )
            if ($mapped) {
                $targetName = [string]$mapped.Value
            }
            else {
                $knownTarget = @(
                    $MemberMap.PSObject.Properties |
                        Where-Object {
                            [string]$_.Value -ieq $name
                        } |
                        Select-Object -First 1
                )
                if ($knownTarget) {
                    $targetName = [string]$knownTarget.Value
                }
                else {
                    throw "IPTC structure member '$name' is not defined by the profile."
                }
            }
        }
        if ($targetName -notmatch '^[A-Za-z][A-Za-z0-9]*$') {
            throw "IPTC structure member '$name' is not supported."
        }
        if (-not (Test-RenderKitMetadataValueIsEmpty -Value $property.Value)) {
            $result[$targetName] = $property.Value
        }
    }
    return [PSCustomObject]$result
}

function Invoke-RenderKitStructuredEmbeddedMetadataWrite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Tag,

        [AllowNull()]
        [object]$Value,

        [AllowNull()]
        [object]$MemberMap,

        [Parameter(Mandatory)]
        [object]$Reader
    )

    $values = if ($Value -is [System.Collections.IEnumerable] -and
        -not ($Value -is [string]) -and
        -not ($Value -is [System.Collections.IDictionary])) {
        @($Value)
    }
    else {
        @($Value)
    }
    $structures = @(
        $values |
            ForEach-Object {
                ConvertTo-RenderKitIptcStructureObject `
                    -Value $_ `
                    -MemberMap $MemberMap
            }
    )
    $payloadRecord = [ordered]@{
        SourceFile = [System.IO.Path]::GetFullPath($Path)
    }
    $payloadRecord[$Tag] = @($structures)
    $payload = @([PSCustomObject]$payloadRecord)
    $temporaryPath = Join-Path `
        -Path ([System.IO.Path]::GetTempPath()) `
        -ChildPath ('renderkit-iptc-{0}.json' -f
            [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText(
            $temporaryPath,
            ($payload | ConvertTo-Json -Depth 50),
            [System.Text.UTF8Encoding]::new($false)
        )
        return Invoke-RenderKitExifToolCommand `
            -Reader $Reader `
            -Arguments @(
                '-overwrite_original',
                '-P',
                '-struct',
                "-json=$temporaryPath",
                $Path
            )
    }
    finally {
        Remove-Item `
            -LiteralPath $temporaryPath `
            -Force `
            -ErrorAction SilentlyContinue
    }
}

function Invoke-RenderKitEmbeddedMetadataWrite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Metadata,

        [switch]$PreferXmpSidecar
    )

    $route = Resolve-RenderKitMetadataAdapterRoute -Path $Path
    $exifToolReader = Resolve-RenderKitExifToolReader
    $map = Read-RenderKitEmbeddedMetadataWriteMap
    $results = New-Object System.Collections.Generic.List[object]

    $xmpSidecarSelection = Resolve-RenderKitXmpSidecar -Path $Path
    $useXmpSidecar = [bool]$PreferXmpSidecar -or
        [bool]$xmpSidecarSelection.Exists
    $xmpSidecarMetadata = [ordered]@{}
    $xmpSidecarDefinitions = @{}
    $xmpSidecarFieldSet =
        [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
    if ($useXmpSidecar) {
        foreach ($key in @($Metadata.Keys | Sort-Object)) {
            $field = [string]$key
            $definition =
                Get-RenderKitDublinCoreXmpFieldDefinition `
                    -Field $field
            if (-not $definition -or
                @($definition.writeTags).Count -eq 0) {
                continue
            }
            $xmpSidecarMetadata[$field] = $Metadata[$key]
            $xmpSidecarDefinitions[$field] = $definition
            [void]$xmpSidecarFieldSet.Add($field)
        }
    }

    if ($xmpSidecarMetadata.Count -gt 0) {
        try {
            $sidecarWrite = Invoke-RenderKitXmpSidecarMetadataWrite `
                -Path $Path `
                -Metadata $xmpSidecarMetadata
            foreach ($field in @($xmpSidecarMetadata.Keys)) {
                $definition =
                    $xmpSidecarDefinitions[[string]$field]
                $results.Add([PSCustomObject]@{
                    Field = [string]$field
                    Embedded = $false
                    Sidecar = $true
                    Status = 'Written'
                    Reason = $null
                    Adapter = 'ExifToolXmpSidecar'
                    Tags = @($definition.writeTags)
                    Backend = [string]$sidecarWrite.Backend
                    BackendSource =
                        [string]$sidecarWrite.BackendSource
                    BackendPath = [string]$sidecarWrite.BackendPath
                    FallbackErrors = @()
                    Verified = [bool]$sidecarWrite.Verified
                    SidecarDescriptor = $sidecarWrite.Sidecar
                })
            }
        }
        catch {
            foreach ($field in @($xmpSidecarMetadata.Keys)) {
                $definition =
                    $xmpSidecarDefinitions[[string]$field]
                $results.Add([PSCustomObject]@{
                    Field = [string]$field
                    Embedded = $false
                    Sidecar = $true
                    Status = 'Failed'
                    Reason = $_.Exception.Message
                    Adapter = 'ExifToolXmpSidecar'
                    Tags = @($definition.writeTags)
                })
            }
        }
    }

    $riffMetadata = [ordered]@{}
    $riffCapabilities = @{}
    foreach ($key in @($Metadata.Keys | Sort-Object)) {
        $field = [string]$key
        if ($xmpSidecarFieldSet.Contains($field)) {
            continue
        }
        $capability = Get-RenderKitEmbeddedMetadataWriteCapability `
            -Field $field `
            -MediaKind ([string]$route.MediaKind) `
            -Path $Path `
            -Map $map
        if ($capability -and
            [string]$capability.adapter -eq 'RenderKitRiff') {
            $riffMetadata[$field] = $Metadata[$key]
            $riffCapabilities[$field] = $capability
        }
    }

    if ($riffMetadata.Count -gt 0) {
        try {
            $riffWrite = Invoke-RenderKitRiffMetadataWrite `
                -Path $Path `
                -Metadata $riffMetadata
            foreach ($field in @($riffMetadata.Keys)) {
                $capability = $riffCapabilities[[string]$field]
                $results.Add([PSCustomObject]@{
                    Field = [string]$field
                    Embedded = $true
                    Status = 'Written'
                    Reason = $null
                    Adapter = 'RenderKitRiff'
                    Tags = @($capability.tags)
                    Backend = [string]$riffWrite.Backend
                    BackendSource = 'BuiltIn'
                    BackendPath = $null
                    FallbackErrors = @()
                    Verified = [bool]$riffWrite.Verified
                    Chunks = @($riffWrite.Chunks)
                })
            }
        }
        catch {
            foreach ($field in @($riffMetadata.Keys)) {
                $capability = $riffCapabilities[[string]$field]
                $results.Add([PSCustomObject]@{
                    Field = [string]$field
                    Embedded = $false
                    Status = 'Failed'
                    Reason = $_.Exception.Message
                    Adapter = 'RenderKitRiff'
                    Tags = @($capability.tags)
                })
            }
        }
    }

    $tagLibMetadata = [ordered]@{}
    $tagLibCapabilities = @{}
    foreach ($key in @($Metadata.Keys | Sort-Object)) {
        $field = [string]$key
        if ($xmpSidecarFieldSet.Contains($field)) {
            continue
        }
        $capability = Get-RenderKitEmbeddedMetadataWriteCapability `
            -Field $field `
            -MediaKind ([string]$route.MediaKind) `
            -Path $Path `
            -Map $map
        if ($capability -and
            [string]$capability.adapter -eq 'TagLibSharp') {
            $tagLibMetadata[$field] = $Metadata[$key]
            $tagLibCapabilities[$field] = $capability
        }
    }

    if ($tagLibMetadata.Count -gt 0) {
        try {
            $tagLibWrite = Invoke-RenderKitTagLibSharpMetadataWrite `
                -Path $Path `
                -Metadata $tagLibMetadata
            foreach ($field in @($tagLibMetadata.Keys)) {
                $capability = $tagLibCapabilities[[string]$field]
                $results.Add([PSCustomObject]@{
                    Field = [string]$field
                    Embedded = $true
                    Status = 'Written'
                    Reason = $null
                    Adapter = 'TagLibSharp'
                    Tags = @($capability.tags)
                    Backend = [string]$tagLibWrite.Backend
                    BackendSource = [string]$tagLibWrite.BackendSource
                    BackendPath = [string]$tagLibWrite.BackendPath
                    BackendVersion = [string]$tagLibWrite.BackendVersion
                    FallbackErrors = @()
                    Verified = [bool]$tagLibWrite.Verified
                    TagVersion = $tagLibWrite.TagVersion
                })
            }
        }
        catch {
            foreach ($field in @($tagLibMetadata.Keys)) {
                $capability = $tagLibCapabilities[[string]$field]
                $results.Add([PSCustomObject]@{
                    Field = [string]$field
                    Embedded = $false
                    Status = 'Failed'
                    Reason = $_.Exception.Message
                    Adapter = 'TagLibSharp'
                    Tags = @($capability.tags)
                })
            }
        }
    }

    $mkvToolNixMetadata = [ordered]@{}
    $mkvToolNixCapabilities = @{}
    foreach ($key in @($Metadata.Keys | Sort-Object)) {
        $field = [string]$key
        if ($xmpSidecarFieldSet.Contains($field)) {
            continue
        }
        $capability = Get-RenderKitEmbeddedMetadataWriteCapability `
            -Field $field `
            -MediaKind ([string]$route.MediaKind) `
            -Path $Path `
            -Map $map
        if ($capability -and
            [string]$capability.adapter -eq 'MkvToolNix') {
            $mkvToolNixMetadata[$field] = $Metadata[$key]
            $mkvToolNixCapabilities[$field] = $capability
        }
    }

    if ($mkvToolNixMetadata.Count -gt 0) {
        try {
            $mkvToolNixWrite =
                Invoke-RenderKitMkvToolNixMetadataWrite `
                    -Path $Path `
                    -Metadata $mkvToolNixMetadata
            foreach ($field in @($mkvToolNixMetadata.Keys)) {
                $capability =
                    $mkvToolNixCapabilities[[string]$field]
                $results.Add([PSCustomObject]@{
                    Field = [string]$field
                    Embedded = $true
                    Status = 'Written'
                    Reason = $null
                    Adapter = 'MkvToolNix'
                    Tags = @($capability.tags)
                    Backend = [string]$mkvToolNixWrite.Backend
                    BackendSource =
                        [string]$mkvToolNixWrite.BackendSource
                    BackendPath =
                        [string]$mkvToolNixWrite.BackendPath
                    BackendVersion =
                        [string]$mkvToolNixWrite.BackendVersion
                    FallbackErrors = @()
                    Verified = [bool]$mkvToolNixWrite.Verified
                    ChapterCount = $mkvToolNixWrite.ChapterCount
                })
            }
        }
        catch {
            foreach ($field in @($mkvToolNixMetadata.Keys)) {
                $capability =
                    $mkvToolNixCapabilities[[string]$field]
                $results.Add([PSCustomObject]@{
                    Field = [string]$field
                    Embedded = $false
                    Status = 'Failed'
                    Reason = $_.Exception.Message
                    Adapter = 'MkvToolNix'
                    Tags = @($capability.tags)
                })
            }
        }
    }

    foreach ($key in @($Metadata.Keys | Sort-Object)) {
        $field = [string]$key
        if ($xmpSidecarFieldSet.Contains($field)) {
            continue
        }
        $value = $Metadata[$key]
        $capability = Get-RenderKitEmbeddedMetadataWriteCapability `
            -Field $field `
            -MediaKind ([string]$route.MediaKind) `
            -Path $Path `
            -Map $map
        if (-not $capability) {
            $results.Add([PSCustomObject]@{
                Field = $field
                Embedded = $false
                Status = 'Skipped'
                Reason = 'NoEmbeddedWriteCapability'
                Adapter = $null
                Tags = @()
            })
            continue
        }
        if ([string]$capability.adapter -in @(
                'RenderKitRiff',
                'TagLibSharp',
                'MkvToolNix'
            )) {
            continue
        }
        if (-not [bool]$exifToolReader.Available) {
            $results.Add([PSCustomObject]@{
                Field = $field
                Embedded = $false
                Status = 'Skipped'
                Reason = 'ExifToolNotAvailable'
                Adapter = 'ExifTool'
                Tags = @($capability.tags)
            })
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace(
                [string]$capability.controlledVocabulary)) {
            $convertedValue = ConvertTo-RenderKitIptcControlledVocabularyValue `
                -Value $value `
                -Vocabulary ([string]$capability.controlledVocabulary)
            if ($null -eq $convertedValue) {
                $results.Add([PSCustomObject]@{
                    Field = $field
                    Embedded = $false
                    Status = 'Skipped'
                    Reason = 'ControlledVocabularyValueNotWritable'
                    Adapter = 'ExifTool'
                    Tags = @($capability.tags)
                })
                continue
            }
            $value = $convertedValue
        }

        $arguments = New-Object System.Collections.Generic.List[string]
        $arguments.Add('-overwrite_original')
        $arguments.Add('-P')
        foreach ($tag in @($capability.tags | ForEach-Object { [string]$_ })) {
            Add-RenderKitExifToolTagWriteArguments `
                -Arguments $arguments `
                -Tag $tag `
                -Value $value
        }
        $arguments.Add($Path)

        try {
            $writeResult = if ([string]$capability.writeMode -eq 'Structure') {
                Invoke-RenderKitStructuredEmbeddedMetadataWrite `
                    -Path $Path `
                    -Tag ([string]@($capability.tags)[0]) `
                    -Value $value `
                    -MemberMap $capability.structureMembers `
                    -Reader $exifToolReader
            }
            else {
                Invoke-RenderKitExifToolCommand `
                    -Reader $exifToolReader `
                    -Arguments @($arguments.ToArray())
            }
            $writeOutput = @($writeResult.Output) -join "`n"
            if ($writeOutput -notmatch
                '\b[1-9][0-9]*\s+image files?\s+(updated|created)\b') {
                throw "ExifTool did not confirm an updated file: $writeOutput"
            }
            $results.Add([PSCustomObject]@{
                Field = $field
                Embedded = $true
                Status = 'Written'
                Reason = $null
                Adapter = 'ExifTool'
                Tags = @($capability.tags)
                Backend = [string]$writeResult.Backend
                BackendSource = [string]$writeResult.Source
                BackendPath = [string]$writeResult.Path
                FallbackErrors = @($writeResult.Errors)
            })
        }
        catch {
            $results.Add([PSCustomObject]@{
                Field = $field
                Embedded = $false
                Status = 'Failed'
                Reason = $_.Exception.Message
                Adapter = 'ExifTool'
                Tags = @($capability.tags)
            })
        }
    }

    return @($results.ToArray())
}
