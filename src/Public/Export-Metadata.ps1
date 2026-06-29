Register-RenderKitFunction "Export-Metadata"
function Export-Metadata {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ProjectRoot')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'Path')]
        [Alias('FullName')]
        [string[]]$Path,

        [Parameter(ParameterSetName = 'Path')]
        [Parameter(Mandatory, ParameterSetName = 'ProjectRoot')]
        [string]$ProjectRoot,

        [Parameter(Mandatory, ParameterSetName = 'ProjectName')]
        [string]$ProjectName,

        [Parameter(Mandatory)]
        [string]$DestinationPath,

        [ValidateSet('Json')]
        [string]$Format = 'Json',

        [switch]$Refresh,

        [ValidateRange(1, 64)]
        [int]$ThrottleLimit = 4,

        [switch]$IncludeUnsupported,

        [switch]$IncludeHistory,

        [switch]$PassThru
    )

    begin {
        $recordItems = New-Object System.Collections.Generic.List[object]
        $errors = New-Object System.Collections.Generic.List[object]
        $resolvedProjectRoot = $null
        $scope = $PSCmdlet.ParameterSetName

        if ($PSCmdlet.ParameterSetName -eq 'ProjectName') {
            $project = @(Get-Project -AvailableOnly |
                Where-Object { [string]$_.Name -ieq $ProjectName })
            if ($project.Count -eq 0) {
                throw "RenderKit project '$ProjectName' was not found or is not available."
            }
            if ($project.Count -gt 1) {
                throw "RenderKit project name '$ProjectName' is ambiguous. Use -ProjectRoot."
            }
            $ProjectRoot = [string]$project[0].RootPath
        }

        if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
            $resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot -ErrorAction Stop).ProviderPath
        }
    }

    process {
        if ($scope -in @('ProjectRoot', 'ProjectName')) {
            if ($Refresh) {
                Update-RenderKitProjectMetadataCache `
                    -ProjectRoot $resolvedProjectRoot `
                    -ThrottleLimit $ThrottleLimit `
                    -IncludeUnsupported:$IncludeUnsupported |
                    Out-Null
            }

            $metadataRoot = Join-Path -Path $resolvedProjectRoot -ChildPath '.renderkit/metadata/files'
            if (Test-Path -LiteralPath $metadataRoot -PathType Container) {
                foreach ($recordFile in @(Get-ChildItem -LiteralPath $metadataRoot -Filter '*.json' -File -Force)) {
                    try {
                        $record = Read-RenderKitJsonFile `
                            -Path $recordFile.FullName `
                            -MaximumBytes 52428800 `
                            -Validator { param($value) Test-RenderKitFileMetadataRecordSchema -Record $value }
                        $recordItems.Add((New-RenderKitMetadataExportRecord `
                            -Record $record `
                            -RecordPath $recordFile.FullName `
                            -ProjectRoot $resolvedProjectRoot `
                            -IncludeHistory:$IncludeHistory))
                    }
                    catch {
                        $errors.Add([PSCustomObject]@{
                            Path = $recordFile.FullName
                            Error = $_.Exception.Message
                        })
                    }
                }
            }
        }
        else {
            foreach ($inputPath in @($Path)) {
                try {
                    $resolvedPath = (Resolve-Path -LiteralPath $inputPath -ErrorAction Stop).ProviderPath
                    if ($Refresh) {
                        Get-Metadata `
                            -Path $resolvedPath `
                            -ProjectRoot $resolvedProjectRoot `
                            -Store `
                            -IncludeUnsupported:$IncludeUnsupported `
                            -IncludeMetadata |
                            Out-Null
                    }

                    $location = Get-RenderKitFileMetadataLocation `
                        -Path $resolvedPath `
                        -ProjectRoot $resolvedProjectRoot
                    if (-not (Test-Path -LiteralPath $location.RecordPath -PathType Leaf)) {
                        $errors.Add([PSCustomObject]@{
                            Path = $resolvedPath
                            Error = 'MetadataRecordNotFound'
                        })
                        continue
                    }

                    $record = Read-RenderKitJsonFile `
                        -Path $location.RecordPath `
                        -MaximumBytes 52428800 `
                        -Validator { param($value) Test-RenderKitFileMetadataRecordSchema -Record $value }
                    $recordItems.Add((New-RenderKitMetadataExportRecord `
                        -Record $record `
                        -RecordPath $location.RecordPath `
                        -ProjectRoot $resolvedProjectRoot `
                        -SourcePath $resolvedPath `
                        -IncludeHistory:$IncludeHistory))
                }
                catch {
                    $errors.Add([PSCustomObject]@{
                        Path = [string]$inputPath
                        Error = $_.Exception.Message
                    })
                }
            }
        }
    }

    end {
        $destination = Resolve-RenderKitMetadataExportDestination `
            -DestinationPath $DestinationPath `
            -ProjectRoot $resolvedProjectRoot `
            -Scope $scope

        $export = [PSCustomObject]@{
            tool = 'RenderKit'
            schemaVersion = '1.0'
            artifactType = 'MetadataExport'
            exportedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            scope = $scope
            format = $Format
            projectRoot = $resolvedProjectRoot
            includeHistory = [bool]$IncludeHistory
            recordCount = $recordItems.Count
            errorCount = $errors.Count
            records = @($recordItems.ToArray())
            errors = @($errors.ToArray())
        }

        if ($PSCmdlet.ShouldProcess($destination, "Export RenderKit metadata")) {
            $parent = Split-Path -Path $destination -Parent
            if (-not [string]::IsNullOrWhiteSpace($parent) -and
                -not (Test-Path -LiteralPath $parent -PathType Container)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            $export |
                ConvertTo-Json -Depth 60 |
                Set-Content -LiteralPath $destination -Encoding UTF8

            $result = [PSCustomObject]@{
                Path = [System.IO.Path]::GetFullPath($destination)
                Format = $Format
                Scope = $scope
                ProjectRoot = $resolvedProjectRoot
                RecordCount = $recordItems.Count
                ErrorCount = $errors.Count
                IncludeHistory = [bool]$IncludeHistory
                Export = if ($PassThru) { $export } else { $null }
            }
            return $result
        }
    }
}

function Resolve-RenderKitMetadataExportDestination {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$DestinationPath,

        [AllowNull()]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [string]$Scope
    )

    $isDirectory = Test-Path -LiteralPath $DestinationPath -PathType Container
    $trimmed = $DestinationPath.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    if ($isDirectory -or $trimmed.Length -ne $DestinationPath.Length) {
        $directory = if ($isDirectory) {
            (Resolve-Path -LiteralPath $DestinationPath -ErrorAction Stop).ProviderPath
        }
        else {
            [System.IO.Path]::GetFullPath($trimmed)
        }
        $name = if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
            Split-Path -Path $ProjectRoot -Leaf
        }
        else {
            'renderkit'
        }
        return Join-Path `
            -Path $directory `
            -ChildPath ('{0}-metadata-{1}.json' -f $name, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    }

    if ([System.IO.Path]::GetExtension($DestinationPath).ToLowerInvariant() -ne '.json') {
        return "$DestinationPath.json"
    }
    return [System.IO.Path]::GetFullPath($DestinationPath)
}

function New-RenderKitMetadataExportRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Record,

        [Parameter(Mandatory)]
        [string]$RecordPath,

        [AllowNull()]
        [string]$ProjectRoot,

        [string]$SourcePath,

        [switch]$IncludeHistory
    )

    $output = [ordered]@{}
    foreach ($property in @($Record.PSObject.Properties)) {
        if ($property.Name -eq 'history' -and -not $IncludeHistory) {
            continue
        }
        $output[$property.Name] = $property.Value
    }

    $relativePath = if ($Record.storage -and $Record.storage.relativePath) {
        [string]$Record.storage.relativePath
    }
    else {
        $null
    }
    $absolutePath = $SourcePath
    if ([string]::IsNullOrWhiteSpace($absolutePath) -and
        -not [string]::IsNullOrWhiteSpace($ProjectRoot) -and
        -not [string]::IsNullOrWhiteSpace($relativePath)) {
        $absolutePath = Join-Path `
            -Path $ProjectRoot `
            -ChildPath ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    }

    [PSCustomObject]@{
        sourcePath = if ([string]::IsNullOrWhiteSpace($absolutePath)) { $null } else { [System.IO.Path]::GetFullPath($absolutePath) }
        relativePath = $relativePath
        recordPath = [System.IO.Path]::GetFullPath($RecordPath)
        record = [PSCustomObject]$output
    }
}
