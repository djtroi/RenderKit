Register-RenderKitFunction "Get-RenderKitMetadataFieldRegistry"
function Get-RenderKitMetadataFieldRegistry {
    [CmdletBinding()]
    param(
        [string]$Path,

        [string[]]$Field,

        [ValidateSet(
            'All',
            'Audio',
            'Video',
            'Image',
            'ImageSequence',
            'Subtitle',
            'ProjectFile',
            'Sidecar',
            'Unknown'
        )]
        [string[]]$AppliesTo,

        [string]$Category,

        [switch]$AsHashtable,

        [switch]$IncludeRegistryMetadata,

        [switch]$Reload
    )

    $registry = Read-RenderKitMetadataFieldRegistry `
        -Path $Path `
        -Reload:$Reload
    $fields = @($registry.fields)

    if ($Field -and $Field.Count -gt 0) {
        $fieldSet = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
        foreach ($fieldName in $Field) {
            [void]$fieldSet.Add($fieldName)
        }
        $fields = @($fields | Where-Object { $fieldSet.Contains([string]$_.name) })
    }

    if ($AppliesTo -and $AppliesTo.Count -gt 0) {
        $appliesToSet = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
        foreach ($mediaKind in $AppliesTo) {
            [void]$appliesToSet.Add($mediaKind)
        }
        $fields = @(
            $fields |
                Where-Object {
                    $fieldAppliesTo = @($_.appliesTo | ForEach-Object { [string]$_ })
                    if ($fieldAppliesTo -contains 'All') { return $true }
                    foreach ($mediaKind in $fieldAppliesTo) {
                        if ($appliesToSet.Contains($mediaKind)) { return $true }
                    }
                    return $false
                }
        )
    }

    if (-not [string]::IsNullOrWhiteSpace($Category)) {
        $fields = @(
            $fields |
                Where-Object {
                    @($_.categories | ForEach-Object { [string]$_ }) -contains $Category
                }
        )
    }

    $iptcMap = Read-RenderKitIptcMetadataMap
    $iptcDefinitions = @{}
    foreach ($definition in @($iptcMap.fields)) {
        $iptcDefinitions[[string]$definition.field] = $definition
    }
    $iptcUnmapped = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($definition in @($iptcMap.unmappedFields)) {
        [void]$iptcUnmapped.Add([string]$definition.field)
    }
    $fields = @(
        foreach ($definition in $fields) {
            $copy = [ordered]@{}
            foreach ($property in @($definition.PSObject.Properties)) {
                $copy[[string]$property.Name] = $property.Value
            }
            $name = [string]$definition.name
            if ($iptcDefinitions.ContainsKey($name)) {
                $iptcDefinition = $iptcDefinitions[$name]
                $copy['iptcProfile'] = if (
                    [string]$iptcDefinition.profile -eq 'Extension'
                ) {
                    'Extension'
                } else {
                    'Core'
                }
                $copy['embeddedWritable'] =
                    @($iptcDefinition.writeTags).Count -gt 0
            }
            elseif ($iptcUnmapped.Contains($name)) {
                $copy['iptcProfile'] = 'Extension'
                $copy['embeddedWritable'] = $false
            }
            else {
                $copy['iptcProfile'] = $null
                $copy['embeddedWritable'] = $null
            }
            [PSCustomObject]$copy
        }
    )

    if ($AsHashtable) {
        $result = [ordered]@{}
        foreach ($definition in $fields) {
            $result[[string]$definition.name] = $definition
        }
        return $result
    }

    if ($IncludeRegistryMetadata) {
        return [PSCustomObject]@{
            SchemaVersion = [string]$registry.schemaVersion
            ArtifactType = [string]$registry.artifactType
            GeneratedAtUtc = [string]$registry.generatedAtUtc
            FieldRowCount = [int]$registry.fieldRowCount
            FieldCount = [int]$registry.fieldCount
            DuplicateFieldNameCount = [int]$registry.duplicateFieldNameCount
            Fields = @($fields)
        }
    }

    return $fields
}
