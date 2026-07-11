function Get-RenderKitDublinCoreXmpMapPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Path
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return Join-Path -Path $script:RenderKitModuleRoot `
        -ChildPath 'src/Resources/Metadata/dublin-core-xmp-map.json'
}

function Test-RenderKitDublinCoreXmpMapSchema {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object]$Map
    )

    if ([string]$Map.artifactType -ne 'DublinCoreXmpMap' -or
        [string]$Map.standardVersion -ne '1.1' -or
        [string]::IsNullOrWhiteSpace([string]$Map.schemaVersion) -or
        -not $Map.fields -or
        -not $Map.xmpProfiles -or
        -not $Map.qualifiedTerms -or
        -not $Map.unmappedElements) {
        return $false
    }

    $dcElements = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $fieldNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    foreach ($definition in @($Map.fields)) {
        if ([string]::IsNullOrWhiteSpace([string]$definition.field) -or
            [string]::IsNullOrWhiteSpace([string]$definition.dcElement) -or
            [string]::IsNullOrWhiteSpace([string]$definition.readStrategy) -or
            -not $definition.readTags -or
            -not $definition.writeTags) {
            return $false
        }
        if (-not $fieldNames.Add([string]$definition.field) -or
            -not $dcElements.Add([string]$definition.dcElement)) {
            return $false
        }
    }

    foreach ($definition in @($Map.unmappedElements)) {
        if ([string]::IsNullOrWhiteSpace([string]$definition.dcElement) -or
            [string]::IsNullOrWhiteSpace([string]$definition.reason) -or
            -not $dcElements.Add([string]$definition.dcElement)) {
            return $false
        }
    }

    foreach ($profile in @($Map.xmpProfiles)) {
        if ([string]::IsNullOrWhiteSpace([string]$profile.profile) -or
            [string]::IsNullOrWhiteSpace([string]$profile.namespace) -or
            [string]::IsNullOrWhiteSpace(
                [string]$profile.namespaceUri
            ) -or
            $null -eq $profile.fields -or
            $null -eq $profile.unmappedProperties) {
            return $false
        }
        foreach ($definition in @($profile.fields)) {
            if ([string]::IsNullOrWhiteSpace(
                    [string]$definition.field) -or
                [string]::IsNullOrWhiteSpace(
                    [string]$definition.property) -or
                [string]::IsNullOrWhiteSpace(
                    [string]$definition.readStrategy) -or
                -not $definition.readTags -or
                -not $definition.writeTags -or
                -not $fieldNames.Add([string]$definition.field)) {
                return $false
            }
        }
        foreach ($unmapped in @($profile.unmappedProperties)) {
            if ([string]::IsNullOrWhiteSpace(
                    [string]$unmapped.property) -or
                [string]::IsNullOrWhiteSpace(
                    [string]$unmapped.reason)) {
                return $false
            }
        }
    }
    foreach ($term in @($Map.qualifiedTerms)) {
        if ([string]::IsNullOrWhiteSpace([string]$term.term) -or
            [string]::IsNullOrWhiteSpace(
                [string]$term.namespaceUri) -or
            [string]::IsNullOrWhiteSpace([string]$term.status) -or
            [string]::IsNullOrWhiteSpace([string]$term.reason)) {
            return $false
        }
    }

    return $dcElements.Count -eq 15
}

function Read-RenderKitDublinCoreXmpMap {
    [CmdletBinding()]
    param(
        [string]$Path,
        [switch]$Reload
    )

    $resolvedPath = Get-RenderKitDublinCoreXmpMapPath -Path $Path
    if (-not $Reload -and
        $script:RenderKitDublinCoreXmpMapCache -and
        $script:RenderKitDublinCoreXmpMapCachePath -eq $resolvedPath) {
        return $script:RenderKitDublinCoreXmpMapCache
    }

    $map = Read-RenderKitJsonFile `
        -Path $resolvedPath `
        -MaximumBytes 1048576 `
        -Validator { param($value) Test-RenderKitDublinCoreXmpMapSchema -Map $value }

    Test-RenderKitArtifactCompatibility `
        -ArtifactType DublinCoreXmpMap `
        -Version ([string]$map.schemaVersion) |
        Out-Null

    $script:RenderKitDublinCoreXmpMapCache = $map
    $script:RenderKitDublinCoreXmpMapCachePath = $resolvedPath
    return $map
}

function Get-RenderKitDublinCoreXmpFieldDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Field,

        [object]$Map
    )

    if (-not $Map) {
        $Map = Read-RenderKitDublinCoreXmpMap
    }

    return @(
        @($Map.fields) +
            @(
                $Map.xmpProfiles |
                    ForEach-Object { @($_.fields) }
            ) |
            Where-Object { [string]$_.field -ieq $Field } |
            Select-Object -First 1
    )
}

function Get-RenderKitDublinCoreXmpFieldDefinitions {
    [CmdletBinding()]
    param(
        [object]$Map
    )

    if (-not $Map) {
        $Map = Read-RenderKitDublinCoreXmpMap
    }
    return @(
        @($Map.fields) +
            @(
                $Map.xmpProfiles |
                    ForEach-Object { @($_.fields) }
            )
    )
}

function ConvertTo-RenderKitDublinCoreXmpFieldValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [object]$Definition
    )

    if ($null -eq $Value) {
        return $null
    }

    $values = New-Object System.Collections.Generic.List[string]
    if ($Value -is [System.Collections.IEnumerable] -and
        -not ($Value -is [string])) {
        foreach ($item in @($Value)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$item)) {
                $values.Add([string]$item)
            }
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$Value)) {
        $values.Add([string]$Value)
    }

    if ($values.Count -eq 0) {
        return $null
    }
    if ([string]$Definition.readStrategy -eq 'All') {
        return ,([string[]]$values.ToArray())
    }
    if ([string]$Definition.fieldType -eq 'Integer') {
        return ConvertTo-RenderKitMetadataInt64 -Value $values[0]
    }

    return [string]$values[0]
}

function ConvertFrom-RenderKitDublinCoreXmpMetadata {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Raw,

        [object]$Map
    )

    $fields = [ordered]@{}
    if (-not $Raw) {
        return $fields
    }
    if (-not $Map) {
        $Map = Read-RenderKitDublinCoreXmpMap
    }

    foreach ($definition in @(
        Get-RenderKitDublinCoreXmpFieldDefinitions -Map $Map
    )) {
        $rawValue = Get-RenderKitExactMetadataPropertyValue `
            -Object $Raw `
            -Name @($definition.readTags | ForEach-Object { [string]$_ })
        $value = ConvertTo-RenderKitDublinCoreXmpFieldValue `
            -Value $rawValue `
            -Definition $definition
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name ([string]$definition.field) `
            -Value $value
    }

    return $fields
}
