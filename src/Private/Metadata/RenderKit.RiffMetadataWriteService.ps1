function Test-RenderKitRiffMetadataWritePath {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return @('.wav', '.wave', '.bwf', '.rf64') -contains
        [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
}

function Get-RenderKitRiffMetadataWriteDefinitions {
    [CmdletBinding()]
    param(
        [string]$Field
    )

    $definitions = New-Object System.Collections.Generic.List[object]
    foreach ($profile in @('BWF', 'iXML')) {
        $map = Read-RenderKitAudioContainerMetadataProfileMap -Profile $profile
        foreach ($definition in @($map.writeFields)) {
            if (-not [string]::IsNullOrWhiteSpace($Field) -and
                [string]$definition.field -ine $Field) {
                continue
            }
            $definitions.Add([PSCustomObject]@{
                Profile = $profile
                Field = [string]$definition.field
                Target = [string]$definition.target
                ValueType = [string]$definition.valueType
            })
        }
    }

    return @($definitions.ToArray())
}

function Get-RenderKitRiffEmbeddedMetadataWriteCapability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Field,

        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-RenderKitRiffMetadataWritePath -Path $Path)) {
        return $null
    }

    $definitions = @(Get-RenderKitRiffMetadataWriteDefinitions -Field $Field)
    if ($definitions.Count -eq 0) {
        return $null
    }

    return [PSCustomObject]@{
        field = $Field
        adapter = 'RenderKitRiff'
        tags = @($definitions | ForEach-Object {
            '{0}:{1}' -f $_.Profile, $_.Target
        })
        mediaKinds = @('Audio')
        fieldType = $null
        standards = @($definitions.Profile | Select-Object -Unique)
        writeMode = 'RiffChunk'
        structureMembers = $null
        controlledVocabulary = $null
    }
}

function Get-RenderKitLittleEndianUInt16 {
    [CmdletBinding()]
    [OutputType([uint16])]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes,

        [Parameter(Mandatory)]
        [int]$Offset
    )

    # RIFF is always little-endian. Decode explicitly instead of relying on
    # BitConverter so the result is identical on a big-endian runtime.
    if ($Offset -lt 0 -or $Offset + 2 -gt $Bytes.Length) {
        throw "Cannot read UInt16 at byte offset $Offset."
    }
    return [uint16](
        [uint16]$Bytes[$Offset] -bor
        ([uint16]$Bytes[$Offset + 1] -shl 8)
    )
}

function Get-RenderKitLittleEndianInt16 {
    [CmdletBinding()]
    [OutputType([int16])]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes,

        [Parameter(Mandatory)]
        [int]$Offset
    )

    $unsigned = Get-RenderKitLittleEndianUInt16 -Bytes $Bytes -Offset $Offset
    if ($unsigned -ge 32768) {
        return [int16]([int]$unsigned - 65536)
    }
    return [int16]$unsigned
}

function Get-RenderKitLittleEndianUInt32 {
    [CmdletBinding()]
    [OutputType([uint32])]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes,

        [Parameter(Mandatory)]
        [int]$Offset
    )

    if ($Offset -lt 0 -or $Offset + 4 -gt $Bytes.Length) {
        throw "Cannot read UInt32 at byte offset $Offset."
    }
    return [uint32](
        [uint32]$Bytes[$Offset] -bor
        ([uint32]$Bytes[$Offset + 1] -shl 8) -bor
        ([uint32]$Bytes[$Offset + 2] -shl 16) -bor
        ([uint32]$Bytes[$Offset + 3] -shl 24)
    )
}

function Get-RenderKitLittleEndianUInt64 {
    [CmdletBinding()]
    [OutputType([uint64])]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes,

        [Parameter(Mandatory)]
        [int]$Offset
    )

    $low = [uint64](Get-RenderKitLittleEndianUInt32 `
        -Bytes $Bytes `
        -Offset $Offset)
    $high = [uint64](Get-RenderKitLittleEndianUInt32 `
        -Bytes $Bytes `
        -Offset ($Offset + 4))
    return [uint64](($high * [uint64]4294967296) + $low)
}

function Set-RenderKitLittleEndianUInt16 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes,

        [Parameter(Mandatory)]
        [int]$Offset,

        [Parameter(Mandatory)]
        [uint16]$Value
    )

    if ($Offset -lt 0 -or $Offset + 2 -gt $Bytes.Length) {
        throw "Cannot write UInt16 at byte offset $Offset."
    }
    $Bytes[$Offset] = [byte]($Value -band 0xff)
    $Bytes[$Offset + 1] = [byte](($Value -shr 8) -band 0xff)
}

function Set-RenderKitLittleEndianInt16 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes,

        [Parameter(Mandatory)]
        [int]$Offset,

        [Parameter(Mandatory)]
        [int16]$Value
    )

    $encoded = [System.BitConverter]::GetBytes($Value)
    if (-not [System.BitConverter]::IsLittleEndian) {
        [array]::Reverse($encoded)
    }
    [System.Buffer]::BlockCopy($encoded, 0, $Bytes, $Offset, 2)
}

function Set-RenderKitLittleEndianUInt32 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes,

        [Parameter(Mandatory)]
        [int]$Offset,

        [Parameter(Mandatory)]
        [uint32]$Value
    )

    if ($Offset -lt 0 -or $Offset + 4 -gt $Bytes.Length) {
        throw "Cannot write UInt32 at byte offset $Offset."
    }
    for ($index = 0; $index -lt 4; $index++) {
        $Bytes[$Offset + $index] =
            [byte](($Value -shr ($index * 8)) -band 0xff)
    }
}

function Set-RenderKitLittleEndianUInt64 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes,

        [Parameter(Mandatory)]
        [int]$Offset,

        [Parameter(Mandatory)]
        [uint64]$Value
    )

    Set-RenderKitLittleEndianUInt32 `
        -Bytes $Bytes `
        -Offset $Offset `
        -Value ([uint32]($Value -band [uint64]4294967295))
    Set-RenderKitLittleEndianUInt32 `
        -Bytes $Bytes `
        -Offset ($Offset + 4) `
        -Value ([uint32]($Value -shr 32))
}

function ConvertTo-RenderKitRiffAsciiBytes {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [AllowEmptyString()]
        [string]$Value,

        [string]$Field = 'value'
    )

    foreach ($character in $Value.ToCharArray()) {
        if ([int]$character -gt 127) {
            throw "BWF field '$Field' only accepts ASCII characters."
        }
    }
    return ,([System.Text.Encoding]::ASCII.GetBytes($Value))
}

function Get-RenderKitBwfFixedString {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes,

        [Parameter(Mandatory)]
        [int]$Offset,

        [Parameter(Mandatory)]
        [int]$Length
    )

    if ($Offset + $Length -gt $Bytes.Length) {
        return $null
    }
    return [System.Text.Encoding]::ASCII.GetString(
        $Bytes,
        $Offset,
        $Length
    ).TrimEnd([char]0, [char]32)
}

function Set-RenderKitBwfFixedString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes,

        [Parameter(Mandatory)]
        [int]$Offset,

        [Parameter(Mandatory)]
        [int]$Length,

        [AllowEmptyString()]
        [string]$Value,

        [Parameter(Mandatory)]
        [string]$Field
    )

    $encoded = ConvertTo-RenderKitRiffAsciiBytes `
        -Value $Value `
        -Field $Field
    if ($encoded.Length -gt $Length) {
        throw "BWF field '$Field' exceeds its $Length-byte limit."
    }
    [array]::Clear($Bytes, $Offset, $Length)
    if ($encoded.Length -gt 0) {
        [System.Buffer]::BlockCopy(
            $encoded,
            0,
            $Bytes,
            $Offset,
            $encoded.Length
        )
    }
}

function ConvertTo-RenderKitBwfDate {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object]$Value
    )

    if ($Value -is [datetime]) {
        return $Value.ToString('yyyy-MM-dd')
    }
    $match = [regex]::Match(
        ([string]$Value).Trim(),
        '^(?<year>\d{4})[:-](?<month>\d{2})[:-](?<day>\d{2})'
    )
    if (-not $match.Success) {
        throw "BWF origination date must use YYYY-MM-DD."
    }
    $candidate = '{0}-{1}-{2}' -f `
        $match.Groups['year'].Value,
        $match.Groups['month'].Value,
        $match.Groups['day'].Value
    $parsed = [datetime]::MinValue
    if (-not [datetime]::TryParseExact(
            $candidate,
            'yyyy-MM-dd',
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None,
            [ref]$parsed)) {
        throw "BWF origination date '$candidate' is not a calendar date."
    }
    return $candidate
}

function ConvertTo-RenderKitBwfTime {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object]$Value
    )

    if ($Value -is [datetime]) {
        return $Value.ToString('HH:mm:ss')
    }
    $candidate = ([string]$Value).Trim()
    $parsed = [datetime]::MinValue
    if (-not [datetime]::TryParseExact(
            $candidate,
            'HH:mm:ss',
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None,
            [ref]$parsed)) {
        throw "BWF origination time must use HH:MM:SS."
    }
    return $candidate
}

function ConvertTo-RenderKitUInt64Value {
    [CmdletBinding()]
    [OutputType([uint64])]
    param(
        [Parameter(Mandatory)]
        [object]$Value,

        [string]$Field = 'value'
    )

    if ($Value -is [sbyte] -or $Value -is [int16] -or
        $Value -is [int32] -or $Value -is [int64]) {
        if ([int64]$Value -lt 0) {
            throw "Field '$Field' must not be negative."
        }
        return [uint64]$Value
    }
    if ($Value -is [byte] -or $Value -is [uint16] -or
        $Value -is [uint32] -or $Value -is [uint64]) {
        return [uint64]$Value
    }

    $parsed = [uint64]0
    if (-not [uint64]::TryParse(
            ([string]$Value).Trim(),
            [System.Globalization.NumberStyles]::Integer,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$parsed)) {
        throw "Field '$Field' must be an unsigned 64-bit integer."
    }
    return $parsed
}

function ConvertTo-RenderKitBwfUmidBytes {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory)]
        [object]$Value
    )

    if ($Value -is [byte[]]) {
        if ($Value.Length -notin @(32, 64)) {
            throw 'BWF UMID byte arrays must contain 32 or 64 bytes.'
        }
        $result = New-Object byte[] 64
        [System.Buffer]::BlockCopy($Value, 0, $result, 0, $Value.Length)
        return ,$result
    }

    $text = ([string]$Value).Trim()
    $text = [regex]::Replace(
        $text,
        '^urn:(?:smpte:)?umid:',
        '',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    $hex = [regex]::Replace($text, '[^0-9A-Fa-f]', '')
    if ($hex.Length -notin @(64, 128)) {
        throw 'BWF UMID must contain 32 or 64 bytes represented as hexadecimal.'
    }

    $result = New-Object byte[] 64
    for ($index = 0; $index -lt ($hex.Length / 2); $index++) {
        $result[$index] = [Convert]::ToByte(
            $hex.Substring($index * 2, 2),
            16
        )
    }
    return ,$result
}

function ConvertTo-RenderKitBwfLoudnessInt16 {
    [CmdletBinding()]
    [OutputType([int16])]
    param(
        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Field
    )

    $number = ConvertTo-RenderKitMetadataNumber -Value $Value
    if ($null -eq $number) {
        throw "BWF loudness field '$Field' must be numeric."
    }
    $scaled = [Math]::Round([double]$number * 100, 0)
    if ($scaled -lt [int16]::MinValue -or
        $scaled -gt 32766) {
        throw "BWF loudness field '$Field' is outside the signed 16-bit BEXT range."
    }
    return [int16]$scaled
}

function ConvertTo-RenderKitRiffComparableJson {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$Value
    )

    return ([PSCustomObject]@{
        Value = $Value
    } | ConvertTo-Json -Depth 50 -Compress)
}

function Get-RenderKitBwfMetadataAssignments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Metadata
    )

    $assignments = [ordered]@{}
    foreach ($field in @($Metadata.Keys | Sort-Object)) {
        $definitions = @(
            Get-RenderKitRiffMetadataWriteDefinitions -Field ([string]$field) |
                Where-Object Profile -eq 'BWF'
        )
        foreach ($definition in $definitions) {
            $target = [string]$definition.Target
            $value = $Metadata[$field]
            if ($assignments.Contains($target)) {
                $existingJson = ConvertTo-RenderKitRiffComparableJson `
                    -Value $assignments[$target].Value
                $nextJson = ConvertTo-RenderKitRiffComparableJson `
                    -Value $value
                if ($existingJson -ne $nextJson) {
                    throw "BWF fields '$($assignments[$target].Field)' and '$field' target '$target' with conflicting values."
                }
                continue
            }
            $assignments[$target] = [PSCustomObject]@{
                Field = [string]$field
                Target = $target
                ValueType = [string]$definition.ValueType
                Value = $value
            }
        }
    }
    return $assignments
}

function New-RenderKitBwfChunkPayload {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [AllowNull()]
        [byte[]]$ExistingPayload,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Metadata
    )

    $assignments = Get-RenderKitBwfMetadataAssignments -Metadata $Metadata
    if ($assignments.Count -eq 0) {
        return $null
    }

    $fixed = New-Object byte[] 602
    Set-RenderKitLittleEndianInt16 -Bytes $fixed -Offset 412 -Value 32767
    Set-RenderKitLittleEndianInt16 -Bytes $fixed -Offset 414 -Value 32767
    Set-RenderKitLittleEndianInt16 -Bytes $fixed -Offset 416 -Value 32767
    Set-RenderKitLittleEndianInt16 -Bytes $fixed -Offset 418 -Value 32767
    Set-RenderKitLittleEndianInt16 -Bytes $fixed -Offset 420 -Value 32767
    if ($ExistingPayload) {
        [System.Buffer]::BlockCopy(
            $ExistingPayload,
            0,
            $fixed,
            0,
            [Math]::Min(602, $ExistingPayload.Length)
        )
    }

    $codingHistory = if ($ExistingPayload -and
        $ExistingPayload.Length -gt 602) {
        $existingLength = $ExistingPayload.Length - 602
        $existing = New-Object byte[] $existingLength
        [System.Buffer]::BlockCopy(
            $ExistingPayload,
            602,
            $existing,
            0,
            $existingLength
        )
        ,$existing
    }
    else {
        ,([byte[]]@())
    }

    foreach ($assignment in @($assignments.Values)) {
        switch ([string]$assignment.Target) {
            'Description' {
                Set-RenderKitBwfFixedString `
                    -Bytes $fixed -Offset 0 -Length 256 `
                    -Value ([string]$assignment.Value) `
                    -Field $assignment.Field
            }
            'Originator' {
                Set-RenderKitBwfFixedString `
                    -Bytes $fixed -Offset 256 -Length 32 `
                    -Value ([string]$assignment.Value) `
                    -Field $assignment.Field
            }
            'OriginatorReference' {
                Set-RenderKitBwfFixedString `
                    -Bytes $fixed -Offset 288 -Length 32 `
                    -Value ([string]$assignment.Value) `
                    -Field $assignment.Field
            }
            'OriginationDate' {
                Set-RenderKitBwfFixedString `
                    -Bytes $fixed -Offset 320 -Length 10 `
                    -Value (ConvertTo-RenderKitBwfDate -Value $assignment.Value) `
                    -Field $assignment.Field
            }
            'OriginationTime' {
                Set-RenderKitBwfFixedString `
                    -Bytes $fixed -Offset 330 -Length 8 `
                    -Value (ConvertTo-RenderKitBwfTime -Value $assignment.Value) `
                    -Field $assignment.Field
            }
            'TimeReference' {
                Set-RenderKitLittleEndianUInt64 `
                    -Bytes $fixed `
                    -Offset 338 `
                    -Value (ConvertTo-RenderKitUInt64Value `
                        -Value $assignment.Value `
                        -Field $assignment.Field)
            }
            'Umid' {
                $umid = ConvertTo-RenderKitBwfUmidBytes -Value $assignment.Value
                [System.Buffer]::BlockCopy($umid, 0, $fixed, 348, 64)
            }
            'CodingHistory' {
                $codingHistory = ConvertTo-RenderKitRiffAsciiBytes `
                    -Value ([string]$assignment.Value) `
                    -Field $assignment.Field
            }
            'LoudnessValue' {
                Set-RenderKitLittleEndianInt16 -Bytes $fixed -Offset 412 `
                    -Value (ConvertTo-RenderKitBwfLoudnessInt16 `
                        -Value $assignment.Value -Field $assignment.Field)
            }
            'LoudnessRange' {
                Set-RenderKitLittleEndianInt16 -Bytes $fixed -Offset 414 `
                    -Value (ConvertTo-RenderKitBwfLoudnessInt16 `
                        -Value $assignment.Value -Field $assignment.Field)
            }
            'MaxTruePeakLevel' {
                Set-RenderKitLittleEndianInt16 -Bytes $fixed -Offset 416 `
                    -Value (ConvertTo-RenderKitBwfLoudnessInt16 `
                        -Value $assignment.Value -Field $assignment.Field)
            }
            'MaxMomentaryLoudness' {
                Set-RenderKitLittleEndianInt16 -Bytes $fixed -Offset 418 `
                    -Value (ConvertTo-RenderKitBwfLoudnessInt16 `
                        -Value $assignment.Value -Field $assignment.Field)
            }
            'MaxShortTermLoudness' {
                Set-RenderKitLittleEndianInt16 -Bytes $fixed -Offset 420 `
                    -Value (ConvertTo-RenderKitBwfLoudnessInt16 `
                        -Value $assignment.Value -Field $assignment.Field)
            }
        }
    }

    $requiredVersion = 0
    $umidHasValue = $false
    for ($index = 348; $index -lt 412; $index++) {
        if ($fixed[$index] -ne 0) {
            $umidHasValue = $true
            break
        }
    }
    if ($umidHasValue) {
        $requiredVersion = 1
    }
    foreach ($offset in @(412, 414, 416, 418, 420)) {
        if ((Get-RenderKitLittleEndianInt16 `
                -Bytes $fixed `
                -Offset $offset) -ne 32767) {
            $requiredVersion = 2
            break
        }
    }

    $version = [int](Get-RenderKitLittleEndianUInt16 -Bytes $fixed -Offset 346)
    if ($assignments.Contains('Version')) {
        $versionValue = ConvertTo-RenderKitMetadataInt64 `
            -Value $assignments['Version'].Value
        if ($null -eq $versionValue -or $versionValue -lt 0 -or
            $versionValue -gt 2) {
            throw 'BWF version must be 0, 1, or 2.'
        }
        $version = [int]$versionValue
    }
    elseif ($version -lt $requiredVersion) {
        $version = $requiredVersion
    }
    if ($version -lt $requiredVersion) {
        throw "BWF version $version cannot represent the supplied UMID or loudness values; version $requiredVersion is required."
    }
    Set-RenderKitLittleEndianUInt16 `
        -Bytes $fixed `
        -Offset 346 `
        -Value ([uint16]$version)

    $payload = New-Object byte[] (602 + $codingHistory.Length)
    [System.Buffer]::BlockCopy($fixed, 0, $payload, 0, 602)
    if ($codingHistory.Length -gt 0) {
        [System.Buffer]::BlockCopy(
            $codingHistory,
            0,
            $payload,
            602,
            $codingHistory.Length
        )
    }
    return ,$payload
}

function Get-RenderKitMetadataObjectProperties {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return @()
    }
    if ($Value -is [System.Collections.IDictionary]) {
        return @($Value.Keys | ForEach-Object {
            [PSCustomObject]@{
                Name = [string]$_
                Value = $Value[$_]
            }
        })
    }
    return @($Value.PSObject.Properties)
}

function Read-RenderKitIxmlDocument {
    [CmdletBinding()]
    [OutputType([System.Xml.XmlDocument])]
    param(
        [AllowNull()]
        [byte[]]$Payload
    )

    if (-not $Payload -or $Payload.Length -eq 0) {
        $document = [System.Xml.XmlDocument]::new()
        $document.PreserveWhitespace = $false
        [void]$document.AppendChild(
            $document.CreateXmlDeclaration('1.0', 'UTF-8', $null)
        )
        $root = $document.CreateElement('BWFXML')
        [void]$document.AppendChild($root)
        $version = $document.CreateElement('IXML_VERSION')
        $version.InnerText = '3.01'
        [void]$root.AppendChild($version)
        return $document
    }

    $length = $Payload.Length
    while ($length -gt 0 -and $Payload[$length - 1] -eq 0) {
        $length--
    }
    if ($length -eq 0) {
        throw 'The existing iXML chunk contains no XML document.'
    }

    $encoding = [System.Text.UTF8Encoding]::new($false, $true)
    try {
        $xml = $encoding.GetString($Payload, 0, $length)
    }
    catch {
        throw "The existing iXML chunk is not valid UTF-8: $($_.Exception.Message)"
    }

    # iXML is media-supplied input. Disable DTD/entity resolution and cap the
    # document before loading it into the mutable DOM used for field updates.
    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $settings.MaxCharactersInDocument = 16777216
    $reader = $null
    $stringReader = $null
    try {
        $stringReader = [System.IO.StringReader]::new($xml)
        $reader = [System.Xml.XmlReader]::Create($stringReader, $settings)
        $document = [System.Xml.XmlDocument]::new()
        $document.PreserveWhitespace = $true
        $document.XmlResolver = $null
        $document.Load($reader)
    }
    catch {
        throw "The existing iXML chunk is not well-formed XML: $($_.Exception.Message)"
    }
    finally {
        if ($reader) {
            $reader.Dispose()
        }
        if ($stringReader) {
            $stringReader.Dispose()
        }
    }

    if (-not $document.DocumentElement -or
        [string]$document.DocumentElement.LocalName -ine 'BWFXML') {
        throw 'The iXML document root must be BWFXML.'
    }
    return $document
}

function Get-RenderKitIxmlChildElement {
    [CmdletBinding()]
    [OutputType([System.Xml.XmlElement])]
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlElement]$Parent,

        [Parameter(Mandatory)]
        [string]$Name
    )

    return @(
        $Parent.ChildNodes |
            Where-Object {
                $_ -is [System.Xml.XmlElement] -and
                [string]$_.LocalName -ieq $Name
            } |
            Select-Object -First 1
    )
}

function Get-RenderKitIxmlElementPath {
    [CmdletBinding()]
    [OutputType([System.Xml.XmlElement])]
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlDocument]$Document,

        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$Create
    )

    $current = $Document.DocumentElement
    foreach ($segment in @($Path -split '/')) {
        if ([string]::IsNullOrWhiteSpace($segment)) {
            throw "iXML target path '$Path' is invalid."
        }
        $child = Get-RenderKitIxmlChildElement `
            -Parent $current `
            -Name $segment
        if (-not $child) {
            if (-not $Create) {
                return $null
            }
            $child = if ([string]::IsNullOrWhiteSpace($current.NamespaceURI)) {
                $Document.CreateElement($segment)
            }
            else {
                $Document.CreateElement($segment, $current.NamespaceURI)
            }
            [void]$current.AppendChild($child)
        }
        $current = $child
    }
    return $current
}

function ConvertTo-RenderKitIxmlBooleanText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Field
    )

    if ($Value -is [bool]) {
        return $(if ($Value) { 'TRUE' } else { 'FALSE' })
    }
    $text = ([string]$Value).Trim().ToLowerInvariant()
    if ($text -in @('true', '1', 'yes')) {
        return 'TRUE'
    }
    if ($text -in @('false', '0', 'no')) {
        return 'FALSE'
    }
    throw "iXML field '$Field' must be boolean."
}

function ConvertTo-RenderKitIxmlIntegerText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Field
    )

    $parsed = ConvertTo-RenderKitMetadataInt64 -Value $Value
    if ($null -eq $parsed -or $parsed -lt 0) {
        throw "iXML field '$Field' must be a non-negative integer."
    }
    return $parsed.ToString(
        [System.Globalization.CultureInfo]::InvariantCulture
    )
}

function ConvertTo-RenderKitIxmlStringText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Field
    )

    $text = [string]$Value
    try {
        [System.Xml.XmlConvert]::VerifyXmlChars($text) | Out-Null
    }
    catch {
        throw "iXML field '$Field' contains characters that XML 1.0 cannot represent."
    }
    return $text
}

function ConvertTo-RenderKitIxmlScalarText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$ValueType,

        [Parameter(Mandatory)]
        [string]$Field
    )

    switch ($ValueType) {
        'Boolean' {
            return ConvertTo-RenderKitIxmlBooleanText `
                -Value $Value `
                -Field $Field
        }
        'Integer' {
            return ConvertTo-RenderKitIxmlIntegerText `
                -Value $Value `
                -Field $Field
        }
        'Date' {
            return ConvertTo-RenderKitBwfDate -Value $Value
        }
        default {
            return ConvertTo-RenderKitIxmlStringText `
                -Value $Value `
                -Field $Field
        }
    }
}

function Get-RenderKitIxmlMetadataAssignments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Metadata
    )

    $assignments = [ordered]@{}
    foreach ($field in @($Metadata.Keys | Sort-Object)) {
        $definitions = @(
            Get-RenderKitRiffMetadataWriteDefinitions -Field ([string]$field) |
                Where-Object Profile -eq 'iXML'
        )
        foreach ($definition in $definitions) {
            $target = [string]$definition.Target
            $value = $Metadata[$field]
            if ($assignments.Contains($target)) {
                $existingJson = ConvertTo-RenderKitRiffComparableJson `
                    -Value $assignments[$target].Value
                $nextJson = ConvertTo-RenderKitRiffComparableJson `
                    -Value $value
                if ($existingJson -ne $nextJson) {
                    throw "iXML fields '$($assignments[$target].Field)' and '$field' target '$target' with conflicting values."
                }
                continue
            }
            $assignments[$target] = [PSCustomObject]@{
                Field = [string]$field
                Target = $target
                ValueType = [string]$definition.ValueType
                Value = $value
            }
        }
    }
    return $assignments
}

function Get-RenderKitIxmlSpeedMemberName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $key = [regex]::Replace($Name, '[^A-Za-z0-9]', '').ToLowerInvariant()
    $members = @{
        masterspeed = 'MASTER_SPEED'
        currentspeed = 'CURRENT_SPEED'
        timecoderate = 'TIMECODE_RATE'
        timecodeflag = 'TIMECODE_FLAG'
        filesamplerate = 'FILE_SAMPLE_RATE'
        audiobitdepth = 'AUDIO_BIT_DEPTH'
    }
    if (-not $members.ContainsKey($key)) {
        throw "iXML SPEED member '$Name' is not supported by the profile."
    }
    return [string]$members[$key]
}

function Set-RenderKitIxmlSpeedObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlDocument]$Document,

        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Field
    )

    $speed = Get-RenderKitIxmlElementPath `
        -Document $Document `
        -Path 'SPEED' `
        -Create
    foreach ($property in @(
        Get-RenderKitMetadataObjectProperties -Value $Value
    )) {
        $memberName = Get-RenderKitIxmlSpeedMemberName `
            -Name ([string]$property.Name)
        $member = Get-RenderKitIxmlChildElement `
            -Parent $speed `
            -Name $memberName
        if (-not $member) {
            $member = if ([string]::IsNullOrWhiteSpace($speed.NamespaceURI)) {
                $Document.CreateElement($memberName)
            }
            else {
                $Document.CreateElement($memberName, $speed.NamespaceURI)
            }
            [void]$speed.AppendChild($member)
        }
        $member.InnerText = ConvertTo-RenderKitIxmlStringText `
            -Value $property.Value `
            -Field "$Field.$($property.Name)"
    }
}

function Get-RenderKitIxmlTrackMemberName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $key = [regex]::Replace($Name, '[^A-Za-z0-9]', '').ToLowerInvariant()
    $members = @{
        channelindex = 'CHANNEL_INDEX'
        interleaveindex = 'INTERLEAVE_INDEX'
        name = 'NAME'
        function = 'FUNCTION'
    }
    if (-not $members.ContainsKey($key)) {
        throw "iXML TRACK member '$Name' is not supported by the profile."
    }
    return [string]$members[$key]
}

function Set-RenderKitIxmlTrackList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlDocument]$Document,

        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Field
    )

    $trackContainerValue = Get-RenderKitNestedMetadataPropertyValue `
        -Object $Value `
        -Path 'Track'
    if ($null -ne $trackContainerValue) {
        $Value = $trackContainerValue
    }
    $tracks = if ($Value -is [System.Collections.IEnumerable] -and
        -not ($Value -is [string]) -and
        -not ($Value -is [System.Collections.IDictionary]) -and
        -not ($Value -is [PSCustomObject])) {
        @($Value)
    }
    else {
        @($Value)
    }
    if ($tracks.Count -eq 0) {
        throw "iXML field '$Field' must contain at least one track."
    }

    $trackList = Get-RenderKitIxmlElementPath `
        -Document $Document `
        -Path 'TRACK_LIST' `
        -Create
    foreach ($child in @($trackList.ChildNodes)) {
        if ($child -is [System.Xml.XmlElement] -and
            [string]$child.LocalName -ieq 'TRACK') {
            [void]$trackList.RemoveChild($child)
        }
    }

    foreach ($trackValue in $tracks) {
        $properties = @(
            Get-RenderKitMetadataObjectProperties -Value $trackValue
        )
        $propertyKeys = @($properties | ForEach-Object {
            [regex]::Replace(
                [string]$_.Name,
                '[^A-Za-z0-9]',
                ''
            ).ToLowerInvariant()
        })
        if ($propertyKeys -notcontains 'channelindex' -or
            $propertyKeys -notcontains 'interleaveindex') {
            throw "Every iXML TRACK in '$Field' requires ChannelIndex and InterleaveIndex."
        }

        $track = if ([string]::IsNullOrWhiteSpace($trackList.NamespaceURI)) {
            $Document.CreateElement('TRACK')
        }
        else {
            $Document.CreateElement('TRACK', $trackList.NamespaceURI)
        }
        foreach ($property in $properties) {
            $memberName = Get-RenderKitIxmlTrackMemberName `
                -Name ([string]$property.Name)
            $member = if ([string]::IsNullOrWhiteSpace($track.NamespaceURI)) {
                $Document.CreateElement($memberName)
            }
            else {
                $Document.CreateElement($memberName, $track.NamespaceURI)
            }
            $member.InnerText = if ($memberName -in @(
                    'CHANNEL_INDEX',
                    'INTERLEAVE_INDEX'
                )) {
                ConvertTo-RenderKitIxmlIntegerText `
                    -Value $property.Value `
                    -Field "$Field.$($property.Name)"
            }
            else {
                ConvertTo-RenderKitIxmlStringText `
                    -Value $property.Value `
                    -Field "$Field.$($property.Name)"
            }
            [void]$track.AppendChild($member)
        }
        [void]$trackList.AppendChild($track)
    }
}

function Set-RenderKitIxmlUInt64Pair {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlDocument]$Document,

        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Field
    )

    $number = ConvertTo-RenderKitUInt64Value -Value $Value -Field $Field
    $high = [uint32]($number -shr 32)
    $low = [uint32]($number -band [uint64]4294967295)
    foreach ($part in @(
        [PSCustomObject]@{
            Path = 'TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_HI'
            Value = $high
        },
        [PSCustomObject]@{
            Path = 'TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_LO'
            Value = $low
        }
    )) {
        $element = Get-RenderKitIxmlElementPath `
            -Document $Document `
            -Path $part.Path `
            -Create
        $element.InnerText = ([uint32]$part.Value).ToString(
            [System.Globalization.CultureInfo]::InvariantCulture
        )
    }
}

function ConvertTo-RenderKitIxmlBytes {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlDocument]$Document
    )

    $settings = [System.Xml.XmlWriterSettings]::new()
    $settings.Encoding = [System.Text.UTF8Encoding]::new($false)
    $settings.Indent = $true
    $settings.NewLineChars = "`n"
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
    $settings.CheckCharacters = $true
    $settings.OmitXmlDeclaration = $false

    $stream = [System.IO.MemoryStream]::new()
    $writer = $null
    try {
        $writer = [System.Xml.XmlWriter]::Create($stream, $settings)
        $Document.Save($writer)
        $writer.Flush()
        if ($stream.Length -gt 16777216) {
            throw 'The generated iXML chunk exceeds the 16 MiB safety limit.'
        }
        return ,$stream.ToArray()
    }
    finally {
        if ($writer) {
            $writer.Dispose()
        }
        $stream.Dispose()
    }
}

function New-RenderKitIxmlChunkPayload {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [AllowNull()]
        [byte[]]$ExistingPayload,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Metadata
    )

    $assignments = Get-RenderKitIxmlMetadataAssignments -Metadata $Metadata
    if ($assignments.Count -eq 0) {
        return $null
    }

    $document = Read-RenderKitIxmlDocument -Payload $ExistingPayload
    $version = Get-RenderKitIxmlElementPath `
        -Document $document `
        -Path 'IXML_VERSION'
    if (-not $version) {
        $version = Get-RenderKitIxmlElementPath `
            -Document $document `
            -Path 'IXML_VERSION' `
            -Create
        $version.InnerText = '3.01'
    }

    if ($assignments.Contains('SPEED')) {
        Set-RenderKitIxmlSpeedObject `
            -Document $document `
            -Value $assignments['SPEED'].Value `
            -Field $assignments['SPEED'].Field
    }
    if ($assignments.Contains('TRACK_LIST')) {
        Set-RenderKitIxmlTrackList `
            -Document $document `
            -Value $assignments['TRACK_LIST'].Value `
            -Field $assignments['TRACK_LIST'].Field
    }
    if ($assignments.Contains('TIMESTAMP_SAMPLES_SINCE_MIDNIGHT')) {
        Set-RenderKitIxmlUInt64Pair `
            -Document $document `
            -Value $assignments['TIMESTAMP_SAMPLES_SINCE_MIDNIGHT'].Value `
            -Field $assignments['TIMESTAMP_SAMPLES_SINCE_MIDNIGHT'].Field
    }

    foreach ($assignment in @($assignments.Values)) {
        if ([string]$assignment.ValueType -in @(
                'SpeedObject',
                'TrackList',
                'UInt64Pair'
            )) {
            continue
        }
        $element = Get-RenderKitIxmlElementPath `
            -Document $document `
            -Path ([string]$assignment.Target) `
            -Create
        $element.InnerText = ConvertTo-RenderKitIxmlScalarText `
            -Value $assignment.Value `
            -ValueType ([string]$assignment.ValueType) `
            -Field ([string]$assignment.Field)
    }

    return ConvertTo-RenderKitIxmlBytes -Document $document
}

function Read-RenderKitStreamBytesExact {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory)]
        [System.IO.Stream]$Stream,

        [Parameter(Mandatory)]
        [ValidateRange(0, 16777216)]
        [int]$Count
    )

    $bytes = New-Object byte[] $Count
    $offset = 0
    while ($offset -lt $Count) {
        $read = $Stream.Read($bytes, $offset, $Count - $offset)
        if ($read -le 0) {
            throw "Unexpected end of stream after $offset of $Count bytes."
        }
        $offset += $read
    }
    return ,$bytes
}

function Copy-RenderKitStreamRange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.Stream]$Source,

        [Parameter(Mandatory)]
        [System.IO.Stream]$Destination,

        [Parameter(Mandatory)]
        [uint64]$Count
    )

    $buffer = New-Object byte[] 1048576
    $remaining = $Count
    while ($remaining -gt 0) {
        $requested = [int][Math]::Min(
            [double]$buffer.Length,
            [double]$remaining
        )
        $read = $Source.Read($buffer, 0, $requested)
        if ($read -le 0) {
            throw "Unexpected end of RIFF stream with $remaining bytes left to copy."
        }
        $Destination.Write($buffer, 0, $read)
        $remaining -= [uint64]$read
    }
}

function ConvertFrom-RenderKitRiffFourCc {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes
    )

    if ($Bytes.Length -ne 4) {
        throw 'A RIFF FourCC must contain exactly four bytes.'
    }
    return [System.Text.Encoding]::ASCII.GetString($Bytes)
}

function ConvertTo-RenderKitRiffFourCcBytes {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    if ($Value.Length -ne 4) {
        throw "RIFF FourCC '$Value' must contain exactly four characters."
    }
    $bytes = ConvertTo-RenderKitRiffAsciiBytes -Value $Value -Field 'FourCC'
    if ($bytes.Length -ne 4) {
        throw "RIFF FourCC '$Value' must contain exactly four ASCII bytes."
    }
    return ,$bytes
}

function Read-RenderKitDs64Payload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Payload
    )

    if ($Payload.Length -lt 28) {
        throw 'RF64 ds64 chunk is shorter than its 28-byte fixed header.'
    }
    $tableLength = Get-RenderKitLittleEndianUInt32 `
        -Bytes $Payload `
        -Offset 24
    $expectedLength = [uint64]28 + ([uint64]$tableLength * [uint64]12)
    if ($expectedLength -gt [uint64]$Payload.Length) {
        throw 'RF64 ds64 chunk table extends beyond the chunk payload.'
    }

    # In RF64, chunks whose 32-bit size is 0xffffffff obtain their real 64-bit
    # size from this table. Entry order therefore matters for repeated IDs.
    $entries = New-Object System.Collections.Generic.List[object]
    for ($index = 0; $index -lt $tableLength; $index++) {
        $offset = 28 + ($index * 12)
        $idBytes = New-Object byte[] 4
        [System.Buffer]::BlockCopy($Payload, $offset, $idBytes, 0, 4)
        $entries.Add([PSCustomObject]@{
            Id = ConvertFrom-RenderKitRiffFourCc -Bytes $idBytes
            Size = Get-RenderKitLittleEndianUInt64 `
                -Bytes $Payload `
                -Offset ($offset + 4)
        })
    }

    return [PSCustomObject]@{
        RiffSize = Get-RenderKitLittleEndianUInt64 -Bytes $Payload -Offset 0
        DataSize = Get-RenderKitLittleEndianUInt64 -Bytes $Payload -Offset 8
        SampleCount = Get-RenderKitLittleEndianUInt64 `
            -Bytes $Payload `
            -Offset 16
        Entries = @($entries.ToArray())
    }
}

function Read-RenderKitRiffLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string[]]$PayloadChunkId = @('bext', 'iXML')
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    $stream = [System.IO.FileStream]::new(
        $resolvedPath,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read,
        1048576,
        [System.IO.FileOptions]::SequentialScan
    )
    $reader = [System.IO.BinaryReader]::new(
        $stream,
        [System.Text.Encoding]::ASCII,
        $true
    )
    try {
        if ($stream.Length -lt 12) {
            throw "File '$resolvedPath' is too short to be RIFF/WAVE."
        }
        $containerId = ConvertFrom-RenderKitRiffFourCc `
            -Bytes (Read-RenderKitStreamBytesExact -Stream $stream -Count 4)
        if ($containerId -notin @('RIFF', 'RF64')) {
            throw "File '$resolvedPath' is '$containerId', not RIFF or RF64."
        }
        $declaredSize = $reader.ReadUInt32()
        $formType = ConvertFrom-RenderKitRiffFourCc `
            -Bytes (Read-RenderKitStreamBytesExact -Stream $stream -Count 4)
        if ($formType -ne 'WAVE') {
            throw "RIFF file '$resolvedPath' has form type '$formType', not WAVE."
        }

        $chunks = New-Object System.Collections.Generic.List[object]
        $ds64 = $null
        $ds64Queues = @{}
        $payloadSet = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
        foreach ($id in $PayloadChunkId) {
            [void]$payloadSet.Add([string]$id)
        }

        while ($stream.Position + 8 -le $stream.Length) {
            $headerOffset = [uint64]$stream.Position
            $idBytes = Read-RenderKitStreamBytesExact -Stream $stream -Count 4
            $id = ConvertFrom-RenderKitRiffFourCc -Bytes $idBytes
            $size32 = $reader.ReadUInt32()
            $dataOffset = [uint64]$stream.Position

            $logicalSize = [uint64]$size32
            if ($size32 -eq [uint32]::MaxValue) {
                if (-not $ds64) {
                    throw "RF64 chunk '$id' uses 0xffffffff before a ds64 chunk defines its size."
                }
                if ($id -eq 'data') {
                    $logicalSize = [uint64]$ds64.DataSize
                }
                elseif ($ds64Queues.ContainsKey($id) -and
                    $ds64Queues[$id].Count -gt 0) {
                    $logicalSize = [uint64]$ds64Queues[$id][0]
                    $ds64Queues[$id].RemoveAt(0)
                }
                else {
                    throw "RF64 ds64 does not define the 64-bit size of chunk '$id'."
                }
            }

            $paddingLength = [uint64]($logicalSize % 2)
            $chunkEnd = $dataOffset + $logicalSize + $paddingLength
            if ($chunkEnd -gt [uint64]$stream.Length) {
                throw "RIFF chunk '$id' extends beyond the end of '$resolvedPath'."
            }

            $payload = $null
            if ($id -eq 'ds64') {
                if ($logicalSize -gt 16777216) {
                    throw 'RF64 ds64 chunk exceeds the 16 MiB safety limit.'
                }
                $payload = Read-RenderKitStreamBytesExact `
                    -Stream $stream `
                    -Count ([int]$logicalSize)
                $ds64 = Read-RenderKitDs64Payload -Payload $payload
                foreach ($entry in @($ds64.Entries)) {
                    if (-not $ds64Queues.ContainsKey([string]$entry.Id)) {
                        $ds64Queues[[string]$entry.Id] =
                            New-Object System.Collections.ArrayList
                    }
                    [void]$ds64Queues[[string]$entry.Id].Add(
                        [uint64]$entry.Size
                    )
                }
            }
            elseif ($payloadSet.Contains($id)) {
                if ($logicalSize -gt 16777216) {
                    throw "RIFF metadata chunk '$id' exceeds the 16 MiB safety limit."
                }
                $payload = Read-RenderKitStreamBytesExact `
                    -Stream $stream `
                    -Count ([int]$logicalSize)
            }

            $chunks.Add([PSCustomObject]@{
                Id = $id
                HeaderOffset = $headerOffset
                DataOffset = $dataOffset
                Size32 = [uint32]$size32
                LogicalSize = [uint64]$logicalSize
                PaddingLength = [uint64]$paddingLength
                Payload = $payload
            })
            $stream.Position = [int64]$chunkEnd
        }

        if ($containerId -eq 'RF64' -and -not $ds64) {
            throw "RF64 file '$resolvedPath' has no ds64 chunk."
        }

        return [PSCustomObject]@{
            Path = $resolvedPath
            ContainerId = $containerId
            DeclaredSize32 = [uint32]$declaredSize
            FormType = $formType
            FileLength = [uint64]$stream.Length
            ParsedEnd = [uint64]$stream.Position
            Chunks = @($chunks.ToArray())
            Ds64 = $ds64
        }
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Get-RenderKitRiffFirstChunkPayload {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory)]
        [object]$Layout,

        [Parameter(Mandatory)]
        [string]$Id
    )

    $chunk = @(
        $Layout.Chunks |
            Where-Object { [string]$_.Id -ieq $Id } |
            Select-Object -First 1
    )
    if (-not $chunk) {
        return $null
    }
    return ,([byte[]]$chunk[0].Payload)
}

function Write-RenderKitRiffChunkPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.Stream]$Stream,

        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [byte[]]$Payload
    )

    if ([uint64]$Payload.Length -gt [uint32]::MaxValue) {
        throw "RIFF metadata chunk '$Id' exceeds the 32-bit chunk-size limit."
    }
    $idBytes = ConvertTo-RenderKitRiffFourCcBytes -Value $Id
    $Stream.Write($idBytes, 0, 4)
    $sizeBytes = New-Object byte[] 4
    Set-RenderKitLittleEndianUInt32 `
        -Bytes $sizeBytes `
        -Offset 0 `
        -Value ([uint32]$Payload.Length)
    $Stream.Write($sizeBytes, 0, 4)
    $Stream.Write($Payload, 0, $Payload.Length)
    if (($Payload.Length % 2) -ne 0) {
        $Stream.WriteByte(0)
    }
}

function Write-RenderKitRiffMetadataFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$SourceLayout,

        [Parameter(Mandatory)]
        [string]$DestinationPath,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$ReplacementPayloads
    )

    $source = [System.IO.FileStream]::new(
        [string]$SourceLayout.Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read,
        1048576,
        [System.IO.FileOptions]::SequentialScan
    )
    $destination = [System.IO.FileStream]::new(
        $DestinationPath,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None,
        1048576,
        [System.IO.FileOptions]::SequentialScan
    )
    try {
        $source.Position = 0
        Copy-RenderKitStreamRange `
            -Source $source `
            -Destination $destination `
            -Count 12

        $writtenTargets = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
        $ds64OutputDataOffset = $null
        $targetOrder = @('bext', 'iXML')

        foreach ($chunk in @($SourceLayout.Chunks)) {
            $isTarget = $ReplacementPayloads.Contains(
                ([string]$chunk.Id).ToLowerInvariant()
            )
            if ([string]$chunk.Id -ieq 'data') {
                foreach ($targetId in $targetOrder) {
                    $key = $targetId.ToLowerInvariant()
                    if ($ReplacementPayloads.Contains($key) -and
                        -not $writtenTargets.Contains($key)) {
                        Write-RenderKitRiffChunkPayload `
                            -Stream $destination `
                            -Id $targetId `
                            -Payload ([byte[]]$ReplacementPayloads[$key])
                        [void]$writtenTargets.Add($key)
                    }
                }
            }

            if ($isTarget) {
                $key = ([string]$chunk.Id).ToLowerInvariant()
                if ([uint32]$chunk.Size32 -eq [uint32]::MaxValue) {
                    throw "RF64 metadata chunk '$($chunk.Id)' uses a ds64 table size and cannot be replaced safely."
                }
                if (-not $writtenTargets.Contains($key)) {
                    $canonicalId = if ($key -eq 'bext') { 'bext' } else { 'iXML' }
                    Write-RenderKitRiffChunkPayload `
                        -Stream $destination `
                        -Id $canonicalId `
                        -Payload ([byte[]]$ReplacementPayloads[$key])
                    [void]$writtenTargets.Add($key)
                }
                continue
            }

            if ([string]$chunk.Id -eq 'ds64') {
                $ds64OutputDataOffset = [uint64]$destination.Position + 8
            }
            $source.Position = [int64]$chunk.HeaderOffset
            Copy-RenderKitStreamRange `
                -Source $source `
                -Destination $destination `
                -Count (
                    [uint64]8 +
                    [uint64]$chunk.LogicalSize +
                    [uint64]$chunk.PaddingLength
                )
        }

        foreach ($targetId in $targetOrder) {
            $key = $targetId.ToLowerInvariant()
            if ($ReplacementPayloads.Contains($key) -and
                -not $writtenTargets.Contains($key)) {
                Write-RenderKitRiffChunkPayload `
                    -Stream $destination `
                    -Id $targetId `
                    -Payload ([byte[]]$ReplacementPayloads[$key])
                [void]$writtenTargets.Add($key)
            }
        }

        if ([uint64]$SourceLayout.ParsedEnd -lt
            [uint64]$SourceLayout.FileLength) {
            $source.Position = [int64]$SourceLayout.ParsedEnd
            Copy-RenderKitStreamRange `
                -Source $source `
                -Destination $destination `
                -Count (
                    [uint64]$SourceLayout.FileLength -
                    [uint64]$SourceLayout.ParsedEnd
                )
        }

        $riffSize = [uint64]$destination.Length - [uint64]8
        if ([string]$SourceLayout.ContainerId -eq 'RIFF') {
            if ($riffSize -gt [uint32]::MaxValue) {
                throw 'The rewritten RIFF file exceeds 4 GiB; explicit RF64 conversion is required.'
            }
            $sizeBytes = New-Object byte[] 4
            Set-RenderKitLittleEndianUInt32 `
                -Bytes $sizeBytes `
                -Offset 0 `
                -Value ([uint32]$riffSize)
            $destination.Position = 4
            $destination.Write($sizeBytes, 0, 4)
        }
        else {
            if ($null -eq $ds64OutputDataOffset) {
                throw 'The rewritten RF64 file has no ds64 chunk to update.'
            }
            $sizeBytes = New-Object byte[] 8
            Set-RenderKitLittleEndianUInt64 `
                -Bytes $sizeBytes `
                -Offset 0 `
                -Value $riffSize
            $destination.Position = [int64]$ds64OutputDataOffset
            $destination.Write($sizeBytes, 0, 8)
        }

        $destination.Flush($true)
    }
    finally {
        $destination.Dispose()
        $source.Dispose()
    }
}

function Get-RenderKitByteArraySha256 {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes
    )

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (
            [System.BitConverter]::ToString($sha.ComputeHash($Bytes)) -replace
            '-',
            ''
        )
    }
    finally {
        $sha.Dispose()
    }
}

function Get-RenderKitRiffPreservationSignature {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [object]$Layout
    )

    return @(
        $Layout.Chunks |
            Where-Object {
                [string]$_.Id -ine 'bext' -and
                [string]$_.Id -ine 'iXML'
            } |
            ForEach-Object {
                '{0}|{1}|{2}' -f `
                    [string]$_.Id,
                    [uint32]$_.Size32,
                    [uint64]$_.LogicalSize
            }
    )
}

function Test-RenderKitRiffMetadataRewrite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$SourceLayout,

        [Parameter(Mandatory)]
        [object]$CandidateLayout,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$ReplacementPayloads
    )

    if ([string]$SourceLayout.ContainerId -ne
        [string]$CandidateLayout.ContainerId) {
        throw 'RIFF metadata rewrite changed the container type.'
    }

    $sourceSignature = @(
        Get-RenderKitRiffPreservationSignature -Layout $SourceLayout
    )
    $candidateSignature = @(
        Get-RenderKitRiffPreservationSignature -Layout $CandidateLayout
    )
    if (($sourceSignature -join "`n") -ne
        ($candidateSignature -join "`n")) {
        throw 'RIFF metadata rewrite changed a non-target chunk layout.'
    }

    foreach ($key in @($ReplacementPayloads.Keys)) {
        $actual = Get-RenderKitRiffFirstChunkPayload `
            -Layout $CandidateLayout `
            -Id ([string]$key)
        if (-not $actual) {
            throw "RIFF metadata rewrite did not create chunk '$key'."
        }
        $expectedHash = Get-RenderKitByteArraySha256 `
            -Bytes ([byte[]]$ReplacementPayloads[$key])
        $actualHash = Get-RenderKitByteArraySha256 -Bytes ([byte[]]$actual
        )
        if ($actualHash -ne $expectedHash) {
            throw "RIFF metadata chunk '$key' failed read-after-write verification."
        }
        if ([string]$key -ieq 'iXML') {
            Read-RenderKitIxmlDocument -Payload ([byte[]]$actual) |
                Out-Null
        }
    }

    return $true
}

function Get-RenderKitRiffMetadataLockTarget {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $canonicalPath = [System.IO.Path]::GetFullPath($Path).ToLowerInvariant()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonicalPath)
    $hash = Get-RenderKitByteArraySha256 -Bytes $bytes
    $lockRoot = Join-Path `
        -Path ([System.IO.Path]::GetTempPath()) `
        -ChildPath 'RenderKit/riff-metadata-locks'
    return Join-Path -Path $lockRoot -ChildPath $hash
}

function ConvertFrom-RenderKitBwfChunkPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Payload
    )

    if ($Payload.Length -lt 602) {
        throw "BEXT chunk is $($Payload.Length) bytes; at least 602 bytes are required."
    }
    $fields = [ordered]@{}
    foreach ($definition in @(
        [PSCustomObject]@{
            Field = 'BwfDescription'; Offset = 0; Length = 256
        },
        [PSCustomObject]@{
            Field = 'BwfOriginator'; Offset = 256; Length = 32
        },
        [PSCustomObject]@{
            Field = 'BwfOriginatorReference'; Offset = 288; Length = 32
        },
        [PSCustomObject]@{
            Field = 'BwfOriginationDate'; Offset = 320; Length = 10
        },
        [PSCustomObject]@{
            Field = 'BwfOriginationTime'; Offset = 330; Length = 8
        }
    )) {
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name $definition.Field `
            -Value (
                Get-RenderKitBwfFixedString `
                    -Bytes $Payload `
                    -Offset $definition.Offset `
                    -Length $definition.Length
            )
    }

    if ($fields.Contains('BwfOriginationDate')) {
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'RecordingDate' `
            -Value $fields['BwfOriginationDate']
    }
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'BwfTimeReferenceSamples' `
        -Value (
            Get-RenderKitLittleEndianUInt64 -Bytes $Payload -Offset 338
        )
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name 'BwfVersion' `
        -Value (
            Get-RenderKitLittleEndianUInt16 -Bytes $Payload -Offset 346
        )

    $umid = New-Object byte[] 64
    [System.Buffer]::BlockCopy($Payload, 348, $umid, 0, 64)
    if (@($umid | Where-Object { $_ -ne 0 }).Count -gt 0) {
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'BwfUmid' `
            -Value (
                [System.BitConverter]::ToString($umid) -replace '-',
                ''
            )
    }

    foreach ($definition in @(
        [PSCustomObject]@{
            Field = 'BwfLoudnessValue'; Offset = 412
        },
        [PSCustomObject]@{
            Field = 'BwfLoudnessRange'; Offset = 414
        },
        [PSCustomObject]@{
            Field = 'BwfMaxTruePeakLevel'; Offset = 416
        },
        [PSCustomObject]@{
            Field = 'BwfMaxMomentaryLoudness'; Offset = 418
        },
        [PSCustomObject]@{
            Field = 'BwfMaxShortTermLoudness'; Offset = 420
        }
    )) {
        $rawValue = Get-RenderKitLittleEndianInt16 `
            -Bytes $Payload `
            -Offset $definition.Offset
        if ($rawValue -ne 32767) {
            Set-RenderKitMetadataFieldValue `
                -Fields $fields `
                -Name $definition.Field `
                -Value ([double]$rawValue / 100)
        }
    }

    if ($Payload.Length -gt 602) {
        $codingHistory = [System.Text.Encoding]::ASCII.GetString(
            $Payload,
            602,
            $Payload.Length - 602
        ).TrimEnd([char]0)
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'BwfCodingHistory' `
            -Value $codingHistory
    }
    return $fields
}

function Get-RenderKitIxmlElementText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlDocument]$Document,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $element = Get-RenderKitIxmlElementPath `
        -Document $Document `
        -Path $Path
    if (-not $element) {
        return $null
    }
    return [string]$element.InnerText
}

function ConvertFrom-RenderKitIxmlBoolean {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }
    switch ($Value.Trim().ToUpperInvariant()) {
        'TRUE' { return $true }
        '1' { return $true }
        'YES' { return $true }
        'FALSE' { return $false }
        '0' { return $false }
        'NO' { return $false }
        default { return $null }
    }
}

function ConvertFrom-RenderKitIxmlChunkPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Payload
    )

    $document = Read-RenderKitIxmlDocument -Payload $Payload
    $fields = [ordered]@{}
    foreach ($definition in @(
        [PSCustomObject]@{
            Field = 'IxmlProject'; Path = 'PROJECT'; Converter = 'String'
        },
        [PSCustomObject]@{
            Field = 'IxmlScene'; Path = 'SCENE'; Converter = 'String'
        },
        [PSCustomObject]@{
            Field = 'IxmlTake'; Path = 'TAKE'; Converter = 'String'
        },
        [PSCustomObject]@{
            Field = 'IxmlTape'; Path = 'TAPE'; Converter = 'String'
        },
        [PSCustomObject]@{
            Field = 'IxmlNote'; Path = 'NOTE'; Converter = 'String'
        },
        [PSCustomObject]@{
            Field = 'IxmlUserBits'; Path = 'UBITS'; Converter = 'String'
        },
        [PSCustomObject]@{
            Field = 'IxmlCircled'; Path = 'CIRCLED'; Converter = 'Boolean'
        },
        [PSCustomObject]@{
            Field = 'IxmlNoGood'; Path = 'NO_GOOD'; Converter = 'Boolean'
        },
        [PSCustomObject]@{
            Field = 'IxmlFalseStart'; Path = 'FALSE_START'; Converter = 'Boolean'
        },
        [PSCustomObject]@{
            Field = 'IxmlWildTrack'; Path = 'WILD_TRACK'; Converter = 'Boolean'
        },
        [PSCustomObject]@{
            Field = 'IxmlPreRecordSampleCount'; Path = 'PRE_RECORD_SAMPLECOUNT'; Converter = 'Integer'
        },
        [PSCustomObject]@{
            Field = 'IxmlFamilyUid'; Path = 'FILE_SET/FAMILY_UID'; Converter = 'String'
        },
        [PSCustomObject]@{
            Field = 'IxmlFileSetCount'; Path = 'FILE_SET/TOTAL_FILES'; Converter = 'Integer'
        },
        [PSCustomObject]@{
            Field = 'IxmlFileSetIndex'; Path = 'FILE_SET/FILE_SET_INDEX'; Converter = 'Integer'
        },
        [PSCustomObject]@{
            Field = 'IxmlLocation'; Path = 'LOCATION/NAME'; Converter = 'String'
        },
        [PSCustomObject]@{
            Field = 'IxmlSampleRate'; Path = 'SPEED/FILE_SAMPLE_RATE'; Converter = 'Integer'
        },
        [PSCustomObject]@{
            Field = 'IxmlBitDepth'; Path = 'SPEED/AUDIO_BIT_DEPTH'; Converter = 'Integer'
        },
        [PSCustomObject]@{
            Field = 'ProductionDate'; Path = 'PRODUCTION_DATE'; Converter = 'Date'
        },
        [PSCustomObject]@{
            Field = 'RecordingDate'; Path = 'BEXT/ORIGINATION_DATE'; Converter = 'Date'
        },
        [PSCustomObject]@{
            Field = 'Slate'; Path = 'SLATE'; Converter = 'String'
        }
    )) {
        $text = Get-RenderKitIxmlElementText `
            -Document $document `
            -Path $definition.Path
        $value = switch ([string]$definition.Converter) {
            'Boolean' {
                ConvertFrom-RenderKitIxmlBoolean -Value $text
            }
            'Integer' {
                ConvertTo-RenderKitMetadataInt64 -Value $text
            }
            'Date' {
                if ([string]::IsNullOrWhiteSpace($text)) {
                    $null
                }
                else {
                    ConvertTo-RenderKitBwfDate -Value $text
                }
            }
            default { $text }
        }
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name $definition.Field `
            -Value $value
    }

    if ($fields.Contains('IxmlScene')) {
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'Scene' `
            -Value $fields['IxmlScene']
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'SceneNumber' `
            -Value $fields['IxmlScene']
    }
    if ($fields.Contains('IxmlTake')) {
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'Take' `
            -Value $fields['IxmlTake']
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'TakeNumber' `
            -Value $fields['IxmlTake']
    }

    $speedElement = Get-RenderKitIxmlElementPath `
        -Document $document `
        -Path 'SPEED'
    if ($speedElement) {
        $speed = [ordered]@{}
        $speedNames = @{
            MASTER_SPEED = 'MasterSpeed'
            CURRENT_SPEED = 'CurrentSpeed'
            TIMECODE_RATE = 'TimecodeRate'
            TIMECODE_FLAG = 'TimecodeFlag'
            FILE_SAMPLE_RATE = 'FileSampleRate'
            AUDIO_BIT_DEPTH = 'AudioBitDepth'
        }
        foreach ($child in @($speedElement.ChildNodes)) {
            if (-not ($child -is [System.Xml.XmlElement])) {
                continue
            }
            $key = ([string]$child.LocalName).ToUpperInvariant()
            if ($speedNames.ContainsKey($key)) {
                $speed[$speedNames[$key]] = [string]$child.InnerText
            }
        }
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'IxmlSpeed' `
            -Value ([PSCustomObject]$speed)
    }

    $highText = Get-RenderKitIxmlElementText `
        -Document $document `
        -Path 'TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_HI'
    $lowText = Get-RenderKitIxmlElementText `
        -Document $document `
        -Path 'TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_LO'
    if (-not [string]::IsNullOrWhiteSpace($highText) -and
        -not [string]::IsNullOrWhiteSpace($lowText)) {
        $high = ConvertTo-RenderKitUInt64Value `
            -Value $highText `
            -Field 'TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_HI'
        $low = ConvertTo-RenderKitUInt64Value `
            -Value $lowText `
            -Field 'TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_LO'
        if ($high -gt [uint32]::MaxValue -or
            $low -gt [uint32]::MaxValue) {
            throw 'iXML timestamp HI and LO words must be unsigned 32-bit integers.'
        }
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'IxmlTimestampSamplesSinceMidnight' `
            -Value ([uint64](
                ($high * [uint64]4294967296) + $low
            ))
    }

    $trackList = Get-RenderKitIxmlElementPath `
        -Document $document `
        -Path 'TRACK_LIST'
    if ($trackList) {
        $tracks = New-Object System.Collections.Generic.List[object]
        foreach ($trackElement in @($trackList.ChildNodes)) {
            if (-not ($trackElement -is [System.Xml.XmlElement]) -or
                [string]$trackElement.LocalName -ine 'TRACK') {
                continue
            }
            $track = [ordered]@{}
            foreach ($definition in @(
                [PSCustomObject]@{
                    Name = 'CHANNEL_INDEX'; Field = 'ChannelIndex'; Integer = $true
                },
                [PSCustomObject]@{
                    Name = 'INTERLEAVE_INDEX'; Field = 'InterleaveIndex'; Integer = $true
                },
                [PSCustomObject]@{
                    Name = 'NAME'; Field = 'Name'; Integer = $false
                },
                [PSCustomObject]@{
                    Name = 'FUNCTION'; Field = 'Function'; Integer = $false
                }
            )) {
                $element = Get-RenderKitIxmlChildElement `
                    -Parent $trackElement `
                    -Name $definition.Name
                if (-not $element) {
                    continue
                }
                $track[$definition.Field] = if ($definition.Integer) {
                    ConvertTo-RenderKitMetadataInt64 -Value $element.InnerText
                }
                else {
                    [string]$element.InnerText
                }
            }
            $tracks.Add([PSCustomObject]$track)
        }
        if ($tracks.Count -gt 0) {
            Set-RenderKitMetadataFieldValue `
                -Fields $fields `
                -Name 'IxmlTrackList' `
                -Value @($tracks.ToArray())
        }
    }

    return $fields
}

function Read-RenderKitRiffEmbeddedMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $fields = [ordered]@{}
    $warnings = New-Object System.Collections.Generic.List[string]
    $layout = Read-RenderKitRiffLayout -Path $Path
    $bwfPayload = Get-RenderKitRiffFirstChunkPayload `
        -Layout $layout `
        -Id 'bext'
    if ($bwfPayload) {
        try {
            Merge-RenderKitMetadataFieldBag `
                -Target $fields `
                -Source (
                    ConvertFrom-RenderKitBwfChunkPayload `
                        -Payload ([byte[]]$bwfPayload)
                )
        }
        catch {
            $warnings.Add("BEXT parsing failed: $($_.Exception.Message)")
        }
    }

    $ixmlPayload = Get-RenderKitRiffFirstChunkPayload `
        -Layout $layout `
        -Id 'iXML'
    if ($ixmlPayload) {
        try {
            Merge-RenderKitMetadataFieldBag `
                -Target $fields `
                -Source (
                    ConvertFrom-RenderKitIxmlChunkPayload `
                        -Payload ([byte[]]$ixmlPayload)
                )
        }
        catch {
            $warnings.Add("iXML parsing failed: $($_.Exception.Message)")
        }
    }

    return [PSCustomObject]@{
        Fields = $fields
        Warnings = @($warnings.ToArray())
        BwfPresent = $null -ne $bwfPayload
        IxmlPresent = $null -ne $ixmlPayload
        Container = [string]$layout.ContainerId
    }
}

function Invoke-RenderKitRiffMetadataWrite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Metadata
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    if (-not (Test-RenderKitRiffMetadataWritePath -Path $resolvedPath)) {
        throw "Native BWF/iXML writes are only supported for WAV, WAVE, BWF, and RF64 files."
    }

    $writtenFields = @(
        $Metadata.Keys |
            Where-Object {
                @(Get-RenderKitRiffMetadataWriteDefinitions `
                    -Field ([string]$_)).Count -gt 0
            } |
            ForEach-Object { [string]$_ } |
            Sort-Object -Unique
    )
    if ($writtenFields.Count -eq 0) {
        throw 'The metadata set contains no writable BWF or iXML fields.'
    }

    $lockHandle = Enter-RenderKitFileLock `
        -Path (Get-RenderKitRiffMetadataLockTarget -Path $resolvedPath) `
        -TimeoutMilliseconds 30000
    $temporaryPath = Join-Path `
        -Path (Split-Path -Path $resolvedPath -Parent) `
        -ChildPath (
            '.{0}.renderkit-{1}.tmp{2}' -f
                [System.IO.Path]::GetFileNameWithoutExtension($resolvedPath),
                [guid]::NewGuid().ToString('N'),
                [System.IO.Path]::GetExtension($resolvedPath)
        )
    $backupPath = Join-Path `
        -Path (Split-Path -Path $resolvedPath -Parent) `
        -ChildPath (
            '.{0}.renderkit-{1}.bak' -f
                [System.IO.Path]::GetFileName($resolvedPath),
                [guid]::NewGuid().ToString('N')
        )
    $replacementComplete = $false
    $preserveBackup = $false
    $sourceTimestamp = [System.IO.File]::GetLastWriteTimeUtc($resolvedPath)
    $sourceAttributes = [System.IO.File]::GetAttributes($resolvedPath)

    # The original is never edited in place: rewrite and validate a sibling
    # candidate, replace atomically when supported, then validate once more.
    # The backup remains available until post-replacement readback succeeds.
    try {
        $sourceLayout = Read-RenderKitRiffLayout -Path $resolvedPath
        $replacementPayloads = [ordered]@{}

        $bwfPayload = New-RenderKitBwfChunkPayload `
            -ExistingPayload (
                Get-RenderKitRiffFirstChunkPayload `
                    -Layout $sourceLayout `
                    -Id 'bext'
            ) `
            -Metadata $Metadata
        if ($null -ne $bwfPayload) {
            $replacementPayloads['bext'] = [byte[]]$bwfPayload
        }

        $ixmlPayload = New-RenderKitIxmlChunkPayload `
            -ExistingPayload (
                Get-RenderKitRiffFirstChunkPayload `
                    -Layout $sourceLayout `
                    -Id 'iXML'
            ) `
            -Metadata $Metadata
        if ($null -ne $ixmlPayload) {
            $replacementPayloads['ixml'] = [byte[]]$ixmlPayload
        }

        if ($replacementPayloads.Count -eq 0) {
            throw 'No BEXT or iXML payload was generated for the requested metadata.'
        }

        Write-RenderKitRiffMetadataFile `
            -SourceLayout $sourceLayout `
            -DestinationPath $temporaryPath `
            -ReplacementPayloads $replacementPayloads
        $candidateLayout = Read-RenderKitRiffLayout -Path $temporaryPath
        Test-RenderKitRiffMetadataRewrite `
            -SourceLayout $sourceLayout `
            -CandidateLayout $candidateLayout `
            -ReplacementPayloads $replacementPayloads |
            Out-Null

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
                throw "Atomic RIFF replacement failed: $($_.Exception.Message)"
            }
        }

        [System.IO.File]::SetLastWriteTimeUtc($resolvedPath, $sourceTimestamp)
        [System.IO.File]::SetAttributes($resolvedPath, $sourceAttributes)

        $finalLayout = Read-RenderKitRiffLayout -Path $resolvedPath
        Test-RenderKitRiffMetadataRewrite `
            -SourceLayout $sourceLayout `
            -CandidateLayout $finalLayout `
            -ReplacementPayloads $replacementPayloads |
            Out-Null

        if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction Stop
        }

        return [PSCustomObject]@{
            Path = $resolvedPath
            Container = [string]$finalLayout.ContainerId
            Adapter = 'RenderKitRiff'
            Backend = 'Native'
            Fields = @($writtenFields)
            Chunks = @(
                $replacementPayloads.Keys |
                    ForEach-Object {
                        if ([string]$_ -ieq 'bext') { 'bext' } else { 'iXML' }
                    }
            )
            Verified = $true
            FileLength = [uint64]$finalLayout.FileLength
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
                throw "RIFF metadata write failed and backup restoration also failed. Original error: $($failure.Exception.Message). Restore error: $($_.Exception.Message). Backup: '$backupPath'."
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
