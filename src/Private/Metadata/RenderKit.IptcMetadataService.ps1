function Get-RenderKitIptcMetadataMapPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Path
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return Join-Path -Path $script:RenderKitModuleRoot `
        -ChildPath 'src/Resources/Metadata/iptc-field-map.json'
}

function Test-RenderKitIptcMetadataMapSchema {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object]$Map
    )

    if ([string]$Map.artifactType -ne 'IptcMetadataMap') {
        return $false
    }
    if ([string]::IsNullOrWhiteSpace([string]$Map.schemaVersion) -or
        [string]::IsNullOrWhiteSpace([string]$Map.standardVersion) -or
        -not $Map.fields) {
        return $false
    }

    $fieldNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($definition in @($Map.fields)) {
        if ([string]::IsNullOrWhiteSpace([string]$definition.field) -or
            [string]::IsNullOrWhiteSpace([string]$definition.iptcPropertyId) -or
            -not $definition.readTags) {
            return $false
        }
        if (-not $fieldNames.Add([string]$definition.field)) {
            return $false
        }
    }

    return $true
}

function Read-RenderKitIptcMetadataMap {
    [CmdletBinding()]
    param(
        [string]$Path,
        [switch]$Reload
    )

    $resolvedPath = Get-RenderKitIptcMetadataMapPath -Path $Path
    if (-not $Reload -and
        $script:RenderKitIptcMetadataMapCache -and
        $script:RenderKitIptcMetadataMapCachePath -eq $resolvedPath) {
        return $script:RenderKitIptcMetadataMapCache
    }

    $map = Read-RenderKitJsonFile `
        -Path $resolvedPath `
        -MaximumBytes 1048576 `
        -Validator { param($value) Test-RenderKitIptcMetadataMapSchema -Map $value }

    Test-RenderKitArtifactCompatibility `
        -ArtifactType IptcMetadataMap `
        -Version ([string]$map.schemaVersion) |
        Out-Null

    $script:RenderKitIptcMetadataMapCache = $map
    $script:RenderKitIptcMetadataMapCachePath = $resolvedPath
    return $map
}

function Get-RenderKitIptcMetadataFieldDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Field,

        [object]$Map
    )

    if (-not $Map) {
        $Map = Read-RenderKitIptcMetadataMap
    }

    return @(
        $Map.fields |
            Where-Object { [string]$_.field -ieq $Field } |
            Select-Object -First 1
    )
}

function Get-RenderKitExactMetadataPropertyValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory)]
        [string[]]$Name
    )

    if ($null -eq $Object) {
        return $null
    }
    if ($Object -is [array]) {
        $Object = $Object | Select-Object -First 1
    }

    $properties = @($Object.PSObject.Properties)
    foreach ($candidate in $Name) {
        foreach ($property in $properties) {
            if ($property.Name -ieq $candidate -and
                -not (Test-RenderKitMetadataValueIsEmpty -Value $property.Value)) {
                return $property.Value
            }
        }
    }

    return $null
}

function ConvertTo-RenderKitIptcFieldValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [string]$FieldType
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($FieldType -eq 'List<Object>') {
        if ($Value -is [System.Collections.IEnumerable] -and
            -not ($Value -is [string]) -and
            -not ($Value -is [System.Collections.IDictionary])) {
            return ,@($Value)
        }
        return ,@($Value)
    }

    if ($FieldType -like 'List*') {
        $values = New-Object System.Collections.Generic.List[string]
        $inputValues = if ($Value -is [System.Collections.IEnumerable] -and
            -not ($Value -is [string])) {
            @($Value)
        }
        else {
            @($Value)
        }

        foreach ($item in $inputValues) {
            if (-not [string]::IsNullOrWhiteSpace([string]$item)) {
                $values.Add([string]$item)
            }
        }
        return ,([string[]]$values.ToArray())
    }

    if ($FieldType -eq 'Integer') {
        return ConvertTo-RenderKitMetadataInt64 -Value $Value
    }

    return $Value
}

function Get-RenderKitIptcControlledVocabularyDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [object]$Map
    )

    if (-not $Map) {
        $Map = Read-RenderKitIptcMetadataMap
    }
    return $Map.controlledVocabularies.PSObject.Properties |
        Where-Object { $_.Name -ieq $Name } |
        Select-Object -First 1 -ExpandProperty Value
}

function ConvertFrom-RenderKitIptcControlledVocabularyValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Vocabulary,

        [object]$Map
    )

    if (Test-RenderKitMetadataValueIsEmpty -Value $Value) {
        return $null
    }
    $definition = Get-RenderKitIptcControlledVocabularyDefinition `
        -Name $Vocabulary `
        -Map $Map
    if (-not $definition) {
        return $null
    }

    $text = ([string]$Value).Trim()
    foreach ($entry in @($definition.values)) {
        if ([string]$entry.value -ieq $text) {
            return [string]$entry.value
        }
        foreach ($uri in @($entry.uris | ForEach-Object { [string]$_ })) {
            if ($uri -ieq $text) {
                return [string]$entry.value
            }
        }
    }
    return $null
}

function ConvertTo-RenderKitIptcControlledVocabularyValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Vocabulary,

        [object]$Map
    )

    if (Test-RenderKitMetadataValueIsEmpty -Value $Value) {
        return $null
    }
    $definition = Get-RenderKitIptcControlledVocabularyDefinition `
        -Name $Vocabulary `
        -Map $Map
    if (-not $definition) {
        return $null
    }

    $text = ([string]$Value).Trim()
    foreach ($entry in @($definition.values)) {
        if ([string]$entry.value -ine $text) {
            continue
        }
        if ($entry.PSObject.Properties.Name -contains 'writeUri' -and
            $null -eq $entry.writeUri) {
            return $null
        }
        $writeUri = [string]$entry.writeUri
        if (-not [string]::IsNullOrWhiteSpace($writeUri)) {
            return $writeUri
        }
        return @($entry.uris | ForEach-Object { [string]$_ } |
            Select-Object -First 1)
    }
    return $null
}

function Get-RenderKitIptcSelectedStructureValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [object]$Definition,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Conflicts
    )

    $values = if ($Value -is [System.Collections.IEnumerable] -and
        -not ($Value -is [string]) -and
        -not ($Value -is [System.Collections.IDictionary])) {
        @($Value)
    }
    else {
        @($Value)
    }

    if ([bool]$Definition.requireSingleStructure -and $values.Count -ne 1) {
        $Conflicts.Add([PSCustomObject]@{
            Field = [string]$Definition.field
            Reason = 'AmbiguousStructure'
            CandidateCount = $values.Count
            Source = 'EmbeddedIPTC'
        })
        return $null
    }

    $hasStructuredValue = @(
        $values |
            Where-Object {
                $_ -is [System.Collections.IDictionary] -or
                (
                    $null -ne $_ -and
                    -not ($_ -is [string]) -and
                    -not ($_ -is [System.ValueType]) -and
                    @($_.PSObject.Properties).Count -gt 0
                )
            }
    ).Count -gt 0
    if (-not [string]::IsNullOrWhiteSpace([string]$Definition.selector) -and
        $hasStructuredValue) {
        $selected = New-Object System.Collections.Generic.List[object]
        foreach ($item in $values) {
            $candidate = Get-RenderKitExactMetadataPropertyValue `
                -Object $item `
                -Name @([string]$Definition.selector)
            if (-not (Test-RenderKitMetadataValueIsEmpty -Value $candidate)) {
                if ($candidate -is [System.Collections.IEnumerable] -and
                    -not ($candidate -is [string]) -and
                    -not ($candidate -is [System.Collections.IDictionary])) {
                    foreach ($entry in @($candidate)) {
                        $selected.Add($entry)
                    }
                }
                else {
                    $selected.Add($candidate)
                }
            }
        }
        $values = @($selected.ToArray())
    }

    if ([bool]$Definition.requireSingleValue -and $values.Count -ne 1) {
        $Conflicts.Add([PSCustomObject]@{
            Field = [string]$Definition.field
            Reason = 'AmbiguousValue'
            CandidateCount = $values.Count
            Source = 'EmbeddedIPTC'
        })
        return $null
    }

    if ($values.Count -eq 0) {
        return $null
    }
    if ([string]$Definition.fieldType -like 'List*') {
        return ,$values
    }
    return $values[0]
}

function ConvertFrom-RenderKitIptcMetadataDetailed {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Raw,

        [object]$Map
    )

    $fields = [ordered]@{}
    $provenance = [ordered]@{}
    $conflicts = New-Object System.Collections.Generic.List[object]
    if (-not $Raw) {
        return [PSCustomObject]@{
            Fields = $fields
            Provenance = $provenance
            Conflicts = @()
        }
    }
    if (-not $Map) {
        $Map = Read-RenderKitIptcMetadataMap
    }

    foreach ($definition in @($Map.fields)) {
        $rawValue = Get-RenderKitExactMetadataPropertyValue `
            -Object $Raw `
            -Name @($definition.readTags | ForEach-Object { [string]$_ })
        if (Test-RenderKitMetadataValueIsEmpty -Value $rawValue) {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$definition.selector) -or
            [bool]$definition.requireSingleStructure -or
            [bool]$definition.requireSingleValue) {
            $rawValue = Get-RenderKitIptcSelectedStructureValue `
                -Value $rawValue `
                -Definition $definition `
                -Conflicts $conflicts
        }

        if (-not [string]::IsNullOrWhiteSpace(
                [string]$definition.controlledVocabulary)) {
            $convertedVocabularyValue =
                ConvertFrom-RenderKitIptcControlledVocabularyValue `
                    -Value $rawValue `
                    -Vocabulary ([string]$definition.controlledVocabulary) `
                    -Map $Map
            if ($null -eq $convertedVocabularyValue -and
                -not (Test-RenderKitMetadataValueIsEmpty -Value $rawValue)) {
                $conflicts.Add([PSCustomObject]@{
                    Field = [string]$definition.field
                    Reason = 'UnknownControlledVocabularyValue'
                    Value = $rawValue
                    Source = 'EmbeddedIPTC'
                })
                continue
            }
            $rawValue = $convertedVocabularyValue
        }

        $value = ConvertTo-RenderKitIptcFieldValue `
            -Value $rawValue `
            -FieldType ([string]$definition.fieldType)
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name ([string]$definition.field) `
            -Value $value
        if ($fields.Contains([string]$definition.field)) {
            $provenance[[string]$definition.field] = [PSCustomObject]@{
                EffectiveSource = 'EmbeddedIPTC'
                Standard = if ([string]$definition.profile -eq 'Extension') {
                    'IPTC Extension'
                } else {
                    'IPTC Core'
                }
                PropertyId = [string]$definition.iptcPropertyId
                ReadTags = @($definition.readTags |
                    ForEach-Object { [string]$_ })
            }
        }
    }

    return [PSCustomObject]@{
        Fields = $fields
        Provenance = $provenance
        Conflicts = @($conflicts.ToArray())
    }
}

function ConvertFrom-RenderKitIptcMetadata {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Raw,

        [object]$Map
    )

    return (ConvertFrom-RenderKitIptcMetadataDetailed `
        -Raw $Raw `
        -Map $Map).Fields
}
