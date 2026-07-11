Register-RenderKitFunction "Import-Metadata"
function Import-Metadata {
    <#
.SYNOPSIS
Imports versioned RenderKit metadata exports.

.DESCRIPTION
Imports IPTC, Dublin Core, and standard XMP profiles from a RenderKit
MetadataExport. File paths are resolved from project-relative paths when
-ProjectRoot is supplied. Structured values remain structured and use the
normal embedded or explicit XMP-sidecar writer unless -NoEmbedded is used.
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [string]$ProjectRoot,

        [ValidateSet('Merge', 'Overwrite', 'Skip')]
        [string]$ConflictAction = 'Merge',

        [switch]$NoEmbedded,

        [switch]$XmpSidecar,

        [switch]$Force
    )

    $resolvedExportPath = (
        Resolve-Path -LiteralPath $Path -ErrorAction Stop
    ).ProviderPath
    $export = Read-RenderKitJsonFile `
        -Path $resolvedExportPath `
        -MaximumBytes 104857600 `
        -Validator {
            param($value)
            [string]$value.artifactType -eq 'MetadataExport' -and
                -not [string]::IsNullOrWhiteSpace(
                    [string]$value.schemaVersion
                ) -and
                $null -ne $value.records
        }

    $resolvedProjectRoot = if (
        [string]::IsNullOrWhiteSpace($ProjectRoot)
    ) {
        $null
    }
    else {
        (Resolve-Path -LiteralPath $ProjectRoot -ErrorAction Stop).ProviderPath
    }
    $iptcMap = Read-RenderKitIptcMetadataMap
    $profileFields = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($definition in @($iptcMap.fields)) {
        [void]$profileFields.Add([string]$definition.field)
    }
    $dublinCoreMap = Read-RenderKitDublinCoreXmpMap
    foreach ($definition in @(
        Get-RenderKitDublinCoreXmpFieldDefinitions `
            -Map $dublinCoreMap
    )) {
        [void]$profileFields.Add([string]$definition.field)
    }

    $entries = New-Object System.Collections.Generic.List[object]
    $succeeded = 0
    $failed = 0
    $skippedCount = 0
    foreach ($item in @($export.records)) {
        $targetPath = $null
        try {
            $relativePath = [string]$item.relativePath
            if (-not [string]::IsNullOrWhiteSpace($resolvedProjectRoot) -and
                -not [string]::IsNullOrWhiteSpace($relativePath)) {
                $targetPath = [System.IO.Path]::GetFullPath(
                    (Join-Path `
                        -Path $resolvedProjectRoot `
                        -ChildPath ($relativePath -replace
                            '/',
                            [System.IO.Path]::DirectorySeparatorChar))
                )
                if (-not (Test-RenderKitPathInsideRoot `
                        -Path $targetPath `
                        -RootPath $resolvedProjectRoot)) {
                    throw "Metadata import path '$relativePath' escapes the project root."
                }
            }
            elseif (-not [string]::IsNullOrWhiteSpace(
                    [string]$item.sourcePath
                )) {
                $targetPath = [System.IO.Path]::GetFullPath(
                    [string]$item.sourcePath
                )
            }
            else {
                throw 'Metadata export record has no resolvable source path.'
            }

            if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
                throw "Metadata import target '$targetPath' was not found."
            }

            $metadata = [ordered]@{}
            $metadataSources = New-Object `
                System.Collections.Generic.List[object]
            if ($item.profiles) {
                foreach ($profileName in @(
                    'iptc',
                    'dublinCoreXmp',
                    'xmp'
                )) {
                    $profile = @(
                        $item.profiles.PSObject.Properties |
                            Where-Object {
                                [string]$_.Name -ieq $profileName
                            } |
                            Select-Object -First 1
                    )
                    if ($profile -and $profile[0].Value) {
                        $metadataSources.Add($profile[0].Value)
                    }
                }
            }
            if ($metadataSources.Count -eq 0) {
                $metadataSources.Add($item.record.metadata)
            }
            foreach ($metadataSource in $metadataSources) {
                foreach ($property in @(
                    $metadataSource.PSObject.Properties
                )) {
                    if (-not $profileFields.Contains(
                            [string]$property.Name)) {
                        continue
                    }
                    Assert-RenderKitMetadataFieldWrite `
                        -Field ([string]$property.Name) `
                        -Value $property.Value `
                        -Force:$Force |
                        Out-Null
                    Set-RenderKitMetadataFieldValue `
                        -Fields $metadata `
                        -Name ([string]$property.Name) `
                        -Value $property.Value
                }
            }

            if ($metadata.Count -eq 0) {
                $skippedCount++
                $entries.Add([PSCustomObject]@{
                    Path = $targetPath
                    Status = 'Skipped'
                    Reason = 'NoProfileMetadata'
                    Changes = @()
                    Embedded = @()
                })
                continue
            }
            if ($ConflictAction -eq 'Skip') {
                $existing = Read-RenderKitFileMetadataRecord `
                    -Path $targetPath `
                    -ProjectRoot $resolvedProjectRoot
                if ($existing) {
                    $skippedCount++
                    $entries.Add([PSCustomObject]@{
                        Path = $targetPath
                        Status = 'Skipped'
                        Reason = 'MetadataRecordExists'
                        Changes = @()
                        Embedded = @()
                    })
                    continue
                }
            }
            if (-not $PSCmdlet.ShouldProcess(
                    $targetPath,
                    "Import metadata profiles"
                )) {
                continue
            }

            $store = Set-RenderKitFileMetadataRecordField `
                -Path $targetPath `
                -ProjectRoot $resolvedProjectRoot `
                -Metadata $metadata `
                -Override:($ConflictAction -eq 'Overwrite')
            $changed = [ordered]@{}
            foreach ($change in @($store.Changes)) {
                Set-RenderKitMetadataFieldValue `
                    -Fields $changed `
                    -Name ([string]$change.Field) `
                    -Value $change.NewValue
            }
            $embedded = if (-not $NoEmbedded -and $changed.Count -gt 0) {
                @(Invoke-RenderKitEmbeddedMetadataWrite `
                    -Path $targetPath `
                    -Metadata $changed `
                    -PreferXmpSidecar:$XmpSidecar)
            }
            else {
                @()
            }
            $succeeded++
            $entries.Add([PSCustomObject]@{
                Path = $targetPath
                Status = 'Succeeded'
                Reason = $null
                MetadataVersion = [int]$store.Version
                Changes = @($store.Changes)
                Skipped = @($store.Skipped)
                Embedded = @($embedded)
            })
        }
        catch {
            $failed++
            $entries.Add([PSCustomObject]@{
                Path = $targetPath
                Status = 'Failed'
                Reason = $_.Exception.Message
                Changes = @()
                Embedded = @()
            })
        }
    }

    return [PSCustomObject]@{
        Path = $resolvedExportPath
        ProjectRoot = $resolvedProjectRoot
        Profile = 'IPTC'
        Profiles = @(
            'IPTC',
            'DublinCoreXmp',
            'XMP'
        )
        ConflictAction = $ConflictAction
        Total = @($export.records).Count
        Succeeded = $succeeded
        Failed = $failed
        Skipped = $skippedCount
        Entries = @($entries.ToArray())
    }
}
