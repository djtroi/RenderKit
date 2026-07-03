function Get-RenderKitAudioContainerMetadataProfileMapPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('BWF', 'iXML', 'ID3', 'Matroska')]
        [string]$Profile,

        [string]$Path
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    $fileName = switch ($Profile) {
        'BWF' { 'bwf-field-map.json' }
        'iXML' { 'ixml-field-map.json' }
        'ID3' { 'id3-field-map.json' }
        'Matroska' { 'matroska-field-map.json' }
    }

    return Join-Path -Path $script:RenderKitModuleRoot `
        -ChildPath "src/Resources/Metadata/$fileName"
}

function Get-RenderKitAudioContainerMetadataProfileArtifactType {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('BWF', 'iXML', 'ID3', 'Matroska')]
        [string]$Profile
    )

    switch ($Profile) {
        'BWF' { 'BwfMetadataMap' }
        'iXML' { 'IxmlMetadataMap' }
        'ID3' { 'Id3MetadataMap' }
        'Matroska' { 'MatroskaMetadataMap' }
    }
}

function Test-RenderKitAudioContainerMetadataProfileMapSchema {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object]$Map,

        [Parameter(Mandatory)]
        [ValidateSet('BWF', 'iXML', 'ID3', 'Matroska')]
        [string]$Profile
    )

    $expectedArtifactType =
        Get-RenderKitAudioContainerMetadataProfileArtifactType -Profile $Profile
    if ([string]$Map.artifactType -ne $expectedArtifactType -or
        [string]$Map.profile -ne $Profile -or
        [string]::IsNullOrWhiteSpace([string]$Map.schemaVersion) -or
        [string]::IsNullOrWhiteSpace([string]$Map.standardVersion) -or
        -not $Map.adapterSettings -or
        -not $Map.fields -or
        -not $Map.writeCapability) {
        return $false
    }

    if (@('Available', 'Unavailable', 'NotImplemented') -notcontains
        [string]$Map.writeCapability.status) {
        return $false
    }
    if ([string]$Map.writeCapability.status -eq 'Available') {
        if ([string]::IsNullOrWhiteSpace(
                [string]$Map.writeCapability.adapter) -or
            -not $Map.writeFields) {
            return $false
        }
        $writeFieldNames = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
        foreach ($definition in @($Map.writeFields)) {
            if ([string]::IsNullOrWhiteSpace([string]$definition.field) -or
                [string]::IsNullOrWhiteSpace([string]$definition.target) -or
                [string]::IsNullOrWhiteSpace([string]$definition.valueType) -or
                -not $writeFieldNames.Add((
                    '{0}|{1}' -f
                        [string]$definition.field,
                        [string]$definition.target
                ))) {
                return $false
            }
        }
    }

    $fieldNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($definition in @($Map.fields)) {
        if ([string]::IsNullOrWhiteSpace([string]$definition.field) -or
            [string]::IsNullOrWhiteSpace([string]$definition.fieldType) -or
            [string]::IsNullOrWhiteSpace([string]$definition.converter) -or
            -not $definition.read -or
            -not $fieldNames.Add([string]$definition.field)) {
            return $false
        }

        foreach ($readDefinition in @($definition.read.PSObject.Properties)) {
            if ([string]::IsNullOrWhiteSpace([string]$readDefinition.Name) -or
                -not $readDefinition.Value.paths) {
                return $false
            }
        }
    }

    foreach ($definition in @($Map.unmappedFields)) {
        if ([string]::IsNullOrWhiteSpace([string]$definition.field) -or
            [string]::IsNullOrWhiteSpace([string]$definition.reason) -or
            -not $fieldNames.Add([string]$definition.field)) {
            return $false
        }
    }

    return $true
}

function Read-RenderKitAudioContainerMetadataProfileMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('BWF', 'iXML', 'ID3', 'Matroska')]
        [string]$Profile,

        [string]$Path,

        [switch]$Reload
    )

    $resolvedPath = Get-RenderKitAudioContainerMetadataProfileMapPath `
        -Profile $Profile `
        -Path $Path
    $cacheKey = "$Profile|$resolvedPath"
    if (-not $script:RenderKitAudioContainerMetadataProfileMapCache) {
        $script:RenderKitAudioContainerMetadataProfileMapCache = @{}
    }
    if (-not $Reload -and
        $script:RenderKitAudioContainerMetadataProfileMapCache.ContainsKey(
            $cacheKey
        )) {
        return $script:RenderKitAudioContainerMetadataProfileMapCache[
            $cacheKey
        ]
    }

    $map = Read-RenderKitJsonFile `
        -Path $resolvedPath `
        -MaximumBytes 2097152 `
        -Validator {
            param($value)
            Test-RenderKitAudioContainerMetadataProfileMapSchema `
                -Map $value `
                -Profile $Profile
        }

    Test-RenderKitArtifactCompatibility `
        -ArtifactType (
            Get-RenderKitAudioContainerMetadataProfileArtifactType `
                -Profile $Profile
        ) `
        -Version ([string]$map.schemaVersion) |
        Out-Null

    $script:RenderKitAudioContainerMetadataProfileMapCache[$cacheKey] = $map
    return $map
}

function Get-RenderKitNestedMetadataPropertyValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $current = $Object
    foreach ($segment in @($Path -split '\.')) {
        if ($null -eq $current) {
            return $null
        }

        if ($current -is [System.Collections.IDictionary]) {
            $key = @(
                $current.Keys |
                    Where-Object { [string]$_ -ieq $segment } |
                    Select-Object -First 1
            )
            if (-not $key) {
                return $null
            }
            $current = $current[$key[0]]
            continue
        }

        $property = @(
            $current.PSObject.Properties |
                Where-Object { $_.Name -ieq $segment } |
                Select-Object -First 1
        )
        if (-not $property) {
            return $null
        }
        $current = $property[0].Value
    }

    return $current
}

function Get-RenderKitAudioContainerMetadataSourceRoot {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Raw,

        [Parameter(Mandatory)]
        [string]$Adapter,

        [Parameter(Mandatory)]
        [object]$AdapterSettings,

        [Parameter(Mandatory)]
        [object]$ReadDefinition
    )

    if ($Adapter -eq 'MediaInfo') {
        if (-not $Raw -or -not $Raw.media) {
            return $null
        }
        return Get-RenderKitMetadataMediaInfoTrack `
            -MediaInfo $Raw `
            -Type ([string]$ReadDefinition.track)
    }

    if ($Raw -is [array]) {
        $Raw = $Raw | Select-Object -First 1
    }
    if (-not $Raw) {
        return $null
    }

    $rootPaths = @(
        $AdapterSettings.rootPaths |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($rootPaths.Count -eq 0) {
        return $Raw
    }
    foreach ($rootPath in $rootPaths) {
        $root = Get-RenderKitNestedMetadataPropertyValue `
            -Object $Raw `
            -Path $rootPath
        if (-not (Test-RenderKitMetadataValueIsEmpty -Value $root)) {
            return $root
        }
    }

    return $null
}

function Get-RenderKitAudioContainerMetadataRawValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Root,

        [Parameter(Mandatory)]
        [object]$AdapterSettings,

        [Parameter(Mandatory)]
        [object]$ReadDefinition,

        [Parameter(Mandatory)]
        [string]$Converter
    )

    if ($null -eq $Root) {
        return $null
    }

    $paths = @(
        $ReadDefinition.paths |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    $groups = @(
        $AdapterSettings.groups |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    if ($Converter -eq 'UInt64Pair') {
        $direct = Get-RenderKitNestedMetadataPropertyValue `
            -Object $Root `
            -Path $paths[0]
        if (-not (Test-RenderKitMetadataValueIsEmpty -Value $direct)) {
            return $direct
        }
        if ($paths.Count -lt 3) {
            return $null
        }
        $high = Get-RenderKitNestedMetadataPropertyValue `
            -Object $Root `
            -Path $paths[1]
        $low = Get-RenderKitNestedMetadataPropertyValue `
            -Object $Root `
            -Path $paths[2]
        if ($null -eq $high -or $null -eq $low) {
            return $null
        }
        return [PSCustomObject]@{
            High = $high
            Low = $low
        }
    }

    if ($groups.Count -gt 0) {
        foreach ($group in $groups) {
            foreach ($path in $paths) {
                $value = Get-RenderKitNestedMetadataPropertyValue `
                    -Object $Root `
                    -Path "${group}:$path"
                if (-not (Test-RenderKitMetadataValueIsEmpty -Value $value)) {
                    return $value
                }
            }
        }
    }

    foreach ($path in $paths) {
        $value = Get-RenderKitNestedMetadataPropertyValue `
            -Object $Root `
            -Path $path
        if (-not (Test-RenderKitMetadataValueIsEmpty -Value $value)) {
            return $value
        }
    }

    return $null
}

function ConvertTo-RenderKitAudioContainerMetadataFieldValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Converter
    )

    if ($null -eq $Value) {
        return $null
    }

    switch ($Converter) {
        'Integer' {
            return ConvertTo-RenderKitMetadataInt64 -Value $Value
        }
        'Float' {
            return ConvertTo-RenderKitMetadataNumber -Value $Value
        }
        'Boolean' {
            if ($Value -is [bool]) {
                return [bool]$Value
            }
            $text = ([string]$Value).Trim()
            if (@('1', 'true', 'yes', 'y', 'on') -contains $text.ToLowerInvariant()) {
                return $true
            }
            if (@('0', 'false', 'no', 'n', 'off') -contains $text.ToLowerInvariant()) {
                return $false
            }
            return $null
        }
        'Date' {
            $match = [regex]::Match(
                [string]$Value,
                '^(?<year>\d{4})[:-](?<month>\d{2})[:-](?<day>\d{2})'
            )
            if ($match.Success) {
                return '{0}-{1}-{2}' -f `
                    $match.Groups['year'].Value,
                    $match.Groups['month'].Value,
                    $match.Groups['day'].Value
            }
            return [string]$Value
        }
        'Time' {
            $match = [regex]::Match(
                [string]$Value,
                '(?:^|[ T])(?<hour>[0-2]\d):(?<minute>[0-5]\d):(?<second>[0-5]\d)(?:$|[.,+\-Z])'
            )
            if ($match.Success) {
                return '{0}:{1}:{2}' -f `
                    $match.Groups['hour'].Value,
                    $match.Groups['minute'].Value,
                    $match.Groups['second'].Value
            }
            return $null
        }
        'FractionNumerator' {
            $parts = @(([string]$Value) -split '/', 2)
            return ConvertTo-RenderKitMetadataInt64 -Value $parts[0]
        }
        'FractionDenominator' {
            $parts = @(([string]$Value) -split '/', 2)
            if ($parts.Count -lt 2) {
                return $null
            }
            return ConvertTo-RenderKitMetadataInt64 -Value $parts[1]
        }
        'ListString' {
            $values = New-Object System.Collections.Generic.List[string]
            $items = if ($Value -is [System.Collections.IEnumerable] -and
                -not ($Value -is [string])) {
                @($Value)
            }
            else {
                @($Value)
            }
            foreach ($item in $items) {
                if (-not [string]::IsNullOrWhiteSpace([string]$item)) {
                    $values.Add([string]$item)
                }
            }
            if ($values.Count -eq 0) {
                return $null
            }
            return ,([string[]]$values.ToArray())
        }
        'ListObject' {
            $items = if ($Value -is [System.Collections.IEnumerable] -and
                -not ($Value -is [string]) -and
                -not ($Value -is [System.Collections.IDictionary]) -and
                -not ($Value -is [PSCustomObject])) {
                @($Value)
            }
            else {
                @($Value)
            }
            return ,@($items)
        }
        'UInt64Pair' {
            if ($Value.PSObject.Properties['High']) {
                $high = [uint64](ConvertTo-RenderKitMetadataInt64 -Value $Value.High)
                $low = [uint64](ConvertTo-RenderKitMetadataInt64 -Value $Value.Low)
                return [uint64](($high -shl 32) -bor $low)
            }
            return [uint64](ConvertTo-RenderKitMetadataInt64 -Value $Value)
        }
        'TrackList' {
            $track = Get-RenderKitNestedMetadataPropertyValue `
                -Object $Value `
                -Path 'Track'
            if ($null -ne $track) {
                return ConvertTo-RenderKitAudioContainerMetadataFieldValue `
                    -Value $track `
                    -Converter 'ListObject'
            }
            return ConvertTo-RenderKitAudioContainerMetadataFieldValue `
                -Value $Value `
                -Converter 'ListObject'
        }
        'StereoMode' {
            $text = ([string]$Value).Trim().ToLowerInvariant()
            if ($text -match 'mono|2d') {
                return 'Mono'
            }
            if ($text -match 'side.by.side|left.right|right.left') {
                return 'LeftRight'
            }
            if ($text -match 'top.bottom|bottom.top') {
                return 'TopBottom'
            }
            if ($text -match 'anaglyph') {
                return 'Anaglyph'
            }
            if ($text -match 'separate|both eyes laced') {
                return 'SeparateStreams'
            }
            return 'Unknown'
        }
        'Object' {
            return $Value
        }
        default {
            $items = if ($Value -is [System.Collections.IEnumerable] -and
                -not ($Value -is [string]) -and
                -not ($Value -is [System.Collections.IDictionary])) {
                @($Value)
            }
            else {
                @($Value)
            }
            foreach ($item in $items) {
                if (-not (Test-RenderKitMetadataValueIsEmpty -Value $item)) {
                    return [string]$item
                }
            }
            return $null
        }
    }
}

function ConvertFrom-RenderKitAudioContainerMetadataProfile {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Raw,

        [Parameter(Mandatory)]
        [ValidateSet('BWF', 'iXML', 'ID3', 'Matroska')]
        [string]$Profile,

        [Parameter(Mandatory)]
        [ValidateSet('ExifTool', 'MediaInfo')]
        [string]$Adapter,

        [object]$Map
    )

    $fields = [ordered]@{}
    if (-not $Raw) {
        return $fields
    }
    if (-not $Map) {
        $Map = Read-RenderKitAudioContainerMetadataProfileMap `
            -Profile $Profile
    }

    $adapterSettingsProperty = @(
        $Map.adapterSettings.PSObject.Properties |
            Where-Object { $_.Name -ieq $Adapter } |
            Select-Object -First 1
    )
    if (-not $adapterSettingsProperty) {
        return $fields
    }
    $adapterSettings = $adapterSettingsProperty[0].Value

    foreach ($definition in @($Map.fields)) {
        $readProperty = @(
            $definition.read.PSObject.Properties |
                Where-Object { $_.Name -ieq $Adapter } |
                Select-Object -First 1
        )
        if (-not $readProperty) {
            continue
        }
        $readDefinition = $readProperty[0].Value
        $root = Get-RenderKitAudioContainerMetadataSourceRoot `
            -Raw $Raw `
            -Adapter $Adapter `
            -AdapterSettings $adapterSettings `
            -ReadDefinition $readDefinition
        $rawValue = Get-RenderKitAudioContainerMetadataRawValue `
            -Root $root `
            -AdapterSettings $adapterSettings `
            -ReadDefinition $readDefinition `
            -Converter ([string]$definition.converter)
        $value = ConvertTo-RenderKitAudioContainerMetadataFieldValue `
            -Value $rawValue `
            -Converter ([string]$definition.converter)
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name ([string]$definition.field) `
            -Value $value
    }

    return $fields
}

function Merge-RenderKitAudioContainerMetadataProfiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Fields,

        [AllowNull()]
        [object]$Raw,

        [Parameter(Mandatory)]
        [ValidateSet('ExifTool', 'MediaInfo')]
        [string]$Adapter
    )

    foreach ($profile in @('BWF', 'iXML', 'ID3', 'Matroska')) {
        Merge-RenderKitMetadataFieldBag `
            -Target $Fields `
            -Source (
                ConvertFrom-RenderKitAudioContainerMetadataProfile `
                    -Raw $Raw `
                    -Profile $profile `
                    -Adapter $Adapter
            )
    }
}
