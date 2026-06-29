Register-RenderKitFunction "Get-Metadata"
function Get-Metadata {
    <#
.SYNOPSIS
Reads RenderKit metadata for files, folders, or projects.

.DESCRIPTION
Returns table-friendly default metadata and can include selected registry
fields. Project calls write a metadata record into the project store by default;
path calls only write sidecars when -Store is set.
#>
    [CmdletBinding(DefaultParameterSetName = 'ProjectRoot')]
    param(
        [Parameter(
            Mandatory,
            Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            ParameterSetName = 'Path'
        )]
        [Alias('FullName')]
        [string[]]$Path,

        [Parameter(ParameterSetName = 'Path')]
        [Parameter(Mandatory, ParameterSetName = 'ProjectRoot')]
        [string]$ProjectRoot,

        [Parameter(Mandatory, ParameterSetName = 'ProjectName')]
        [string]$ProjectName,

        [switch]$Recurse,

        [switch]$Store,

        [switch]$NoStore,

        [switch]$IncludeUnsupported,

        [switch]$IncludeMetadata,

        [switch]$IncludeRaw
    )

    dynamicparam {
        New-RenderKitMetadataFieldDynamicParameter `
            -Name 'Field' `
            -Position -1 `
            -ParameterType ([string[]])
    }

    begin {
        if ($Store -and $NoStore) {
            throw 'Use either -Store or -NoStore, not both.'
        }

        $selectedFields = @()
        if ($PSBoundParameters.ContainsKey('Field')) {
            $selectedFields = @($PSBoundParameters['Field'] | ForEach-Object { [string]$_ })
        }
    }

    process {
        $resolvedProjectRoot = $null
        $inputPaths = @()
        $projectMode = $false

        switch ($PSCmdlet.ParameterSetName) {
            'ProjectRoot' {
                $resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot -ErrorAction Stop).ProviderPath
                $inputPaths = @($resolvedProjectRoot)
                $projectMode = $true
            }
            'ProjectName' {
                $project = @(Get-Project -AvailableOnly |
                    Where-Object { [string]$_.Name -ieq $ProjectName })
                if ($project.Count -eq 0) {
                    throw "RenderKit project '$ProjectName' was not found or is not available."
                }
                if ($project.Count -gt 1) {
                    throw "RenderKit project name '$ProjectName' is ambiguous. Use -ProjectRoot."
                }
                $resolvedProjectRoot = [string]$project[0].RootPath
                $inputPaths = @($resolvedProjectRoot)
                $projectMode = $true
            }
            default {
                $inputPaths = @($Path)
                if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
                    $resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot -ErrorAction Stop).ProviderPath
                }
            }
        }

        $shouldStore = [bool]$Store -or ($projectMode -and -not [bool]$NoStore)
        $effectiveRecurse = [bool]$Recurse -or $projectMode

        foreach ($inputPath in $inputPaths) {
            $resolvedPath = (Resolve-Path -LiteralPath $inputPath -ErrorAction Stop).ProviderPath
            $item = Get-Item -LiteralPath $resolvedPath -ErrorAction Stop
            $files = @()

            if ($item.PSIsContainer) {
                $files = @(
                    Get-ChildItem `
                        -LiteralPath $item.FullName `
                        -File `
                        -Force `
                        -Recurse:$effectiveRecurse `
                        -ErrorAction SilentlyContinue |
                        Where-Object {
                            $relative = $null
                            if ($projectMode) {
                                $relative = ConvertTo-RenderKitProjectRelativePath `
                                    -BasePath $resolvedProjectRoot `
                                    -Path $_.FullName
                            }
                            -not ($projectMode -and $relative -like '.renderkit/*')
                        }
                )
            }
            else {
                $files = @($item)
            }

            foreach ($file in $files) {
                $route = Resolve-RenderKitMetadataAdapterRoute -Path $file.FullName
                if (-not $IncludeUnsupported -and -not [bool]$route.IsSupported) {
                    continue
                }

                $readResult = Read-RenderKitFileMetadata `
                    -Path $file.FullName `
                    -ProjectRoot $resolvedProjectRoot `
                    -IncludeRaw:$IncludeRaw

                $storeResult = $null
                if ($shouldStore) {
                    $storeResult = Write-RenderKitFileMetadataRecord `
                        -MetadataResult $readResult `
                        -ProjectRoot $resolvedProjectRoot
                }

                New-RenderKitMetadataDisplayRecord `
                    -ReadResult $readResult `
                    -StoreResult $storeResult `
                    -SelectedField $selectedFields `
                    -IncludeMetadata:$IncludeMetadata
            }
        }
    }
}

function Get-RenderKitMetadataDisplayValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Fields,

        [Parameter(Mandatory)]
        [string[]]$Name
    )

    if ($null -eq $Fields) { return $null }
    $properties = @($Fields.PSObject.Properties)
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

function Get-RenderKitMetadataDisplaySize {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Fields
    )

    $width = Get-RenderKitMetadataDisplayValue `
        -Fields $Fields `
        -Name @('VideoDisplayWidth', 'VideoWidth', 'ImageWidth')
    $height = Get-RenderKitMetadataDisplayValue `
        -Fields $Fields `
        -Name @('VideoDisplayHeight', 'VideoHeight', 'ImageHeight')
    if ($null -eq $width -or $null -eq $height) {
        return $null
    }

    return '{0}x{1}' -f $width, $height
}

function New-RenderKitMetadataDisplayRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$ReadResult,

        [AllowNull()]
        [object]$StoreResult,

        [string[]]$SelectedField,

        [switch]$IncludeMetadata
    )

    $fields = $ReadResult.Fields
    $properties = [ordered]@{
        FileName = Get-RenderKitMetadataDisplayValue -Fields $fields -Name @('FileName')
        Date = Get-RenderKitMetadataDisplayValue `
            -Fields $fields `
            -Name @('DateCreated', 'DateOriginal', 'CreatedAtFileSystem', 'ModifiedAtFileSystem')
        Size = Get-RenderKitMetadataDisplayValue -Fields $fields -Name @('FileSizeHuman', 'FileSizeBytes')
        Duration = Get-RenderKitMetadataDisplayValue -Fields $fields -Name @('Duration', 'VideoDuration', 'AudioDuration')
        DisplaySize = Get-RenderKitMetadataDisplaySize -Fields $fields
        AspectRatio = Get-RenderKitMetadataDisplayValue `
            -Fields $fields `
            -Name @('DisplayAspectRatio', 'ImageAspectRatio', 'PixelAspectRatio')
        Rating = Get-RenderKitMetadataDisplayValue -Fields $fields -Name @('Rating')
        FrameRate = Get-RenderKitMetadataDisplayValue `
            -Fields $fields `
            -Name @('VideoFrameRate', 'ImageSequenceFrameRate', 'AudioFrameRate')
        MediaKind = [string]$ReadResult.MediaKind
        Path = [string]$ReadResult.Path
        MetadataVersion = if ($StoreResult) { [int]$StoreResult.Version } else { $null }
        StorePath = if ($StoreResult) { [string]$StoreResult.RecordPath } else { $null }
    }

    foreach ($fieldName in @($SelectedField)) {
        if ($properties.Contains($fieldName)) {
            continue
        }
        $properties[$fieldName] = Get-RenderKitMetadataDisplayValue `
            -Fields $fields `
            -Name @($fieldName)
    }

    if ($IncludeMetadata) {
        $properties['Metadata'] = $fields
        $properties['Warnings'] = @($ReadResult.Warnings)
        $properties['Adapters'] = @($ReadResult.AdapterIds)
        $properties['Readers'] = @($ReadResult.Readers)
        if ($ReadResult.Raw) {
            $properties['Raw'] = $ReadResult.Raw
        }
    }

    return [PSCustomObject]$properties
}
