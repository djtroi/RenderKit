# Harden external metadata-tool execution after the adapter implementations are
# loaded. Keeping these process boundaries together makes the shared timeout and
# output policy consistent across ExifTool, MediaInfo and MKVToolNix.

function Invoke-RenderKitExifToolCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Candidate,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $commandArguments = @($Candidate.PrefixArguments) + @($Arguments)
    $result = Invoke-RenderKitBoundedMetadataProcess `
        -FilePath ([string]$Candidate.Path) `
        -Arguments $commandArguments `
        -TimeoutSeconds 120 `
        -MaximumStandardOutputBytes 32MB `
        -MaximumStandardErrorBytes 8MB

    if ([int]$result.ExitCode -ne 0) {
        $diagnostic = ConvertTo-RenderKitMetadataProcessDiagnostic `
            -Text $(if (-not [string]::IsNullOrWhiteSpace([string]$result.StandardError)) {
                [string]$result.StandardError
            }
            else {
                [string]$result.StandardOutput
            })
        throw "ExifTool $($Candidate.Kind.ToLowerInvariant()) exited with code $($result.ExitCode)`: $diagnostic"
    }

    return @(
        @($result.StandardOutputLines) +
        @($result.StandardErrorLines)
    )
}

function Invoke-RenderKitMediaInfoHostMetadataRead {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$HostPath
    )

    $result = Invoke-RenderKitBoundedMetadataProcess `
        -FilePath $HostPath `
        -Arguments @('mediainfo', 'read', '--json', $Path) `
        -TimeoutSeconds 120 `
        -MaximumStandardOutputBytes 32MB `
        -MaximumStandardErrorBytes 8MB
    if ([int]$result.ExitCode -ne 0) {
        $diagnostic = ConvertTo-RenderKitMetadataProcessDiagnostic `
            -Text $(if (-not [string]::IsNullOrWhiteSpace([string]$result.StandardError)) {
                [string]$result.StandardError
            }
            else {
                [string]$result.StandardOutput
            })
        throw "host exited with code $($result.ExitCode)`: $diagnostic"
    }
    if ([string]::IsNullOrWhiteSpace([string]$result.StandardOutput)) {
        throw 'MediaInfo host returned no JSON output.'
    }
    return ([string]$result.StandardOutput) | ConvertFrom-Json -ErrorAction Stop
}

function Invoke-RenderKitMediaInfoCliMetadataRead {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$CommandPath
    )

    $result = Invoke-RenderKitBoundedMetadataProcess `
        -FilePath $CommandPath `
        -Arguments @('--Output=JSON', '--Full', $Path) `
        -TimeoutSeconds 120 `
        -MaximumStandardOutputBytes 32MB `
        -MaximumStandardErrorBytes 8MB
    if ([int]$result.ExitCode -ne 0) {
        $diagnostic = ConvertTo-RenderKitMetadataProcessDiagnostic `
            -Text $(if (-not [string]::IsNullOrWhiteSpace([string]$result.StandardError)) {
                [string]$result.StandardError
            }
            else {
                [string]$result.StandardOutput
            })
        throw "cli exited with code $($result.ExitCode)`: $diagnostic"
    }
    if ([string]::IsNullOrWhiteSpace([string]$result.StandardOutput)) {
        throw 'MediaInfo CLI returned no JSON output.'
    }
    return ([string]$result.StandardOutput) | ConvertFrom-Json -ErrorAction Stop
}

function Invoke-RenderKitMkvToolNixApplication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Name,
        [ValidateRange(1, 1800)][int]$TimeoutSeconds = 300,
        [AllowEmptyCollection()][string[]]$MonitoredPath = @(),
        [ValidateRange(1024, 1073741824)][int64]$MaximumMonitoredFileBytes = 64MB
    )

    $result = Invoke-RenderKitBoundedMetadataProcess `
        -FilePath $Path `
        -Arguments $Arguments `
        -TimeoutSeconds $TimeoutSeconds `
        -MaximumStandardOutputBytes 32MB `
        -MaximumStandardErrorBytes 8MB `
        -MonitoredPath $MonitoredPath `
        -MaximumMonitoredFileBytes $MaximumMonitoredFileBytes
    if ([int]$result.ExitCode -ne 0) {
        $diagnostic = ConvertTo-RenderKitMetadataProcessDiagnostic `
            -Text $(if (-not [string]::IsNullOrWhiteSpace([string]$result.StandardError)) {
                [string]$result.StandardError
            }
            else {
                [string]$result.StandardOutput
            })
        throw "$Name exited with code $($result.ExitCode)`: $diagnostic"
    }
    return [PSCustomObject]@{
        ExitCode = [int]$result.ExitCode
        Output = @(
            @($result.StandardOutputLines) +
            @($result.StandardErrorLines)
        )
    }
}

function Read-RenderKitMkvToolNixXmlDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]
        [ValidateSet('Tags', 'Chapters')][string]$RootName,
        [ValidateRange(1024, 1073741824)][int64]$MaximumBytes = 64MB
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return New-RenderKitMkvToolNixXmlDocument -RootName $RootName
    }
    $fileInfo = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ([int64]$fileInfo.Length -eq 0) {
        return New-RenderKitMkvToolNixXmlDocument -RootName $RootName
    }
    if ([int64]$fileInfo.Length -gt $MaximumBytes) {
        throw "MKVToolNix XML '$Path' exceeds the $MaximumBytes byte limit."
    }

    $settings = [Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $settings.MaxCharactersInDocument = $MaximumBytes
    $settings.MaxCharactersFromEntities = 0
    $reader = [Xml.XmlReader]::Create($Path, $settings)
    try {
        $document = [Xml.XmlDocument]::new()
        $document.PreserveWhitespace = $false
        $document.XmlResolver = $null
        $document.Load($reader)
    }
    finally {
        $reader.Dispose()
    }
    if (-not $document.DocumentElement -or
        [string]$document.DocumentElement.LocalName -ne $RootName) {
        throw "MKVToolNix XML '$Path' has no $RootName root."
    }
    return $document
}

function Read-RenderKitMkvToolNixEmbeddedMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $resolvedPath = (
        Resolve-Path -LiteralPath $Path -ErrorAction Stop
    ).ProviderPath
    if (-not (Test-RenderKitMkvToolNixPath -Path $resolvedPath)) {
        throw 'MKVToolNix metadata reads require a Matroska or WebM file.'
    }
    $runtime = Resolve-RenderKitMkvToolNixRuntime
    if (-not [bool]$runtime.Available) {
        throw [string]$runtime.exception
    }
    $temporaryRoot = Join-Path `
        -Path ([IO.Path]::GetTempPath()) `
        -ChildPath ('renderkit-mkv-read-{0}' -f
            [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporaryRoot -Force |
        Out-Null
    try {
        $tagsPath = Join-Path $temporaryRoot 'tags.xml'
        $chaptersPath = Join-Path $temporaryRoot 'chapters.xml'
        Invoke-RenderKitMkvToolNixApplication `
            -Path ([string]$runtime.ExtractPath) `
            -Name 'mkvextract tags' `
            -Arguments @($resolvedPath, 'tags', $tagsPath) `
            -TimeoutSeconds 120 `
            -MonitoredPath @($tagsPath) `
            -MaximumMonitoredFileBytes 64MB |
            Out-Null
        Invoke-RenderKitMkvToolNixApplication `
            -Path ([string]$runtime.ExtractPath) `
            -Name 'mkvextract chapters' `
            -Arguments @($resolvedPath, 'chapters', $chaptersPath) `
            -TimeoutSeconds 120 `
            -MonitoredPath @($chaptersPath) `
            -MaximumMonitoredFileBytes 64MB |
            Out-Null
        $tags = Read-RenderKitMkvToolNixXmlDocument `
            -Path $tagsPath `
            -RootName Tags `
            -MaximumBytes 64MB
        $chapters = Read-RenderKitMkvToolNixXmlDocument `
            -Path $chaptersPath `
            -RootName Chapters `
            -MaximumBytes 64MB
        $fields = ConvertFrom-RenderKitMkvToolNixMetadata `
            -Tags $tags `
            -Chapters $chapters
        return [PSCustomObject]@{
            Fields = $fields
            Profile = 'Matroska'
            GlobalTagCount = @(
                $tags.DocumentElement.ChildNodes |
                    Where-Object {
                        $_ -is [Xml.XmlElement] -and
                            [string]$_.LocalName -eq 'Tag' -and
                            (Test-RenderKitMkvToolNixGlobalTagElement -Tag $_)
                    }
            ).Count
            EditionCount = @(
                $chapters.DocumentElement.ChildNodes |
                    Where-Object {
                        $_ -is [Xml.XmlElement] -and
                            [string]$_.LocalName -eq 'EditionEntry'
                    }
            ).Count
            ChapterCount = if ($fields.Contains('ChapterCount')) {
                [int]$fields['ChapterCount']
            }
            else {
                0
            }
            Runtime = [PSCustomObject]@{
                Version = [string]$runtime.Version
                Source = [string]$runtime.Source
                PropEditPath = [string]$runtime.PropEditPath
                ExtractPath = [string]$runtime.ExtractPath
                RuntimeIdentifier = [string]$runtime.RuntimeIdentifier
            }
        }
    }
    finally {
        Remove-Item `
            -LiteralPath $temporaryRoot `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }
}
