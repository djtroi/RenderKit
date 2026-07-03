function Get-RenderKitTagLibSharpBundleRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return Join-Path -Path $script:RenderKitModuleRoot `
        -ChildPath 'src/Resources/ThirdParty/TagLibSharp'
}

function Read-RenderKitTagLibSharpManifest {
    [CmdletBinding()]
    param()

    if ($script:RenderKitTagLibSharpManifest) {
        return $script:RenderKitTagLibSharpManifest
    }

    $path = Join-Path `
        -Path (Get-RenderKitTagLibSharpBundleRoot) `
        -ChildPath 'manifest.json'
    $manifest = Read-RenderKitJsonFile `
        -Path $path `
        -MaximumBytes 262144 `
        -Validator {
            param($value)
            [string]$value.artifactType -eq 'ThirdPartyMetadataBundle' -and
                [string]$value.name -eq 'TagLibSharp' -and
                @($value.assemblies).Count -gt 0
        }
    $script:RenderKitTagLibSharpManifest = $manifest
    return $manifest
}

function Resolve-RenderKitTagLibSharpRuntime {
    [CmdletBinding()]
    param()

    $manifest = Read-RenderKitTagLibSharpManifest
    $target = if ($PSVersionTable.PSEdition -eq 'Desktop') {
        'net462'
    }
    else {
        'netstandard2.0'
    }
    $definition = @(
        $manifest.assemblies |
            Where-Object { [string]$_.target -eq $target } |
            Select-Object -First 1
    )
    if (-not $definition) {
        return [PSCustomObject]@{
            Available = $false
            Source = 'Bundled'
            Path = $null
            Target = $target
            Version = [string]$manifest.componentVersion
            Error = "The TagLibSharp manifest has no '$target' assembly."
        }
    }

    $source = 'Bundled'
    $path = if (-not [string]::IsNullOrWhiteSpace(
            [string]$env:RENDERKIT_TAGLIBSHARP_PATH)) {
        $source = 'Environment'
        [System.IO.Path]::GetFullPath(
            [string]$env:RENDERKIT_TAGLIBSHARP_PATH
        )
    }
    else {
        Join-Path `
            -Path (Get-RenderKitTagLibSharpBundleRoot) `
            -ChildPath ([string]$definition.relativePath)
    }

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [PSCustomObject]@{
            Available = $false
            Source = $source
            Path = $path
            Target = $target
            Version = [string]$manifest.componentVersion
            Error = "TagLibSharp was not found at '$path'."
        }
    }

    $actualHash = (
        Get-FileHash -LiteralPath $path -Algorithm SHA256
    ).Hash.ToUpperInvariant()
    $expectedHashes = @(
        $manifest.assemblies |
            ForEach-Object {
                ([string]$_.sha256).ToUpperInvariant()
            }
    )
    if ($expectedHashes -notcontains $actualHash) {
        return [PSCustomObject]@{
            Available = $false
            Source = $source
            Path = $path
            Target = $target
            Version = [string]$manifest.componentVersion
            Hash = $actualHash
            Error = "TagLibSharp at '$path' failed the bundled SHA-256 check."
        }
    }

    return [PSCustomObject]@{
        Available = $true
        Source = $source
        Path = $path
        Target = $target
        Version = [string]$manifest.componentVersion
        Hash = $actualHash
        Error = $null
    }
}

function Import-RenderKitTagLibSharpRuntime {
    [CmdletBinding()]
    param()

    $loaded = @(
        [AppDomain]::CurrentDomain.GetAssemblies() |
            Where-Object {
                [string]$_.GetName().Name -eq 'TagLibSharp'
            } |
            Select-Object -First 1
    )
    if ($loaded) {
        return [PSCustomObject]@{
            Available = $true
            Source = 'Loaded'
            Path = [string]$loaded.Location
            Target = $null
            Version = [string]$loaded.GetName().Version
            Hash = if (-not [string]::IsNullOrWhiteSpace(
                    [string]$loaded.Location) -and
                (Test-Path -LiteralPath $loaded.Location -PathType Leaf)) {
                (
                    Get-FileHash `
                        -LiteralPath $loaded.Location `
                        -Algorithm SHA256
                ).Hash.ToUpperInvariant()
            }
            else {
                $null
            }
            Error = $null
        }
    }

    $runtime = Resolve-RenderKitTagLibSharpRuntime
    if (-not [bool]$runtime.Available) {
        throw [string]$runtime.Error
    }
    Add-Type -LiteralPath ([string]$runtime.Path) -ErrorAction Stop
    return $runtime
}

function Test-RenderKitTagLibSharpId3Path {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return @('.mp3', '.mp2', '.aac', '.tta') -contains
        [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
}

function Get-RenderKitTagLibSharpMetadataWriteDefinitions {
    [CmdletBinding()]
    param(
        [ValidateSet('ID3', 'Matroska')]
        [string]$Profile,

        [string]$Field
    )

    $profiles = if ([string]::IsNullOrWhiteSpace($Profile)) {
        @('ID3', 'Matroska')
    }
    else {
        @($Profile)
    }
    $definitions = New-Object System.Collections.Generic.List[object]
    foreach ($profileName in $profiles) {
        $map = Read-RenderKitAudioContainerMetadataProfileMap `
            -Profile $profileName
        if ([string]$map.writeCapability.adapter -ne 'TagLibSharp') {
            continue
        }
        foreach ($definition in @($map.writeFields)) {
            if (-not [string]::IsNullOrWhiteSpace($Field) -and
                [string]$definition.field -ine $Field) {
                continue
            }
            $definitions.Add([PSCustomObject]@{
                Profile = $profileName
                Field = [string]$definition.field
                Target = [string]$definition.target
                ValueType = [string]$definition.valueType
            })
        }
    }
    return @($definitions.ToArray())
}

function Get-RenderKitTagLibSharpEmbeddedMetadataWriteCapability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Field,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $profile = if (Test-RenderKitTagLibSharpId3Path -Path $Path) {
        'ID3'
    }
    elseif (@('.mkv', '.mka', '.mks', '.webm') -contains
        [System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        'Matroska'
    }
    else {
        return $null
    }

    $definitions = @(
        Get-RenderKitTagLibSharpMetadataWriteDefinitions `
            -Profile $profile `
            -Field $Field
    )
    if ($definitions.Count -eq 0) {
        return $null
    }

    return [PSCustomObject]@{
        field = $Field
        adapter = 'TagLibSharp'
        tags = @($definitions | ForEach-Object {
            '{0}:{1}' -f $_.Profile, $_.Target
        })
        mediaKinds = @('Audio', 'Video')
        fieldType = $null
        standards = @($profile)
        writeMode = 'AtomicTagLibrary'
        structureMembers = $null
        controlledVocabulary = $null
    }
}

function Get-RenderKitTagLibObjectMember {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string[]]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }
    foreach ($candidate in $Name) {
        if ($InputObject -is [System.Collections.IDictionary]) {
            $key = @(
                $InputObject.Keys |
                    Where-Object { [string]$_ -ieq $candidate } |
                    Select-Object -First 1
            )
            if ($key) {
                return $InputObject[$key[0]]
            }
        }
        else {
            $property = @(
                $InputObject.PSObject.Properties |
                    Where-Object { [string]$_.Name -ieq $candidate } |
                    Select-Object -First 1
            )
            if ($property) {
                return $property.Value
            }
        }
    }
    return $null
}

function Get-RenderKitTagLibMetadataValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Metadata,

        [Parameter(Mandatory)]
        [string]$Field,

        [ref]$Found
    )

    $key = @(
        $Metadata.Keys |
            Where-Object { [string]$_ -ieq $Field } |
            Select-Object -First 1
    )
    $Found.Value = $key.Count -gt 0
    if (-not $Found.Value) {
        return $null
    }
    return $Metadata[$key[0]]
}

function ConvertTo-RenderKitTagLibComparableJson {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return 'null'
    }
    if ($Value -is [string] -or
        $Value -is [ValueType]) {
        return ([string]$Value).Trim()
    }
    return $Value |
        ConvertTo-Json -Depth 30 -Compress |
        ForEach-Object { [string]$_ }
}

function Resolve-RenderKitTagLibAliasValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Metadata,

        [Parameter(Mandatory)]
        [string[]]$Field,

        [Parameter(Mandatory)]
        [string]$Target,

        [ref]$Found
    )

    $selectedValue = $null
    $selectedField = $null
    $Found.Value = $false
    foreach ($name in $Field) {
        $hasValue = $false
        $value = Get-RenderKitTagLibMetadataValue `
            -Metadata $Metadata `
            -Field $name `
            -Found ([ref]$hasValue)
        if (-not $hasValue) {
            continue
        }
        if (-not $Found.Value) {
            $Found.Value = $true
            $selectedValue = $value
            $selectedField = $name
            continue
        }
        if ((ConvertTo-RenderKitTagLibComparableJson -Value $selectedValue) -ne
            (ConvertTo-RenderKitTagLibComparableJson -Value $value)) {
            throw "Conflicting values for ID3 target '$Target' were supplied by '$selectedField' and '$name'."
        }
    }
    return $selectedValue
}

function ConvertTo-RenderKitTagLibStringArray {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return @()
    }
    $values = if ($Value -is [System.Collections.IEnumerable] -and
        -not ($Value -is [string]) -and
        -not ($Value -is [System.Collections.IDictionary])) {
        @($Value)
    }
    else {
        @($Value)
    }
    return @(
        $values |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function ConvertTo-RenderKitTagLibUInt32 {
    [CmdletBinding()]
    [OutputType([uint32])]
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Field
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return [uint32]0
    }
    $parsed = [uint32]0
    if (-not [uint32]::TryParse(
            ([string]$Value).Trim(),
            [Globalization.NumberStyles]::Integer,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$parsed)) {
        throw "ID3 field '$Field' must be an unsigned 32-bit integer."
    }
    return $parsed
}

function ConvertTo-RenderKitTagLibDateText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return ''
    }
    if ($Value -is [datetime]) {
        return $Value.ToString(
            'yyyy-MM-ddTHH:mm:ssK',
            [Globalization.CultureInfo]::InvariantCulture
        )
    }
    return ([string]$Value).Trim()
}

function Get-RenderKitId3FrameId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Z0-9]{4}$')]
        [string]$Id
    )

    return ,([TagLib.ByteVector]::FromString(
            $Id,
            [TagLib.StringType]::Latin1
        ))
}

function Set-RenderKitId3TextFrame {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Tag,

        [Parameter(Mandatory)]
        [string]$Id,

        [AllowNull()]
        [object]$Value
    )

    $frameId = Get-RenderKitId3FrameId -Id $Id
    $values = ConvertTo-RenderKitTagLibStringArray -Value $Value
    if ($values.Count -eq 0) {
        $Tag.RemoveFrames($frameId)
        return
    }
    $Tag.SetTextFrame($frameId, [string[]]$values)
}

function Set-RenderKitId3UserTextFrame {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Tag,

        [Parameter(Mandatory)]
        [string]$Description,

        [AllowNull()]
        [object]$Value
    )

    $values = ConvertTo-RenderKitTagLibStringArray -Value $Value
    $frame = [TagLib.Id3v2.UserTextInformationFrame]::Get(
        $Tag,
        $Description,
        [TagLib.StringType]::UTF8,
        $true,
        $true
    )
    if ($values.Count -eq 0) {
        if ($frame) {
            $Tag.RemoveFrame($frame)
        }
        return
    }
    $frame.Text = [string[]]$values
}

function Set-RenderKitId3UrlFrame {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Tag,

        [Parameter(Mandatory)]
        [string]$Id,

        [AllowNull()]
        [object]$Value
    )

    $frameId = Get-RenderKitId3FrameId -Id $Id
    $values = ConvertTo-RenderKitTagLibStringArray -Value $Value
    if ($values.Count -eq 0) {
        $Tag.RemoveFrames($frameId)
        return
    }
    $frame = [TagLib.Id3v2.UrlLinkFrame]::Get(
        $Tag,
        $frameId,
        $true
    )
    $frame.Text = [string[]]$values
}

function Set-RenderKitId3ArrangerFrame {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Tag,

        [AllowNull()]
        [object]$Value
    )

    $frameId = Get-RenderKitId3FrameId -Id 'TIPL'
    $frame = [TagLib.Id3v2.TextInformationFrame]::Get(
        $Tag,
        $frameId,
        [TagLib.StringType]::UTF8,
        $true
    )
    $items = New-Object System.Collections.Generic.List[string]
    $existing = @($frame.Text)
    for ($index = 0; $index + 1 -lt $existing.Count; $index += 2) {
        if ([string]$existing[$index] -ine 'Arranger') {
            $items.Add([string]$existing[$index])
            $items.Add([string]$existing[$index + 1])
        }
    }
    foreach ($arranger in @(
            ConvertTo-RenderKitTagLibStringArray -Value $Value
        )) {
        $items.Add('Arranger')
        $items.Add($arranger)
    }
    if ($items.Count -eq 0) {
        $Tag.RemoveFrames($frameId)
    }
    else {
        $frame.Text = [string[]]$items.ToArray()
    }
}

function ConvertTo-RenderKitId3Language {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$Value,

        [string]$Fallback = 'und'
    )

    $text = ([string]$Value).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $Fallback
    }
    if ($text -notmatch '^[a-z]{3}$') {
        throw "ID3 lyric language '$text' must be a three-letter ISO 639-2 code."
    }
    return $text
}

function Set-RenderKitId3Lyrics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Tag,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Metadata
    )

    $hasLyrics = $false
    $lyrics = Get-RenderKitTagLibMetadataValue `
        -Metadata $Metadata `
        -Field 'Lyrics' `
        -Found ([ref]$hasLyrics)
    $hasLanguage = $false
    $languageValue = Get-RenderKitTagLibMetadataValue `
        -Metadata $Metadata `
        -Field 'LyricsLanguage' `
        -Found ([ref]$hasLanguage)
    if (-not $hasLyrics -and -not $hasLanguage) {
        return
    }

    $frames = @(
        $Tag.GetFrames[
            TagLib.Id3v2.UnsynchronisedLyricsFrame
        ]()
    )
    $existing = @($frames | Select-Object -First 1)
    $language = ConvertTo-RenderKitId3Language `
        -Value $languageValue `
        -Fallback $(if ($existing) {
            ConvertTo-RenderKitId3Language `
                -Value $existing.Language `
                -Fallback 'und'
        }
        else {
            'und'
        })

    if ($hasLyrics) {
        foreach ($frame in $frames) {
            $Tag.RemoveFrame($frame)
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$lyrics)) {
            $frame = [TagLib.Id3v2.UnsynchronisedLyricsFrame]::new(
                '',
                $language,
                [TagLib.StringType]::UTF8
            )
            $frame.Text = [string]$lyrics
            $Tag.AddFrame($frame)
        }
    }
    elseif ($hasLanguage) {
        foreach ($frame in $frames) {
            $frame.Language = $language
        }
    }
}

function ConvertTo-RenderKitId3TimestampMilliseconds {
    [CmdletBinding()]
    [OutputType([uint32])]
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Field
    )

    if ($Value -is [timespan]) {
        $milliseconds = $Value.TotalMilliseconds
    }
    elseif ([string]$Value -match '^\d{1,2}:\d{2}(:\d{2})?(\.\d+)?$') {
        $parsed = [timespan]::Zero
        if (-not [timespan]::TryParse(
                [string]$Value,
                [Globalization.CultureInfo]::InvariantCulture,
                [ref]$parsed)) {
            throw "ID3 field '$Field' contains an invalid timestamp."
        }
        $milliseconds = $parsed.TotalMilliseconds
    }
    else {
        $milliseconds = [double]0
        if (-not [double]::TryParse(
                ([string]$Value).Trim(),
                [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture,
                [ref]$milliseconds)) {
            throw "ID3 field '$Field' must be milliseconds or a time span."
        }
    }
    if ($milliseconds -lt 0 -or $milliseconds -gt [uint32]::MaxValue) {
        throw "ID3 field '$Field' is outside the supported millisecond range."
    }
    return [uint32][Math]::Round(
        $milliseconds,
        0,
        [MidpointRounding]::AwayFromZero
    )
}

function Set-RenderKitId3SynchronizedLyrics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Tag,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Metadata
    )

    $hasValue = $false
    $value = Get-RenderKitTagLibMetadataValue `
        -Metadata $Metadata `
        -Field 'SynchronizedLyrics' `
        -Found ([ref]$hasValue)
    if (-not $hasValue) {
        return
    }

    $frameId = Get-RenderKitId3FrameId -Id 'SYLT'
    $Tag.RemoveFrames($frameId)
    $items = if ($value -is [System.Collections.IEnumerable] -and
        -not ($value -is [string]) -and
        -not ($value -is [System.Collections.IDictionary])) {
        @($value)
    }
    elseif ($null -eq $value) {
        @()
    }
    else {
        @($value)
    }
    if ($items.Count -eq 0) {
        return
    }

    $hasLanguage = $false
    $languageValue = Get-RenderKitTagLibMetadataValue `
        -Metadata $Metadata `
        -Field 'LyricsLanguage' `
        -Found ([ref]$hasLanguage)
    $language = ConvertTo-RenderKitId3Language -Value $languageValue
    $lines = New-Object 'System.Collections.Generic.List[TagLib.Id3v2.SynchedText]'
    foreach ($item in $items) {
        $time = Get-RenderKitTagLibObjectMember `
            -InputObject $item `
            -Name @(
                'TimestampMilliseconds',
                'TimeMilliseconds',
                'Timestamp',
                'Time'
            )
        $text = Get-RenderKitTagLibObjectMember `
            -InputObject $item `
            -Name @('Text', 'Lyric')
        if ($null -eq $time -or
            [string]::IsNullOrWhiteSpace([string]$text)) {
            throw 'Each synchronized lyric line requires timestamp and text.'
        }
        $milliseconds = ConvertTo-RenderKitId3TimestampMilliseconds `
            -Value $time `
            -Field 'SynchronizedLyrics'
        $lines.Add(
            [TagLib.Id3v2.SynchedText]::new(
                [int64]$milliseconds,
                [string]$text
            )
        )
    }

    $frame = [TagLib.Id3v2.SynchronisedLyricsFrame]::new(
        '',
        $language,
        [TagLib.Id3v2.SynchedTextType]::Lyrics,
        [TagLib.StringType]::UTF8
    )
    $frame.Format = [TagLib.Id3v2.TimestampFormat]::AbsoluteMilliseconds
    $frame.Text = [TagLib.Id3v2.SynchedText[]]$lines.ToArray()
    $Tag.AddFrame($frame)
}

function ConvertTo-RenderKitId3Picture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Value,

        [string]$DefaultType = 'Other'
    )

    $path = if ($Value -is [string]) {
        [string]$Value
    }
    else {
        [string](Get-RenderKitTagLibObjectMember `
            -InputObject $Value `
            -Name @('Path', 'FilePath'))
    }
    if ([string]::IsNullOrWhiteSpace($path)) {
        throw 'Each ID3 picture requires a filesystem path.'
    }
    $resolvedPath = (
        Resolve-Path -LiteralPath $path -ErrorAction Stop
    ).ProviderPath
    $picture = [TagLib.Picture]::CreateFromPath($resolvedPath)
    $mime = if ($Value -is [string]) {
        $null
    }
    else {
        Get-RenderKitTagLibObjectMember `
            -InputObject $Value `
            -Name @('Mime', 'MimeType')
    }
    $description = if ($Value -is [string]) {
        $null
    }
    else {
        Get-RenderKitTagLibObjectMember `
            -InputObject $Value `
            -Name @('Description')
    }
    $type = if ($Value -is [string]) {
        $DefaultType
    }
    else {
        Get-RenderKitTagLibObjectMember `
            -InputObject $Value `
            -Name @('Type', 'PictureType')
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$mime)) {
        $picture.MimeType = ([string]$mime).Trim()
    }
    if ($null -ne $description) {
        $picture.Description = [string]$description
    }
    if ([string]::IsNullOrWhiteSpace([string]$type)) {
        $type = $DefaultType
    }
    try {
        $picture.Type = [TagLib.PictureType](
            [Enum]::Parse(
                [TagLib.PictureType],
                [string]$type,
                $true
            )
        )
    }
    catch {
        $numericType = [int]0
        if (-not [int]::TryParse([string]$type, [ref]$numericType) -or
            -not [Enum]::IsDefined([TagLib.PictureType], $numericType)) {
            throw "ID3 picture type '$type' is not supported."
        }
        $picture.Type = [TagLib.PictureType]$numericType
    }
    return $picture
}

function Set-RenderKitId3Pictures {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Tag,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Metadata
    )

    $hasPictures = $false
    $picturesValue = Get-RenderKitTagLibMetadataValue `
        -Metadata $Metadata `
        -Field 'AttachedPictures' `
        -Found ([ref]$hasPictures)
    $hasCoverPath = $false
    $coverPath = Get-RenderKitTagLibMetadataValue `
        -Metadata $Metadata `
        -Field 'CoverArtPath' `
        -Found ([ref]$hasCoverPath)
    $hasCoverMime = $false
    $coverMime = Get-RenderKitTagLibMetadataValue `
        -Metadata $Metadata `
        -Field 'CoverArtMimeType' `
        -Found ([ref]$hasCoverMime)
    $hasCoverDescription = $false
    $coverDescription = Get-RenderKitTagLibMetadataValue `
        -Metadata $Metadata `
        -Field 'CoverArtDescription' `
        -Found ([ref]$hasCoverDescription)
    if (-not $hasPictures -and -not $hasCoverPath -and
        -not $hasCoverMime -and -not $hasCoverDescription) {
        return
    }

    $pictures = New-Object 'System.Collections.Generic.List[TagLib.IPicture]'
    if ($hasPictures) {
        $items = if ($picturesValue -is [System.Collections.IEnumerable] -and
            -not ($picturesValue -is [string]) -and
            -not ($picturesValue -is [System.Collections.IDictionary])) {
            @($picturesValue)
        }
        elseif ($null -eq $picturesValue) {
            @()
        }
        else {
            @($picturesValue)
        }
        foreach ($item in $items) {
            $pictures.Add((ConvertTo-RenderKitId3Picture -Value $item))
        }
    }
    else {
        foreach ($existing in @($Tag.Pictures)) {
            $pictures.Add($existing)
        }
    }

    $frontCover = @(
        $pictures |
            Where-Object {
                [string]$_.Type -eq 'FrontCover'
            } |
            Select-Object -First 1
    )
    if ($hasCoverPath) {
        for ($index = $pictures.Count - 1; $index -ge 0; $index--) {
            if ([string]$pictures[$index].Type -eq 'FrontCover') {
                $pictures.RemoveAt($index)
            }
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$coverPath)) {
            $cover = ConvertTo-RenderKitId3Picture `
                -Value ([PSCustomObject]@{
                    Path = $coverPath
                    Mime = if ($hasCoverMime) { $coverMime } else { $null }
                    Description = if ($hasCoverDescription) {
                        $coverDescription
                    }
                    else {
                        $null
                    }
                    Type = 'FrontCover'
                }) `
                -DefaultType 'FrontCover'
            $pictures.Add($cover)
            $frontCover = @($cover)
        }
        else {
            $frontCover = @()
        }
    }
    if ($frontCover) {
        if ($hasCoverMime) {
            $frontCover[0].MimeType = [string]$coverMime
        }
        if ($hasCoverDescription) {
            $frontCover[0].Description = [string]$coverDescription
        }
    }
    elseif (($hasCoverMime -and
            -not [string]::IsNullOrWhiteSpace([string]$coverMime)) -or
        ($hasCoverDescription -and
            -not [string]::IsNullOrWhiteSpace(
                [string]$coverDescription))) {
        throw 'CoverArtPath is required when no front-cover picture exists.'
    }

    $Tag.Pictures = [TagLib.IPicture[]]$pictures.ToArray()
}

function Set-RenderKitId3Chapters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Tag,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Metadata
    )

    $hasValue = $false
    $value = Resolve-RenderKitTagLibAliasValue `
        -Metadata $Metadata `
        -Field @('Chapters', 'AudioChapters') `
        -Target 'Chapters' `
        -Found ([ref]$hasValue)
    if (-not $hasValue) {
        return
    }

    $Tag.RemoveFrames((Get-RenderKitId3FrameId -Id 'CHAP'))
    $Tag.RemoveFrames((Get-RenderKitId3FrameId -Id 'CTOC'))
    $items = if ($value -is [System.Collections.IEnumerable] -and
        -not ($value -is [string]) -and
        -not ($value -is [System.Collections.IDictionary])) {
        @($value)
    }
    elseif ($null -eq $value) {
        @()
    }
    else {
        @($value)
    }
    if ($items.Count -eq 0) {
        return
    }

    $ids = New-Object System.Collections.Generic.List[string]
    $seenIds = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    for ($index = 0; $index -lt $items.Count; $index++) {
        $item = $items[$index]
        $id = [string](Get-RenderKitTagLibObjectMember `
            -InputObject $item `
            -Name @('Id', 'ElementId'))
        if ([string]::IsNullOrWhiteSpace($id)) {
            $id = 'renderkit-chapter-{0:D4}' -f ($index + 1)
        }
        if (-not $seenIds.Add($id)) {
            throw "Duplicate ID3 chapter id '$id'."
        }
        $start = Get-RenderKitTagLibObjectMember `
            -InputObject $item `
            -Name @('StartMilliseconds', 'Start')
        $end = Get-RenderKitTagLibObjectMember `
            -InputObject $item `
            -Name @('EndMilliseconds', 'End')
        $title = Get-RenderKitTagLibObjectMember `
            -InputObject $item `
            -Name @('Title')
        $url = Get-RenderKitTagLibObjectMember `
            -InputObject $item `
            -Name @('Url', 'URL')
        if ($null -eq $start -or $null -eq $end) {
            throw 'Each ID3 chapter requires start and end timestamps.'
        }
        $startMilliseconds = ConvertTo-RenderKitId3TimestampMilliseconds `
            -Value $start `
            -Field 'Chapter.Start'
        $endMilliseconds = ConvertTo-RenderKitId3TimestampMilliseconds `
            -Value $end `
            -Field 'Chapter.End'
        if ($endMilliseconds -lt $startMilliseconds) {
            throw "ID3 chapter '$id' ends before it starts."
        }

        $chapter = [TagLib.Id3v2.ChapterFrame]::new($id)
        $chapter.StartMilliseconds = $startMilliseconds
        $chapter.EndMilliseconds = $endMilliseconds
        $chapter.StartByteOffset = [uint32]::MaxValue
        $chapter.EndByteOffset = [uint32]::MaxValue
        $subFrames = New-Object 'System.Collections.Generic.List[TagLib.Id3v2.Frame]'
        if (-not [string]::IsNullOrWhiteSpace([string]$title)) {
            $titleFrame = [TagLib.Id3v2.TextInformationFrame]::new(
                (Get-RenderKitId3FrameId -Id 'TIT2'),
                [TagLib.StringType]::UTF8
            )
            $titleFrame.Text = [string[]]@([string]$title)
            $subFrames.Add($titleFrame)
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$url)) {
            $urlFrame = [TagLib.Id3v2.UserTextInformationFrame]::new(
                'URL',
                [TagLib.StringType]::UTF8
            )
            $urlFrame.Text = [string[]]@([string]$url)
            $subFrames.Add($urlFrame)
        }
        $chapter.SubFrames = $subFrames
        $Tag.AddFrame($chapter)
        $ids.Add($id)
    }

    $toc = [TagLib.Id3v2.TableOfContentsFrame]::new(
        'renderkit-toc'
    )
    $toc.IsTopLevel = $true
    $toc.IsOrdered = $true
    $toc.ChapterIds = [System.Collections.Generic.List[string]]::new()
    foreach ($id in $ids) {
        $toc.ChapterIds.Add($id)
    }
    $Tag.AddFrame($toc)
}

function Set-RenderKitId3Metadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$File,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Metadata
    )

    $tag = $File.GetTag([TagLib.TagTypes]::Id3v2, $true)
    if (-not ($tag -is [TagLib.Id3v2.Tag])) {
        throw 'TagLibSharp did not expose an ID3v2 tag for the target file.'
    }
    [TagLib.Id3v2.Tag]::DefaultVersion = [byte]4
    [TagLib.Id3v2.Tag]::DefaultEncoding = [TagLib.StringType]::UTF8
    $tag.Version = [byte]4

    foreach ($group in @(
        [PSCustomObject]@{
            Property = 'Title'; Fields = @('Title', 'AudioTitle'); Type = 'String'
        },
        [PSCustomObject]@{
            Property = 'Performers'
            Fields = @('Artist', 'Creator', 'Performer')
            Type = 'StringList'
        },
        [PSCustomObject]@{
            Property = 'AlbumArtists'
            Fields = @('AlbumArtist', 'BandOrOrchestra')
            Type = 'StringList'
        },
        [PSCustomObject]@{
            Property = 'Publisher'; Fields = @('Publisher', 'Label'); Type = 'String'
        },
        [PSCustomObject]@{
            Property = 'InitialKey'
            Fields = @('InitialKey', 'MusicalKey')
            Type = 'String'
        },
        [PSCustomObject]@{
            Property = 'Album'; Fields = @('Album'); Type = 'String'
        },
        [PSCustomObject]@{
            Property = 'AlbumSort'; Fields = @('AlbumSort'); Type = 'String'
        },
        [PSCustomObject]@{
            Property = 'PerformersSort'
            Fields = @('ArtistSort')
            Type = 'StringList'
        },
        [PSCustomObject]@{
            Property = 'Composers'; Fields = @('Composer'); Type = 'StringList'
        },
        [PSCustomObject]@{
            Property = 'ComposersSort'
            Fields = @('ComposerSort')
            Type = 'StringList'
        },
        [PSCustomObject]@{
            Property = 'Conductor'; Fields = @('Conductor'); Type = 'String'
        },
        [PSCustomObject]@{
            Property = 'Grouping'; Fields = @('ContentGroup'); Type = 'String'
        },
        [PSCustomObject]@{
            Property = 'Copyright'
            Fields = @('CopyrightNotice')
            Type = 'String'
        },
        [PSCustomObject]@{
            Property = 'Genres'; Fields = @('Genre'); Type = 'StringList'
        },
        [PSCustomObject]@{
            Property = 'ISRC'; Fields = @('Isrc'); Type = 'String'
        },
        [PSCustomObject]@{
            Property = 'Subtitle'; Fields = @('Subtitle'); Type = 'String'
        },
        [PSCustomObject]@{
            Property = 'TitleSort'; Fields = @('TitleSort'); Type = 'String'
        },
        [PSCustomObject]@{
            Property = 'Comment'; Fields = @('UserComment'); Type = 'String'
        },
        [PSCustomObject]@{
            Property = 'Track'; Fields = @('AudioTrackNumber'); Type = 'UInt32'
        },
        [PSCustomObject]@{
            Property = 'TrackCount'; Fields = @('AudioTrackTotal'); Type = 'UInt32'
        },
        [PSCustomObject]@{
            Property = 'Disc'; Fields = @('AudioDiscNumber'); Type = 'UInt32'
        },
        [PSCustomObject]@{
            Property = 'DiscCount'; Fields = @('AudioDiscTotal'); Type = 'UInt32'
        }
    )) {
        $found = $false
        $value = Resolve-RenderKitTagLibAliasValue `
            -Metadata $Metadata `
            -Field $group.Fields `
            -Target $group.Property `
            -Found ([ref]$found)
        if (-not $found) {
            continue
        }
        $property = $tag.PSObject.Properties[[string]$group.Property]
        switch ([string]$group.Type) {
            'StringList' {
                $property.Value = [string[]](
                    ConvertTo-RenderKitTagLibStringArray -Value $value
                )
            }
            'UInt32' {
                $property.Value = ConvertTo-RenderKitTagLibUInt32 `
                    -Value $value `
                    -Field ([string]$group.Fields[0])
            }
            default {
                $property.Value = if ($null -eq $value) {
                    $null
                }
                else {
                    [string]$value
                }
            }
        }
    }

    foreach ($definition in @(
        [PSCustomObject]@{ Field = 'Bpm'; Id = 'TBPM'; Date = $false },
        [PSCustomObject]@{ Field = 'Category'; Id = 'TCAT'; Date = $false },
        [PSCustomObject]@{ Field = 'Description'; Id = 'TDES'; Date = $false },
        [PSCustomObject]@{ Field = 'EncodedBy'; Id = 'TENC'; Date = $false },
        [PSCustomObject]@{ Field = 'EncodingDate'; Id = 'TDEN'; Date = $true },
        [PSCustomObject]@{ Field = 'Language'; Id = 'TLAN'; Date = $false },
        [PSCustomObject]@{ Field = 'Lyricist'; Id = 'TEXT'; Date = $false },
        [PSCustomObject]@{ Field = 'Mood'; Id = 'TMOO'; Date = $false },
        [PSCustomObject]@{
            Field = 'OriginalReleaseDate'; Id = 'TDOR'; Date = $true
        },
        [PSCustomObject]@{ Field = 'RecordingDate'; Id = 'TDRC'; Date = $true },
        [PSCustomObject]@{ Field = 'ReleaseDate'; Id = 'TDRL'; Date = $true }
    )) {
        $found = $false
        $value = Get-RenderKitTagLibMetadataValue `
            -Metadata $Metadata `
            -Field $definition.Field `
            -Found ([ref]$found)
        if ($found) {
            Set-RenderKitId3TextFrame `
                -Tag $tag `
                -Id $definition.Id `
                -Value $(if ($definition.Date) {
                    ConvertTo-RenderKitTagLibDateText -Value $value
                }
                else {
                    $value
                })
        }
    }

    foreach ($definition in @(
        [PSCustomObject]@{ Field = 'Barcode'; Description = 'BARCODE' },
        [PSCustomObject]@{
            Field = 'CatalogNumber'; Description = 'CATALOGNUMBER'
        },
        [PSCustomObject]@{
            Field = 'PodcastShow'; Description = 'PODCASTSHOW'
        }
    )) {
        $found = $false
        $value = Get-RenderKitTagLibMetadataValue `
            -Metadata $Metadata `
            -Field $definition.Field `
            -Found ([ref]$found)
        if ($found) {
            Set-RenderKitId3UserTextFrame `
                -Tag $tag `
                -Description $definition.Description `
                -Value $value
        }
    }

    foreach ($definition in @(
        [PSCustomObject]@{ Field = 'ArtistUrl'; Id = 'WOAR' },
        [PSCustomObject]@{ Field = 'AudioFileUrl'; Id = 'WOAF' },
        [PSCustomObject]@{ Field = 'CommercialUrl'; Id = 'WCOM' },
        [PSCustomObject]@{ Field = 'CopyrightUrl'; Id = 'WCOP' },
        [PSCustomObject]@{ Field = 'PublisherUrl'; Id = 'WPUB' }
    )) {
        $found = $false
        $value = Get-RenderKitTagLibMetadataValue `
            -Metadata $Metadata `
            -Field $definition.Field `
            -Found ([ref]$found)
        if ($found) {
            Set-RenderKitId3UrlFrame `
                -Tag $tag `
                -Id $definition.Id `
                -Value $value
        }
    }

    $hasArranger = $false
    $arranger = Get-RenderKitTagLibMetadataValue `
        -Metadata $Metadata `
        -Field 'Arranger' `
        -Found ([ref]$hasArranger)
    if ($hasArranger) {
        Set-RenderKitId3ArrangerFrame -Tag $tag -Value $arranger
    }

    Set-RenderKitId3Lyrics -Tag $tag -Metadata $Metadata
    Set-RenderKitId3SynchronizedLyrics -Tag $tag -Metadata $Metadata
    Set-RenderKitId3Pictures -Tag $tag -Metadata $Metadata
    Set-RenderKitId3Chapters -Tag $tag -Metadata $Metadata
}

function Get-RenderKitId3TextFrameValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Tag,

        [Parameter(Mandatory)]
        [string]$Id
    )

    $frame = [TagLib.Id3v2.TextInformationFrame]::Get(
        $Tag,
        (Get-RenderKitId3FrameId -Id $Id),
        $false
    )
    if (-not $frame) {
        return @()
    }
    return @($frame.Text | ForEach-Object { [string]$_ })
}

function Get-RenderKitId3UserTextValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Tag,

        [Parameter(Mandatory)]
        [string]$Description
    )

    $frame = [TagLib.Id3v2.UserTextInformationFrame]::Get(
        $Tag,
        $Description,
        $false
    )
    if (-not $frame) {
        return @()
    }
    return @($frame.Text | ForEach-Object { [string]$_ })
}

function Get-RenderKitId3UrlValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Tag,

        [Parameter(Mandatory)]
        [string]$Id
    )

    $frame = [TagLib.Id3v2.UrlLinkFrame]::Get(
        $Tag,
        (Get-RenderKitId3FrameId -Id $Id),
        $false
    )
    if (-not $frame) {
        return @()
    }
    return @($frame.Text | ForEach-Object { [string]$_ })
}

function Read-RenderKitId3TagFields {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Tag
    )

    $fields = [ordered]@{}
    foreach ($definition in @(
        [PSCustomObject]@{ Property = 'Title'; Fields = @('Title', 'AudioTitle') },
        [PSCustomObject]@{
            Property = 'Performers'; Fields = @('Artist', 'Creator', 'Performer')
        },
        [PSCustomObject]@{
            Property = 'AlbumArtists'
            Fields = @('AlbumArtist', 'BandOrOrchestra')
        },
        [PSCustomObject]@{ Property = 'Album'; Fields = @('Album') },
        [PSCustomObject]@{ Property = 'AlbumSort'; Fields = @('AlbumSort') },
        [PSCustomObject]@{
            Property = 'PerformersSort'; Fields = @('ArtistSort')
        },
        [PSCustomObject]@{ Property = 'Composers'; Fields = @('Composer') },
        [PSCustomObject]@{
            Property = 'ComposersSort'; Fields = @('ComposerSort')
        },
        [PSCustomObject]@{ Property = 'Conductor'; Fields = @('Conductor') },
        [PSCustomObject]@{ Property = 'Grouping'; Fields = @('ContentGroup') },
        [PSCustomObject]@{
            Property = 'Copyright'; Fields = @('CopyrightNotice')
        },
        [PSCustomObject]@{ Property = 'Genres'; Fields = @('Genre') },
        [PSCustomObject]@{
            Property = 'InitialKey'; Fields = @('InitialKey', 'MusicalKey')
        },
        [PSCustomObject]@{ Property = 'ISRC'; Fields = @('Isrc') },
        [PSCustomObject]@{
            Property = 'Publisher'; Fields = @('Publisher', 'Label')
        },
        [PSCustomObject]@{ Property = 'Subtitle'; Fields = @('Subtitle') },
        [PSCustomObject]@{ Property = 'TitleSort'; Fields = @('TitleSort') },
        [PSCustomObject]@{ Property = 'Comment'; Fields = @('UserComment') },
        [PSCustomObject]@{
            Property = 'Track'; Fields = @('AudioTrackNumber')
        },
        [PSCustomObject]@{
            Property = 'TrackCount'; Fields = @('AudioTrackTotal')
        },
        [PSCustomObject]@{ Property = 'Disc'; Fields = @('AudioDiscNumber') },
        [PSCustomObject]@{
            Property = 'DiscCount'; Fields = @('AudioDiscTotal')
        }
    )) {
        $value = $Tag.PSObject.Properties[
            [string]$definition.Property
        ].Value
        if ($value -is [uint32] -and [uint32]$value -eq 0) {
            continue
        }
        foreach ($field in $definition.Fields) {
            Set-RenderKitMetadataFieldValue `
                -Fields $fields `
                -Name $field `
                -Value $value
        }
    }

    foreach ($definition in @(
        [PSCustomObject]@{ Field = 'Bpm'; Id = 'TBPM' },
        [PSCustomObject]@{ Field = 'Category'; Id = 'TCAT' },
        [PSCustomObject]@{ Field = 'Description'; Id = 'TDES' },
        [PSCustomObject]@{ Field = 'EncodedBy'; Id = 'TENC' },
        [PSCustomObject]@{ Field = 'EncodingDate'; Id = 'TDEN' },
        [PSCustomObject]@{ Field = 'Language'; Id = 'TLAN' },
        [PSCustomObject]@{ Field = 'Lyricist'; Id = 'TEXT' },
        [PSCustomObject]@{ Field = 'Mood'; Id = 'TMOO' },
        [PSCustomObject]@{ Field = 'OriginalReleaseDate'; Id = 'TDOR' },
        [PSCustomObject]@{ Field = 'RecordingDate'; Id = 'TDRC' },
        [PSCustomObject]@{ Field = 'ReleaseDate'; Id = 'TDRL' }
    )) {
        $values = @(Get-RenderKitId3TextFrameValues `
            -Tag $Tag `
            -Id $definition.Id)
        if ($values.Count -eq 0) {
            continue
        }
        $value = if ($definition.Field -eq 'Mood') {
            @($values)
        }
        elseif ($definition.Field -eq 'Bpm') {
            ConvertTo-RenderKitMetadataNumber -Value $values[0]
        }
        else {
            [string]$values[0]
        }
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name $definition.Field `
            -Value $value
    }

    foreach ($definition in @(
        [PSCustomObject]@{ Field = 'Barcode'; Description = 'BARCODE' },
        [PSCustomObject]@{
            Field = 'CatalogNumber'; Description = 'CATALOGNUMBER'
        },
        [PSCustomObject]@{
            Field = 'PodcastShow'; Description = 'PODCASTSHOW'
        }
    )) {
        $values = @(Get-RenderKitId3UserTextValues `
            -Tag $Tag `
            -Description $definition.Description)
        if ($values.Count -gt 0) {
            Set-RenderKitMetadataFieldValue `
                -Fields $fields `
                -Name $definition.Field `
                -Value $values[0]
        }
    }

    foreach ($definition in @(
        [PSCustomObject]@{ Field = 'ArtistUrl'; Id = 'WOAR' },
        [PSCustomObject]@{ Field = 'AudioFileUrl'; Id = 'WOAF' },
        [PSCustomObject]@{ Field = 'CommercialUrl'; Id = 'WCOM' },
        [PSCustomObject]@{ Field = 'CopyrightUrl'; Id = 'WCOP' },
        [PSCustomObject]@{ Field = 'PublisherUrl'; Id = 'WPUB' }
    )) {
        $values = @(Get-RenderKitId3UrlValues `
            -Tag $Tag `
            -Id $definition.Id)
        if ($values.Count -gt 0) {
            Set-RenderKitMetadataFieldValue `
                -Fields $fields `
                -Name $definition.Field `
                -Value $values[0]
        }
    }

    $arrangers = New-Object System.Collections.Generic.List[string]
    $people = @(Get-RenderKitId3TextFrameValues -Tag $Tag -Id 'TIPL')
    for ($index = 0; $index + 1 -lt $people.Count; $index += 2) {
        if ([string]$people[$index] -ieq 'Arranger') {
            $arrangers.Add([string]$people[$index + 1])
        }
    }
    if ($arrangers.Count -gt 0) {
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'Arranger' `
            -Value ($arrangers.ToArray() -join ', ')
    }

    $lyrics = @(
        $Tag.GetFrames[
            TagLib.Id3v2.UnsynchronisedLyricsFrame
        ]()
    )
    if ($lyrics.Count -gt 0) {
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'Lyrics' `
            -Value ([string]$lyrics[0].Text)
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'LyricsLanguage' `
            -Value ([string]$lyrics[0].Language)
    }

    $synchronized = @(
        $Tag.GetFrames[
            TagLib.Id3v2.SynchronisedLyricsFrame
        ]()
    )
    if ($synchronized.Count -gt 0) {
        $lines = @(
            $synchronized[0].Text |
                ForEach-Object {
                    [PSCustomObject][ordered]@{
                        TimestampMilliseconds = [uint32]$_.Time
                        Text = [string]$_.Text
                    }
                }
        )
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'SynchronizedLyrics' `
            -Value $lines
        if (-not $fields.Contains('LyricsLanguage')) {
            Set-RenderKitMetadataFieldValue `
                -Fields $fields `
                -Name 'LyricsLanguage' `
                -Value ([string]$synchronized[0].Language)
        }
    }

    $pictures = @(
        $Tag.Pictures |
            ForEach-Object {
                [PSCustomObject][ordered]@{
                    Embedded = $true
                    Mime = [string]$_.MimeType
                    Type = [string]$_.Type
                    Description = [string]$_.Description
                    SizeBytes = [int64]$_.Data.Count
                    Sha256 = [Convert]::ToHexString(
                        [Security.Cryptography.SHA256]::HashData(
                            [byte[]]$_.Data.Data
                        )
                    )
                }
            }
    )
    if ($pictures.Count -gt 0) {
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'AttachedPictures' `
            -Value $pictures
        $front = @(
            $pictures |
                Where-Object Type -eq 'FrontCover' |
                Select-Object -First 1
        )
        if ($front) {
            Set-RenderKitMetadataFieldValue `
                -Fields $fields `
                -Name 'CoverArtMimeType' `
                -Value $front.Mime
            Set-RenderKitMetadataFieldValue `
                -Fields $fields `
                -Name 'CoverArtDescription' `
                -Value $front.Description
        }
    }

    $chapters = @(
        $Tag.GetFrames[
            TagLib.Id3v2.ChapterFrame
        ]() |
            Sort-Object StartMilliseconds |
            ForEach-Object {
                $titleFrame = @(
                    $_.SubFrames |
                        Where-Object {
                            $_ -is [TagLib.Id3v2.TextInformationFrame] -and
                                $_.FrameId.ToString() -eq 'TIT2'
                        } |
                        Select-Object -First 1
                )
                $urlFrame = @(
                    $_.SubFrames |
                        Where-Object {
                            $_ -is [TagLib.Id3v2.UserTextInformationFrame] -and
                                [string]$_.Description -ieq 'URL'
                        } |
                        Select-Object -First 1
                )
                [PSCustomObject][ordered]@{
                    Id = [string]$_.Id
                    StartMilliseconds = [uint32]$_.StartMilliseconds
                    EndMilliseconds = [uint32]$_.EndMilliseconds
                    Title = if ($titleFrame) {
                        [string]@($titleFrame.Text)[0]
                    }
                    else {
                        $null
                    }
                    Url = if ($urlFrame) {
                        [string]@($urlFrame.Text)[0]
                    }
                    else {
                        $null
                    }
                }
            }
    )
    if ($chapters.Count -gt 0) {
        foreach ($field in @('Chapters', 'AudioChapters')) {
            Set-RenderKitMetadataFieldValue `
                -Fields $fields `
                -Name $field `
                -Value $chapters
        }
    }
    return $fields
}

function Read-RenderKitTagLibSharpEmbeddedMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $resolvedPath = (
        Resolve-Path -LiteralPath $Path -ErrorAction Stop
    ).ProviderPath
    if (-not (Test-RenderKitTagLibSharpId3Path -Path $resolvedPath)) {
        throw 'The TagLibSharp ID3 reader does not support this file extension.'
    }
    $runtime = Import-RenderKitTagLibSharpRuntime
    $file = [TagLib.File]::Create(
        $resolvedPath,
        [TagLib.ReadStyle]::Average
    )
    try {
        $tag = $file.GetTag([TagLib.TagTypes]::Id3v2, $false)
        $fields = if ($tag -is [TagLib.Id3v2.Tag]) {
            Read-RenderKitId3TagFields -Tag $tag
        }
        else {
            [ordered]@{}
        }
        return [PSCustomObject]@{
            Fields = $fields
            Profile = 'ID3'
            TagPresent = $tag -is [TagLib.Id3v2.Tag]
            TagVersion = if ($tag -is [TagLib.Id3v2.Tag]) {
                [int]$tag.Version
            }
            else {
                $null
            }
            Runtime = [PSCustomObject]@{
                Version = [string]$runtime.Version
                Source = [string]$runtime.Source
                Path = [string]$runtime.Path
                Hash = [string]$runtime.Hash
            }
        }
    }
    finally {
        $file.Dispose()
    }
}

function Test-RenderKitTagLibSharpId3Write {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Metadata
    )

    $read = Read-RenderKitTagLibSharpEmbeddedMetadata -Path $Path
    $definitions = @(
        Get-RenderKitTagLibSharpMetadataWriteDefinitions -Profile ID3
    )
    $definitionByField = @{}
    foreach ($definition in $definitions) {
        $definitionByField[[string]$definition.Field] = $definition
    }
    foreach ($key in @($Metadata.Keys)) {
        $field = [string]$key
        if (-not $definitionByField.ContainsKey($field)) {
            continue
        }
        $definition = $definitionByField[$field]
        if ($field -in @(
                'CoverArtPath',
                'CoverArtMimeType',
                'CoverArtDescription'
            )) {
            continue
        }
        if (-not $read.Fields.Contains($field)) {
            if (Test-RenderKitMetadataValueIsEmpty -Value $Metadata[$key]) {
                continue
            }
            throw "ID3 verification did not read field '$field' back."
        }
        if ($field -eq 'AttachedPictures') {
            $expectedCount = @($Metadata[$key]).Count
            if (@($read.Fields[$field]).Count -ne $expectedCount) {
                throw "ID3 verification failed for picture field '$field'."
            }
            continue
        }
        if ([string]$definition.ValueType -eq 'ChapterList') {
            $expectedChapters = @($Metadata[$key])
            $actualChapters = @($read.Fields[$field])
            if ($expectedChapters.Count -ne $actualChapters.Count) {
                throw "ID3 verification failed for chapter field '$field'."
            }
            for ($index = 0; $index -lt $expectedChapters.Count; $index++) {
                $expectedChapter = $expectedChapters[$index]
                $actualChapter = $actualChapters[$index]
                foreach ($member in @(
                    [PSCustomObject]@{
                        Expected = @('StartMilliseconds', 'Start')
                        Actual = 'StartMilliseconds'
                        Required = $true
                    },
                    [PSCustomObject]@{
                        Expected = @('EndMilliseconds', 'End')
                        Actual = 'EndMilliseconds'
                        Required = $true
                    },
                    [PSCustomObject]@{
                        Expected = @('Title')
                        Actual = 'Title'
                        Required = $false
                    },
                    [PSCustomObject]@{
                        Expected = @('Url', 'URL')
                        Actual = 'Url'
                        Required = $false
                    }
                )) {
                    $expectedValue = Get-RenderKitTagLibObjectMember `
                        -InputObject $expectedChapter `
                        -Name $member.Expected
                    if ($null -eq $expectedValue -and
                        -not [bool]$member.Required) {
                        continue
                    }
                    $actualValue = Get-RenderKitTagLibObjectMember `
                        -InputObject $actualChapter `
                        -Name @([string]$member.Actual)
                    if ($member.Actual -in @(
                            'StartMilliseconds',
                            'EndMilliseconds'
                        )) {
                        $expectedValue =
                            ConvertTo-RenderKitId3TimestampMilliseconds `
                                -Value $expectedValue `
                                -Field $field
                    }
                    if (([string]$expectedValue) -ne
                        ([string]$actualValue)) {
                        throw "ID3 verification failed for chapter field '$field'."
                    }
                }
            }
            continue
        }
        if ([string]$definition.ValueType -eq 'SynchronizedLyrics') {
            $expectedLines = @($Metadata[$key])
            $actualLines = @($read.Fields[$field])
            if ($expectedLines.Count -ne $actualLines.Count) {
                throw "ID3 verification failed for synchronized lyrics."
            }
            for ($index = 0; $index -lt $expectedLines.Count; $index++) {
                $expectedTime = Get-RenderKitTagLibObjectMember `
                    -InputObject $expectedLines[$index] `
                    -Name @(
                        'TimestampMilliseconds',
                        'TimeMilliseconds',
                        'Timestamp',
                        'Time'
                    )
                $expectedText = Get-RenderKitTagLibObjectMember `
                    -InputObject $expectedLines[$index] `
                    -Name @('Text', 'Lyric')
                $actualTime = Get-RenderKitTagLibObjectMember `
                    -InputObject $actualLines[$index] `
                    -Name @('TimestampMilliseconds')
                $actualText = Get-RenderKitTagLibObjectMember `
                    -InputObject $actualLines[$index] `
                    -Name @('Text')
                $expectedMilliseconds =
                    ConvertTo-RenderKitId3TimestampMilliseconds `
                        -Value $expectedTime `
                        -Field $field
                if ([uint32]$expectedMilliseconds -ne
                    [uint32]$actualTime -or
                    [string]$expectedText -ne [string]$actualText) {
                    throw "ID3 verification failed for synchronized lyrics."
                }
            }
            continue
        }
        if ([string]$definition.ValueType -in @(
                'StringList',
                'TextFrameList'
            )) {
            $expected = ConvertTo-RenderKitTagLibComparableJson `
                -Value @(
                    ConvertTo-RenderKitTagLibStringArray `
                        -Value $Metadata[$key]
                )
            $actual = ConvertTo-RenderKitTagLibComparableJson `
                -Value @(
                    ConvertTo-RenderKitTagLibStringArray `
                        -Value $read.Fields[$field]
                )
            if ($expected -ne $actual) {
                throw "ID3 verification failed for field '$field'."
            }
            continue
        }
        $expected = ConvertTo-RenderKitTagLibComparableJson `
            -Value $Metadata[$key]
        $actual = ConvertTo-RenderKitTagLibComparableJson `
            -Value $read.Fields[$field]
        if ($expected -ne $actual) {
            throw "ID3 verification failed for field '$field'."
        }
    }
    return $read
}

function Invoke-RenderKitTagLibSharpMetadataWrite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Metadata
    )

    $resolvedPath = (
        Resolve-Path -LiteralPath $Path -ErrorAction Stop
    ).ProviderPath
    if (-not (Test-RenderKitTagLibSharpId3Path -Path $resolvedPath)) {
        throw 'TagLibSharp ID3 writes support MP3, MP2, AAC, and TTA files.'
    }
    $writtenFields = @(
        $Metadata.Keys |
            Where-Object {
                @(
                    Get-RenderKitTagLibSharpMetadataWriteDefinitions `
                        -Profile ID3 `
                        -Field ([string]$_)
                ).Count -gt 0
            } |
            ForEach-Object { [string]$_ } |
            Sort-Object -Unique
    )
    if ($writtenFields.Count -eq 0) {
        throw 'The metadata set contains no writable ID3 fields.'
    }

    $runtime = Import-RenderKitTagLibSharpRuntime
    $lockHandle = Enter-RenderKitFileLock `
        -Path "$resolvedPath.renderkit-metadata" `
        -TimeoutMilliseconds 30000
    $directory = Split-Path -Path $resolvedPath -Parent
    $extension = [System.IO.Path]::GetExtension($resolvedPath)
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedPath)
    $temporaryPath = Join-Path `
        -Path $directory `
        -ChildPath (
            '.{0}.renderkit-{1}.tmp{2}' -f
                $baseName,
                [guid]::NewGuid().ToString('N'),
                $extension
        )
    $backupPath = Join-Path `
        -Path $directory `
        -ChildPath (
            '.{0}.renderkit-{1}.bak' -f
                [System.IO.Path]::GetFileName($resolvedPath),
                [guid]::NewGuid().ToString('N')
        )
    $sourceTimestamp = [System.IO.File]::GetLastWriteTimeUtc($resolvedPath)
    $sourceAttributes = [System.IO.File]::GetAttributes($resolvedPath)
    $replacementComplete = $false
    $preserveBackup = $false
    try {
        [System.IO.File]::Copy($resolvedPath, $temporaryPath, $false)
        $tagFile = [TagLib.File]::Create(
            $temporaryPath,
            [TagLib.ReadStyle]::Average
        )
        try {
            if (-not [bool]$tagFile.Writeable) {
                throw "TagLibSharp reports '$resolvedPath' as read-only."
            }
            Set-RenderKitId3Metadata `
                -File $tagFile `
                -Metadata $Metadata
            $tagFile.Save()
        }
        finally {
            $tagFile.Dispose()
        }
        $candidateRead = Test-RenderKitTagLibSharpId3Write `
            -Path $temporaryPath `
            -Metadata $Metadata

        try {
            [System.IO.File]::Replace(
                $temporaryPath,
                $resolvedPath,
                $backupPath,
                $true
            )
            $replacementComplete = $true
        }
        catch {
            try {
                [System.IO.File]::Move($resolvedPath, $backupPath)
                try {
                    [System.IO.File]::Move($temporaryPath, $resolvedPath)
                    $replacementComplete = $true
                }
                catch {
                    [System.IO.File]::Move($backupPath, $resolvedPath)
                    throw
                }
            }
            catch {
                throw "Atomic ID3 replacement failed: $($_.Exception.Message)"
            }
        }

        [System.IO.File]::SetLastWriteTimeUtc(
            $resolvedPath,
            $sourceTimestamp
        )
        [System.IO.File]::SetAttributes(
            $resolvedPath,
            $sourceAttributes
        )
        $finalRead = Test-RenderKitTagLibSharpId3Write `
            -Path $resolvedPath `
            -Metadata $Metadata
        if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction Stop
        }

        return [PSCustomObject]@{
            Path = $resolvedPath
            Profile = 'ID3'
            Adapter = 'TagLibSharp'
            Backend = 'BundledDotNet'
            BackendSource = [string]$runtime.Source
            BackendPath = [string]$runtime.Path
            BackendVersion = [string]$runtime.Version
            Fields = @($writtenFields)
            Verified = $true
            TagVersion = [int]$finalRead.TagVersion
            CandidateTagVersion = [int]$candidateRead.TagVersion
        }
    }
    catch {
        $failure = $_
        if ($replacementComplete -and
            (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            try {
                if (Test-Path -LiteralPath $resolvedPath -PathType Leaf) {
                    try {
                        [System.IO.File]::Replace(
                            $backupPath,
                            $resolvedPath,
                            $null,
                            $true
                        )
                    }
                    catch {
                        [System.IO.File]::Copy(
                            $backupPath,
                            $resolvedPath,
                            $true
                        )
                    }
                }
                else {
                    [System.IO.File]::Move($backupPath, $resolvedPath)
                }
                [System.IO.File]::SetLastWriteTimeUtc(
                    $resolvedPath,
                    $sourceTimestamp
                )
                [System.IO.File]::SetAttributes(
                    $resolvedPath,
                    $sourceAttributes
                )
            }
            catch {
                $preserveBackup = $true
                throw "ID3 write failed and backup restoration also failed. Original error: $($failure.Exception.Message). Restore error: $($_.Exception.Message). Backup: '$backupPath'."
            }
        }
        throw $failure
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item `
                -LiteralPath $temporaryPath `
                -Force `
                -ErrorAction SilentlyContinue
        }
        if (-not $preserveBackup -and
            (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            Remove-Item `
                -LiteralPath $backupPath `
                -Force `
                -ErrorAction SilentlyContinue
        }
        Exit-RenderKitFileLock -LockHandle $lockHandle
    }
}
