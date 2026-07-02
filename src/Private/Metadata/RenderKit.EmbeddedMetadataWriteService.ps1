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

        [object]$Map
    )

    if (-not $Map) {
        $Map = Read-RenderKitEmbeddedMetadataWriteMap
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
        [System.Collections.IDictionary]$Metadata
    )

    $route = Resolve-RenderKitMetadataAdapterRoute -Path $Path
    $exifToolReader = Resolve-RenderKitExifToolReader
    $map = Read-RenderKitEmbeddedMetadataWriteMap
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($key in @($Metadata.Keys | Sort-Object)) {
        $field = [string]$key
        $value = $Metadata[$key]
        $capability = Get-RenderKitEmbeddedMetadataWriteCapability `
            -Field $field `
            -MediaKind ([string]$route.MediaKind) `
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
