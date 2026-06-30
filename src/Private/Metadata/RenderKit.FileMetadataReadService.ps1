function Test-RenderKitMetadataValueIsEmpty {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) { return $true }
    if ($Value -is [string]) {
        return [string]::IsNullOrWhiteSpace($Value)
    }
    if ($Value -is [System.Collections.IDictionary]) {
        return $Value.Count -eq 0
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        return @($Value).Count -eq 0
    }
    return $false
}

function Set-RenderKitMetadataFieldValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Fields,

        [Parameter(Mandatory)]
        [string]$Name,

        [AllowNull()]
        [object]$Value
    )

    if (Test-RenderKitMetadataValueIsEmpty -Value $Value) {
        return
    }

    if ($Value -is [datetime]) {
        $Value = $Value.ToUniversalTime().ToString('o')
    }

    $Fields[$Name] = $Value
}

function ConvertTo-RenderKitMetadataNumber {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) { return $null }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or
        $Value -is [decimal]) {
        return [double]$Value
    }

    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $text = $text -replace '\s+', ''
    $text = $text -replace ',', '.'

    $parsed = [double]0
    if ([double]::TryParse(
            $text,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$parsed)) {
        return $parsed
    }

    return $null
}

function ConvertTo-RenderKitMetadataInt64 {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    $number = ConvertTo-RenderKitMetadataNumber -Value $Value
    if ($null -eq $number) { return $null }
    return [int64][Math]::Round([double]$number, 0)
}

function ConvertTo-RenderKitMetadataDurationText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Seconds
    )

    $number = ConvertTo-RenderKitMetadataNumber -Value $Seconds
    if ($null -eq $number -or $number -lt 0) { return $null }

    $timeSpan = [timespan]::FromSeconds([double]$number)
    if ($timeSpan.TotalHours -ge 1) {
        return '{0:00}:{1:00}:{2:00}.{3:000}' -f `
            [Math]::Floor($timeSpan.TotalHours),
            $timeSpan.Minutes,
            $timeSpan.Seconds,
            $timeSpan.Milliseconds
    }

    return '{0:00}:{1:00}.{2:000}' -f `
        $timeSpan.Minutes,
        $timeSpan.Seconds,
        $timeSpan.Milliseconds
}

function Get-RenderKitMetadataPropertyValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory)]
        [string[]]$Name
    )

    if ($null -eq $Object) { return $null }
    $properties = @($Object.PSObject.Properties)

    foreach ($candidate in $Name) {
        foreach ($property in $properties) {
            if ($property.Name -ieq $candidate) {
                return $property.Value
            }
        }
    }

    foreach ($candidate in $Name) {
        foreach ($property in $properties) {
            if ($property.Name -like "*:$candidate") {
                return $property.Value
            }
        }
    }

    return $null
}

function Get-RenderKitMetadataTrackType {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$Track
    )

    return [string](Get-RenderKitMetadataPropertyValue `
        -Object $Track `
        -Name @('@type', 'Type'))
}

function Get-RenderKitMetadataMediaInfoTrack {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$MediaInfo,

        [Parameter(Mandatory)]
        [string]$Type
    )

    $tracks = @($MediaInfo.media.track)
    return @(
        $tracks |
            Where-Object { (Get-RenderKitMetadataTrackType -Track $_) -eq $Type } |
            Select-Object -First 1
    )
}

function ConvertFrom-RenderKitMediaInfoMetadata {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Raw
    )

    $fields = [ordered]@{}
    if (-not $Raw -or -not $Raw.media) {
        return $fields
    }

    $general = Get-RenderKitMetadataMediaInfoTrack -MediaInfo $Raw -Type 'General'
    $video = Get-RenderKitMetadataMediaInfoTrack -MediaInfo $Raw -Type 'Video'
    $audio = Get-RenderKitMetadataMediaInfoTrack -MediaInfo $Raw -Type 'Audio'
    $image = Get-RenderKitMetadataMediaInfoTrack -MediaInfo $Raw -Type 'Image'

    $duration = Get-RenderKitMetadataPropertyValue -Object $general -Name @('Duration')
    if ($null -eq $duration) {
        $duration = Get-RenderKitMetadataPropertyValue -Object $video -Name @('Duration')
    }
    if ($null -eq $duration) {
        $duration = Get-RenderKitMetadataPropertyValue -Object $audio -Name @('Duration')
    }
    $durationSeconds = ConvertTo-RenderKitMetadataNumber -Value $duration
    Set-RenderKitMetadataFieldValue -Fields $fields -Name 'DurationSeconds' -Value $durationSeconds
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'Duration' `
        -Value (ConvertTo-RenderKitMetadataDurationText -Seconds $durationSeconds)

    $format = Get-RenderKitMetadataPropertyValue -Object $general -Name @('Format')
    Set-RenderKitMetadataFieldValue -Fields $fields -Name 'ContainerFormat' -Value $format
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'CodecName' `
        -Value (Get-RenderKitMetadataPropertyValue -Object $general -Name @('CodecID'))

    if ($video) {
        $width = ConvertTo-RenderKitMetadataInt64 `
            -Value (Get-RenderKitMetadataPropertyValue -Object $video -Name @('Width'))
        $height = ConvertTo-RenderKitMetadataInt64 `
            -Value (Get-RenderKitMetadataPropertyValue -Object $video -Name @('Height'))
        Set-RenderKitMetadataFieldValue -Fields $fields -Name 'VideoWidth' -Value $width
        Set-RenderKitMetadataFieldValue -Fields $fields -Name 'VideoHeight' -Value $height
        Set-RenderKitMetadataFieldValue -Fields $fields -Name 'VideoDisplayWidth' -Value $width
        Set-RenderKitMetadataFieldValue -Fields $fields -Name 'VideoDisplayHeight' -Value $height
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'VideoFormat' `
            -Value (Get-RenderKitMetadataPropertyValue -Object $video -Name @('Format'))
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'VideoCodecId' `
            -Value (Get-RenderKitMetadataPropertyValue -Object $video -Name @('CodecID'))
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'VideoFrameRate' `
            -Value (ConvertTo-RenderKitMetadataNumber -Value (
                Get-RenderKitMetadataPropertyValue -Object $video -Name @('FrameRate')
            ))
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'VideoFrameCount' `
            -Value (ConvertTo-RenderKitMetadataInt64 -Value (
                Get-RenderKitMetadataPropertyValue -Object $video -Name @('FrameCount')
            ))
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'DisplayAspectRatio' `
            -Value (Get-RenderKitMetadataPropertyValue `
                -Object $video `
                -Name @('DisplayAspectRatio_String', 'DisplayAspectRatio'))
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'PixelAspectRatio' `
            -Value (Get-RenderKitMetadataPropertyValue `
                -Object $video `
                -Name @('PixelAspectRatio_String', 'PixelAspectRatio'))
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'ColorSpace' `
            -Value (Get-RenderKitMetadataPropertyValue -Object $video -Name @('ColorSpace'))
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'ChromaSubsampling' `
            -Value (Get-RenderKitMetadataPropertyValue -Object $video -Name @('ChromaSubsampling'))
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'VideoBitDepth' `
            -Value (ConvertTo-RenderKitMetadataInt64 -Value (
                Get-RenderKitMetadataPropertyValue -Object $video -Name @('BitDepth')
            ))
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'ScanType' `
            -Value (Get-RenderKitMetadataPropertyValue -Object $video -Name @('ScanType'))
    }

    if ($audio) {
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'AudioFormat' `
            -Value (Get-RenderKitMetadataPropertyValue -Object $audio -Name @('Format'))
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'AudioCodecId' `
            -Value (Get-RenderKitMetadataPropertyValue -Object $audio -Name @('CodecID'))
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'AudioChannels' `
            -Value (ConvertTo-RenderKitMetadataInt64 -Value (
                Get-RenderKitMetadataPropertyValue -Object $audio -Name @('Channels', 'Channel_s_')
            ))
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'AudioChannelLayout' `
            -Value (Get-RenderKitMetadataPropertyValue -Object $audio -Name @('ChannelLayout'))
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'AudioSampleRate' `
            -Value (ConvertTo-RenderKitMetadataInt64 -Value (
                Get-RenderKitMetadataPropertyValue -Object $audio -Name @('SamplingRate')
            ))
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'AudioBitDepth' `
            -Value (ConvertTo-RenderKitMetadataInt64 -Value (
                Get-RenderKitMetadataPropertyValue -Object $audio -Name @('BitDepth')
            ))
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'AudioBitRate' `
            -Value (ConvertTo-RenderKitMetadataInt64 -Value (
                Get-RenderKitMetadataPropertyValue -Object $audio -Name @('BitRate')
            ))
    }

    if ($image) {
        $imageWidth = ConvertTo-RenderKitMetadataInt64 `
            -Value (Get-RenderKitMetadataPropertyValue -Object $image -Name @('Width'))
        $imageHeight = ConvertTo-RenderKitMetadataInt64 `
            -Value (Get-RenderKitMetadataPropertyValue -Object $image -Name @('Height'))
        Set-RenderKitMetadataFieldValue -Fields $fields -Name 'ImageWidth' -Value $imageWidth
        Set-RenderKitMetadataFieldValue -Fields $fields -Name 'ImageHeight' -Value $imageHeight
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'ImageFormat' `
            -Value (Get-RenderKitMetadataPropertyValue -Object $image -Name @('Format'))
    }

    return $fields
}

function ConvertFrom-RenderKitExifToolMetadata {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Raw
    )

    $fields = [ordered]@{}
    if ($Raw -is [array]) {
        $Raw = @($Raw | Select-Object -First 1)
    }
    if (-not $Raw) {
        return $fields
    }

    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'MimeType' `
        -Value (Get-RenderKitMetadataPropertyValue -Object $Raw -Name @('MIMEType'))
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'Rating' `
        -Value (Get-RenderKitMetadataPropertyValue -Object $Raw -Name @('Rating'))
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'Title' `
        -Value (Get-RenderKitMetadataPropertyValue -Object $Raw -Name @('Title', 'ObjectName'))
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'Description' `
        -Value (Get-RenderKitMetadataPropertyValue -Object $Raw -Name @('Description', 'Caption-Abstract'))
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'Author' `
        -Value (Get-RenderKitMetadataPropertyValue -Object $Raw -Name @('Author', 'Creator', 'Artist'))
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'CopyrightNotice' `
        -Value (Get-RenderKitMetadataPropertyValue -Object $Raw -Name @('Copyright', 'CopyrightNotice'))
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'Keywords' `
        -Value (Get-RenderKitMetadataPropertyValue -Object $Raw -Name @('Keywords', 'Subject'))

    $createDate = Get-RenderKitMetadataPropertyValue `
        -Object $Raw `
        -Name @('DateTimeOriginal', 'CreateDate', 'MediaCreateDate', 'DateCreated')
    Set-RenderKitMetadataFieldValue -Fields $fields -Name 'DateCreated' -Value $createDate
    Set-RenderKitMetadataFieldValue -Fields $fields -Name 'DateOriginal' -Value $createDate
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'ModifyDateEmbedded' `
        -Value (Get-RenderKitMetadataPropertyValue -Object $Raw -Name @('ModifyDate'))

    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'ImageWidth' `
        -Value (ConvertTo-RenderKitMetadataInt64 -Value (
            Get-RenderKitMetadataPropertyValue -Object $Raw -Name @('ImageWidth', 'ExifImageWidth')
        ))
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'ImageHeight' `
        -Value (ConvertTo-RenderKitMetadataInt64 -Value (
            Get-RenderKitMetadataPropertyValue -Object $Raw -Name @('ImageHeight', 'ExifImageHeight')
        ))
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'ImageFormat' `
        -Value (Get-RenderKitMetadataPropertyValue -Object $Raw -Name @('FileType', 'FileTypeExtension'))
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'Orientation' `
        -Value (Get-RenderKitMetadataPropertyValue -Object $Raw -Name @('Orientation'))
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'RotationDegrees' `
        -Value (ConvertTo-RenderKitMetadataInt64 -Value (
            Get-RenderKitMetadataPropertyValue -Object $Raw -Name @('Rotation')
        ))

    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'CameraManufacturer' `
        -Value (Get-RenderKitMetadataPropertyValue -Object $Raw -Name @('Make'))
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'CameraModel' `
        -Value (Get-RenderKitMetadataPropertyValue -Object $Raw -Name @('Model', 'CameraModelName'))
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'CameraSerialNumber' `
        -Value (Get-RenderKitMetadataPropertyValue -Object $Raw -Name @('SerialNumber', 'CameraSerialNumber'))
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'LensModel' `
        -Value (Get-RenderKitMetadataPropertyValue -Object $Raw -Name @('LensModel', 'LensID'))
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'Iso' `
        -Value (ConvertTo-RenderKitMetadataInt64 -Value (
            Get-RenderKitMetadataPropertyValue -Object $Raw -Name @('ISO', 'ISOSpeedRatings')
        ))
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'ExposureTimeSeconds' `
        -Value (ConvertTo-RenderKitMetadataNumber -Value (
            Get-RenderKitMetadataPropertyValue -Object $Raw -Name @('ExposureTime', 'ShutterSpeed')
        ))
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'FNumber' `
        -Value (ConvertTo-RenderKitMetadataNumber -Value (
            Get-RenderKitMetadataPropertyValue -Object $Raw -Name @('FNumber', 'Aperture')
        ))
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'FocalLengthMm' `
        -Value (ConvertTo-RenderKitMetadataNumber -Value (
            Get-RenderKitMetadataPropertyValue -Object $Raw -Name @('FocalLength')
        ))

    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'VideoFrameRate' `
        -Value (ConvertTo-RenderKitMetadataNumber -Value (
            Get-RenderKitMetadataPropertyValue -Object $Raw -Name @('VideoFrameRate', 'FrameRate')
        ))
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'VideoWidth' `
        -Value (ConvertTo-RenderKitMetadataInt64 -Value (
            Get-RenderKitMetadataPropertyValue -Object $Raw -Name @('SourceImageWidth', 'ImageWidth')
        ))
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'VideoHeight' `
        -Value (ConvertTo-RenderKitMetadataInt64 -Value (
            Get-RenderKitMetadataPropertyValue -Object $Raw -Name @('SourceImageHeight', 'ImageHeight')
        ))

    return $fields
}

function Invoke-RenderKitMediaInfoMetadataRead {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [object]$Reader,

        [string]$CommandPath
    )

    $errors = New-Object System.Collections.Generic.List[string]
    if (-not $Reader) {
        $Reader = [PSCustomObject]@{
            NativeCandidates = @()
            HostCandidates = @()
            CliCandidates = if ([string]::IsNullOrWhiteSpace($CommandPath)) { @() } else {
                @([PSCustomObject]@{
                    Kind = 'Cli'
                    Source = 'Explicit'
                    Path = $CommandPath
                    DisplayName = $CommandPath
                    Available = $true
                })
            }
        }
    }

    foreach ($candidate in @($Reader.NativeCandidates)) {
        if (-not [bool]$candidate.Available) { continue }
        try {
            $raw = Invoke-RenderKitMediaInfoNativeMetadataRead `
                -Path $Path `
                -LibraryPath ([string]$candidate.Path)
            return [PSCustomObject]@{
                Raw = $raw
                Backend = 'Native'
                Source = [string]$candidate.Source
                Path = [string]$candidate.Path
                Errors = @($errors.ToArray())
            }
        }
        catch {
            $errors.Add("native/$($candidate.Source) failed: $($_.Exception.Message)")
        }
    }

    foreach ($candidate in @($Reader.HostCandidates)) {
        if (-not [bool]$candidate.Available) { continue }
        try {
            $output = & ([string]$candidate.Path) mediainfo read --json $Path 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "host exited with code $LASTEXITCODE`: $($output -join "`n")"
            }
            $raw = ($output -join "`n") | ConvertFrom-Json -ErrorAction Stop
            return [PSCustomObject]@{
                Raw = $raw
                Backend = 'Host'
                Source = [string]$candidate.Source
                Path = [string]$candidate.Path
                Errors = @($errors.ToArray())
            }
        }
        catch {
            $errors.Add("host/$($candidate.Source) failed: $($_.Exception.Message)")
        }
    }

    $cliCandidates = @($Reader.CliCandidates)
    if ($cliCandidates.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($CommandPath)) {
        $cliCandidates = @([PSCustomObject]@{
            Kind = 'Cli'
            Source = 'Explicit'
            Path = $CommandPath
            DisplayName = $CommandPath
            Available = $true
        })
    }

    foreach ($candidate in $cliCandidates) {
        if (-not [bool]$candidate.Available) { continue }
        try {
            $output = & ([string]$candidate.Path) --Output=JSON --Full $Path 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "cli exited with code $LASTEXITCODE`: $($output -join "`n")"
            }
            $raw = ($output -join "`n") | ConvertFrom-Json -ErrorAction Stop
            return [PSCustomObject]@{
                Raw = $raw
                Backend = 'Cli'
                Source = [string]$candidate.Source
                Path = [string]$candidate.Path
                Errors = @($errors.ToArray())
            }
        }
        catch {
            $errors.Add("cli/$($candidate.Source) failed: $($_.Exception.Message)")
        }
    }

    if ($errors.Count -gt 0) {
        throw "MediaInfo failed through all configured backends: $($errors -join '; ')"
    }

    throw 'MediaInfo is not available. Configure RENDERKIT_MEDIAINFO_LIBRARY, add bundled MediaInfo assets, set RENDERKIT_MEDIAINFO_PATH, or install mediainfo on PATH.'
}

function Invoke-RenderKitExifToolMetadataRead {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$CommandPath
    )

    $output = & $CommandPath -json -G1 -a -n -api LargeFileSupport=1 $Path 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "ExifTool failed with exit code $LASTEXITCODE`: $($output -join "`n")"
    }
    return ($output -join "`n") | ConvertFrom-Json -ErrorAction Stop
}

function Get-RenderKitFileSystemMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$File,

        [Parameter(Mandatory)]
        [object]$Route
    )

    $fields = [ordered]@{}
    Set-RenderKitMetadataFieldValue -Fields $fields -Name 'FileName' -Value $File.Name
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'BaseName' `
        -Value ([System.IO.Path]::GetFileNameWithoutExtension($File.Name))
    Set-RenderKitMetadataFieldValue -Fields $fields -Name 'Extension' -Value $File.Extension
    Set-RenderKitMetadataFieldValue -Fields $fields -Name 'FilePath' -Value $File.FullName
    Set-RenderKitMetadataFieldValue -Fields $fields -Name 'DirectoryPath' -Value $File.DirectoryName
    Set-RenderKitMetadataFieldValue -Fields $fields -Name 'FileSizeBytes' -Value ([int64]$File.Length)
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'FileSizeHuman' `
        -Value (ConvertTo-RenderKitHumanSize -Bytes ([int64]$File.Length))
    Set-RenderKitMetadataFieldValue -Fields $fields -Name 'CreatedAtFileSystem' -Value $File.CreationTimeUtc
    Set-RenderKitMetadataFieldValue -Fields $fields -Name 'ModifiedAtFileSystem' -Value $File.LastWriteTimeUtc
    Set-RenderKitMetadataFieldValue -Fields $fields -Name 'AccessedAtFileSystem' -Value $File.LastAccessTimeUtc
    Set-RenderKitMetadataFieldValue -Fields $fields -Name 'IsReadOnly' -Value $File.IsReadOnly
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'IsHidden' `
        -Value ([bool]($File.Attributes -band [System.IO.FileAttributes]::Hidden))
    Set-RenderKitMetadataFieldValue -Fields $fields -Name 'MediaKind' -Value ([string]$Route.MediaKind)
    Set-RenderKitMetadataFieldValue -Fields $fields -Name 'MimeType' -Value ([string]$Route.MimeType)

    return $fields
}

function Merge-RenderKitMetadataFieldBag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Target,

        [AllowNull()]
        [System.Collections.IDictionary]$Source
    )

    if (-not $Source) { return }
    foreach ($key in @($Source.Keys)) {
        Set-RenderKitMetadataFieldValue `
            -Fields $Target `
            -Name ([string]$key) `
            -Value $Source[$key]
    }
}

function Read-RenderKitFileMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$ProjectRoot,

        [string[]]$Field,

        [switch]$IncludeRaw,

        [switch]$NoExternalAdapters
    )

    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file.PSIsContainer) {
        throw "Metadata can only be read from files. '$Path' is a directory."
    }

    $route = Resolve-RenderKitMetadataAdapterRoute -Path $file.FullName
    $fields = [ordered]@{}
    $raw = [ordered]@{}
    $warnings = New-Object System.Collections.Generic.List[string]

    Merge-RenderKitMetadataFieldBag `
        -Target $fields `
        -Source (Get-RenderKitFileSystemMetadata -File $file -Route $route)

    if (-not $NoExternalAdapters) {
        foreach ($reader in @($route.Readers)) {
            if (-not [bool]$reader.Available) {
                $warnings.Add("Metadata reader '$($reader.Id)' is not available through native, bundled, host, or CLI resolution.")
                continue
            }

            try {
                switch ([string]$reader.Id) {
                    'MediaInfo' {
                        $mediaInfoRead = Invoke-RenderKitMediaInfoMetadataRead `
                            -Path $file.FullName `
                            -Reader $reader `
                            -CommandPath ([string]$reader.CommandPath)
                        $readerRaw = $mediaInfoRead.Raw
                        $raw['MediaInfo'] = $readerRaw
                        $raw['MediaInfoBackend'] = [PSCustomObject]@{
                            Backend = [string]$mediaInfoRead.Backend
                            Source = [string]$mediaInfoRead.Source
                            Path = [string]$mediaInfoRead.Path
                            FallbackErrors = @($mediaInfoRead.Errors)
                        }
                        Merge-RenderKitMetadataFieldBag `
                            -Target $fields `
                            -Source (ConvertFrom-RenderKitMediaInfoMetadata -Raw $readerRaw)
                    }
                    'ExifTool' {
                        $readerRaw = Invoke-RenderKitExifToolMetadataRead `
                            -Path $file.FullName `
                            -CommandPath ([string]$reader.CommandPath)
                        $raw['ExifTool'] = $readerRaw
                        Merge-RenderKitMetadataFieldBag `
                            -Target $fields `
                            -Source (ConvertFrom-RenderKitExifToolMetadata -Raw $readerRaw)
                    }
                    default {
                        $warnings.Add("Metadata reader '$($reader.Id)' has no MVP reader implementation.")
                    }
                }
            }
            catch {
                $warnings.Add("Metadata reader '$($reader.Id)' failed: $($_.Exception.Message)")
            }
        }
    }

    if ($Field -and $Field.Count -gt 0) {
        $selected = [ordered]@{}
        foreach ($name in $Field) {
            if ($fields.Contains($name)) {
                Set-RenderKitMetadataFieldValue `
                    -Fields $selected `
                    -Name $name `
                    -Value $fields[$name]
            }
        }
        $fields = $selected
    }

    return [PSCustomObject]@{
        Path = $file.FullName
        ProjectRoot = if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $null } else { [System.IO.Path]::GetFullPath($ProjectRoot) }
        FileName = $file.Name
        MediaKind = [string]$route.MediaKind
        Extension = [string]$route.Extension
        MimeType = [string]$route.MimeType
        IsSupported = [bool]$route.IsSupported
        AdapterIds = @($route.AdapterIds)
        Readers = @($route.Readers)
        Fields = [PSCustomObject]$fields
        Warnings = @($warnings.ToArray())
        Raw = if ($IncludeRaw) { [PSCustomObject]$raw } else { $null }
    }
}

function Update-RenderKitProjectMetadataCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [ValidateRange(1, 64)]
        [int]$ThrottleLimit = 4,

        [switch]$IncludeUnsupported
    )

    $resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot -ErrorAction Stop).ProviderPath
    $files = @(
        Get-ChildItem -LiteralPath $resolvedProjectRoot -File -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object {
                $relative = ConvertTo-RenderKitProjectRelativePath `
                    -BasePath $resolvedProjectRoot `
                    -Path $_.FullName
                if ($relative -like '.renderkit/*') { return $false }
                if ($IncludeUnsupported) { return $true }
                $route = Resolve-RenderKitMetadataAdapterRoute -Path $_.FullName
                return [bool]$route.IsSupported
            }
    )

    $startedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    $results = New-Object System.Collections.Generic.List[object]
    $modulePath = Join-Path -Path $script:RenderKitModuleRoot -ChildPath 'RenderKit.psd1'
    $threadJobCommand = Get-Command -Name Start-ThreadJob -ErrorAction SilentlyContinue

    if ($threadJobCommand -and $ThrottleLimit -gt 1 -and $files.Count -gt 1) {
        $jobs = foreach ($file in $files) {
            Start-ThreadJob `
                -ThrottleLimit $ThrottleLimit `
                -ArgumentList $modulePath, $file.FullName, $resolvedProjectRoot `
                -ScriptBlock {
                    param($ModulePath, $Path, $ProjectRoot)
                    Import-Module $ModulePath -Force
                    try {
                        $result = Get-Metadata `
                            -Path $Path `
                            -ProjectRoot $ProjectRoot `
                            -Store `
                            -IncludeMetadata
                        [PSCustomObject]@{
                            Path = $Path
                            Status = 'Succeeded'
                            MetadataVersion = [int]$result.MetadataVersion
                            StorePath = [string]$result.StorePath
                            Error = $null
                        }
                    }
                    catch {
                        [PSCustomObject]@{
                            Path = $Path
                            Status = 'Failed'
                            MetadataVersion = $null
                            StorePath = $null
                            Error = $_.Exception.Message
                        }
                    }
                }
        }
        if ($jobs) {
            Wait-Job -Job $jobs | Out-Null
            foreach ($job in $jobs) {
                foreach ($item in @(Receive-Job -Job $job)) {
                    $results.Add($item)
                }
                Remove-Job -Job $job -Force
            }
        }
        $parallel = $true
    }
    else {
        foreach ($file in $files) {
            try {
                $result = Get-Metadata `
                    -Path $file.FullName `
                    -ProjectRoot $resolvedProjectRoot `
                    -Store `
                    -IncludeMetadata
                $results.Add([PSCustomObject]@{
                    Path = $file.FullName
                    Status = 'Succeeded'
                    MetadataVersion = [int]$result.MetadataVersion
                    StorePath = [string]$result.StorePath
                    Error = $null
                })
            }
            catch {
                $results.Add([PSCustomObject]@{
                    Path = $file.FullName
                    Status = 'Failed'
                    MetadataVersion = $null
                    StorePath = $null
                    Error = $_.Exception.Message
                })
            }
        }
        $parallel = $false
    }

    $endedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    return [PSCustomObject]@{
        ProjectRoot = $resolvedProjectRoot
        StartedAtUtc = $startedAtUtc
        EndedAtUtc = $endedAtUtc
        ThrottleLimit = $ThrottleLimit
        Parallel = [bool]$parallel
        Total = $files.Count
        Succeeded = @($results | Where-Object { $_.Status -eq 'Succeeded' }).Count
        Failed = @($results | Where-Object { $_.Status -eq 'Failed' }).Count
        Results = @($results.ToArray())
    }
}
