function Get-RenderKitMkvToolNixBundleRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return Join-Path `
        -Path $script:RenderKitModuleRoot `
        -ChildPath 'src/Resources/ThirdParty/MKVToolNix'
}

function Read-RenderKitMkvToolNixManifest {
    [CmdletBinding()]
    param()

    if ($script:RenderKitMkvToolNixManifest) {
        return $script:RenderKitMkvToolNixManifest
    }
    $path = Join-Path `
        -Path (Get-RenderKitMkvToolNixBundleRoot) `
        -ChildPath 'manifest.json'
    $manifest = Read-RenderKitJsonFile `
        -Path $path `
        -MaximumBytes 1048576 `
        -Validator {
            param($value)
            [string]$value.artifactType -eq 'ThirdPartyMetadataBundle' -and
                [string]$value.name -eq 'MKVToolNix' -and
                @($value.runtimeIdentifiers).Count -gt 0
        }
    $script:RenderKitMkvToolNixManifest = $manifest
    return $manifest
}

function Get-RenderKitMkvToolNixRuntimeIdentifier {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $os = if (
        [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    ) {
        'win'
    }
    else {
        try {
            if ([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
                    [Runtime.InteropServices.OSPlatform]::OSX)) {
                'osx'
            }
            elseif (
                [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
                    [Runtime.InteropServices.OSPlatform]::Linux)
            ) {
                'linux'
            }
            else {
                'unknown'
            }
        }
        catch {
            'unknown'
        }
    }
    $architecture = try {
        [Runtime.InteropServices.RuntimeInformation]::
            ProcessArchitecture.ToString()
    }
    catch {
        [string]$env:PROCESSOR_ARCHITECTURE
    }
    $arch = switch -Regex ($architecture) {
        'Arm64|Aarch64|ARM64' { 'arm64'; break }
        'X64|AMD64|x86_64' { 'x64'; break }
        'X86|i386|i686' { 'x86'; break }
        default { $architecture.ToLowerInvariant() }
    }
    return '{0}-{1}' -f $os, $arch
}

function Resolve-RenderKitMkvToolNixApplication {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$PathOrName
    )

    if ([string]::IsNullOrWhiteSpace($PathOrName)) {
        return $null
    }
    if (Test-Path -LiteralPath $PathOrName -PathType Leaf) {
        return [System.IO.Path]::GetFullPath($PathOrName)
    }
    $command = Get-Command `
        -Name $PathOrName `
        -CommandType Application `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) {
        return [string]$command.Source
    }
    return $null
}

function New-RenderKitMkvToolNixCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [AllowNull()]
        [string]$PropEditPath,

        [AllowNull()]
        [string]$ExtractPath,

        [string]$Version,

        [string]$Error
    )

    return [PSCustomObject]@{
        Source = $Source
        PropEditPath = $PropEditPath
        ExtractPath = $ExtractPath
        Version = $Version
        Available = (
            -not [string]::IsNullOrWhiteSpace($PropEditPath) -and
            -not [string]::IsNullOrWhiteSpace($ExtractPath) -and
            (Test-Path -LiteralPath $PropEditPath -PathType Leaf) -and
            (Test-Path -LiteralPath $ExtractPath -PathType Leaf) -and
            [string]::IsNullOrWhiteSpace($Error)
        )
        Error = $Error
    }
}

function Resolve-RenderKitMkvToolNixRuntime {
    [CmdletBinding()]
    param()

    $manifest = Read-RenderKitMkvToolNixManifest
    $runtimeIdentifier = Get-RenderKitMkvToolNixRuntimeIdentifier
    $candidates = New-Object System.Collections.Generic.List[object]

    $configuredRoot = [string]$env:RENDERKIT_MKVTOOLNIX_ROOT
    $configuredPropEdit = [string]$env:RENDERKIT_MKVPROPEDIT_PATH
    $configuredExtract = [string]$env:RENDERKIT_MKVEXTRACT_PATH
    if (-not [string]::IsNullOrWhiteSpace($configuredRoot)) {
        $propName = if ($runtimeIdentifier -like 'win-*') {
            'mkvpropedit.exe'
        }
        else {
            'mkvpropedit'
        }
        $extractName = if ($runtimeIdentifier -like 'win-*') {
            'mkvextract.exe'
        }
        else {
            'mkvextract'
        }
        $candidates.Add((New-RenderKitMkvToolNixCandidate `
            -Source 'EnvironmentRoot' `
            -PropEditPath (Resolve-RenderKitMkvToolNixApplication `
                -PathOrName (Join-Path $configuredRoot $propName)) `
            -ExtractPath (Resolve-RenderKitMkvToolNixApplication `
                -PathOrName (Join-Path $configuredRoot $extractName))))
    }
    if (-not [string]::IsNullOrWhiteSpace($configuredPropEdit) -or
        -not [string]::IsNullOrWhiteSpace($configuredExtract)) {
        $propPath = Resolve-RenderKitMkvToolNixApplication `
            -PathOrName $configuredPropEdit
        $extractPath = Resolve-RenderKitMkvToolNixApplication `
            -PathOrName $configuredExtract
        if ($propPath -and -not $extractPath) {
            $extractName = if ($runtimeIdentifier -like 'win-*') {
                'mkvextract.exe'
            }
            else {
                'mkvextract'
            }
            $extractPath = Resolve-RenderKitMkvToolNixApplication `
                -PathOrName (Join-Path `
                    -Path (Split-Path -Parent $propPath) `
                    -ChildPath $extractName)
        }
        if ($extractPath -and -not $propPath) {
            $propName = if ($runtimeIdentifier -like 'win-*') {
                'mkvpropedit.exe'
            }
            else {
                'mkvpropedit'
            }
            $propPath = Resolve-RenderKitMkvToolNixApplication `
                -PathOrName (Join-Path `
                    -Path (Split-Path -Parent $extractPath) `
                    -ChildPath $propName)
        }
        $candidates.Add((New-RenderKitMkvToolNixCandidate `
            -Source 'Environment' `
            -PropEditPath $propPath `
            -ExtractPath $extractPath))
    }

    $runtime = @(
        $manifest.runtimeIdentifiers |
            Where-Object {
                [string]$_.rid -ieq $runtimeIdentifier
            } |
            Select-Object -First 1
    )
    if ($runtime -and [bool]$runtime.bundled) {
        $root = Get-RenderKitMkvToolNixBundleRoot
        $propPath = Join-Path `
            -Path $root `
            -ChildPath ([string]$runtime.propEditRelativePath)
        $extractPath = Join-Path `
            -Path $root `
            -ChildPath ([string]$runtime.extractRelativePath)
        $error = $null
        foreach ($check in @(
            [PSCustomObject]@{
                Path = $propPath
                Expected = [string]$runtime.propEditSha256
                Name = 'mkvpropedit'
            },
            [PSCustomObject]@{
                Path = $extractPath
                Expected = [string]$runtime.extractSha256
                Name = 'mkvextract'
            }
        )) {
            if (-not (Test-Path -LiteralPath $check.Path -PathType Leaf)) {
                $error = "Bundled $($check.Name) is missing."
                break
            }
            $hash = (
                Get-FileHash `
                    -LiteralPath $check.Path `
                    -Algorithm SHA256
            ).Hash
            if ($hash -ne $check.Expected) {
                $error = "Bundled $($check.Name) failed its SHA-256 check."
                break
            }
        }
        $candidates.Add((New-RenderKitMkvToolNixCandidate `
            -Source 'Bundled' `
            -PropEditPath $propPath `
            -ExtractPath $extractPath `
            -Version ([string]$manifest.componentVersion) `
            -Error $error))
    }

    $systemProp = Resolve-RenderKitMkvToolNixApplication `
        -PathOrName 'mkvpropedit'
    $systemExtract = Resolve-RenderKitMkvToolNixApplication `
        -PathOrName 'mkvextract'
    if ($systemProp -or $systemExtract) {
        $candidates.Add((New-RenderKitMkvToolNixCandidate `
            -Source 'System' `
            -PropEditPath $systemProp `
            -ExtractPath $systemExtract))
    }

    $selected = @(
        $candidates |
            Where-Object { [bool]$_.Available } |
            Select-Object -First 1
    )
    return [PSCustomObject]@{
        Available = [bool]$selected
        Source = if ($selected) {
            [string]$selected.Source
        }
        else {
            $null
        }
        PropEditPath = if ($selected) {
            [string]$selected.PropEditPath
        }
        else {
            $null
        }
        ExtractPath = if ($selected) {
            [string]$selected.ExtractPath
        }
        else {
            $null
        }
        Version = if ($selected) {
            [string]$selected.Version
        }
        else {
            [string]$manifest.componentVersion
        }
        RuntimeIdentifier = $runtimeIdentifier
        Candidates = @($candidates.ToArray())
        Error = if ($selected) {
            $null
        }
        else {
            'No complete mkvpropedit and mkvextract runtime pair is available.'
        }
    }
}

function Test-RenderKitMkvToolNixPath {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return @('.mkv', '.mk3d', '.mka', '.mks', '.webm') -contains
        [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
}

function Get-RenderKitMkvToolNixWriteDefinitions {
    [CmdletBinding()]
    param(
        [string]$Field
    )

    $map = Read-RenderKitAudioContainerMetadataProfileMap `
        -Profile Matroska
    if ([string]$map.writeCapability.adapter -ne 'MkvToolNix') {
        return @()
    }
    return @(
        $map.writeFields |
            Where-Object {
                [string]::IsNullOrWhiteSpace($Field) -or
                    [string]$_.field -ieq $Field
            } |
            ForEach-Object {
                [PSCustomObject]@{
                    Profile = 'Matroska'
                    Field = [string]$_.field
                    Target = [string]$_.target
                    ValueType = [string]$_.valueType
                }
            }
    )
}

function Get-RenderKitMkvToolNixEmbeddedMetadataWriteCapability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Field,

        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-RenderKitMkvToolNixPath -Path $Path)) {
        return $null
    }
    $definitions = @(
        Get-RenderKitMkvToolNixWriteDefinitions -Field $Field
    )
    if ($definitions.Count -eq 0) {
        return $null
    }
    return [PSCustomObject]@{
        field = $Field
        adapter = 'MkvToolNix'
        tags = @($definitions | ForEach-Object {
            'Matroska:{0}' -f $_.Target
        })
        mediaKinds = @('Audio', 'Video')
        fieldType = $null
        standards = @('Matroska')
        writeMode = 'AtomicMkvPropEdit'
        structureMembers = $null
        controlledVocabulary = $null
    }
}

function Invoke-RenderKitMkvToolNixApplication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $Path @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        throw "$Name exited with code $exitCode`: $(@($output) -join "`n")"
    }
    return [PSCustomObject]@{
        ExitCode = $exitCode
        Output = @($output | ForEach-Object { [string]$_ })
    }
}

function New-RenderKitMkvToolNixXmlDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Tags', 'Chapters')]
        [string]$RootName
    )

    $document = [Xml.XmlDocument]::new()
    $document.PreserveWhitespace = $false
    $document.XmlResolver = $null
    $declaration = $document.CreateXmlDeclaration(
        '1.0',
        'UTF-8',
        $null
    )
    [void]$document.AppendChild($declaration)
    [void]$document.AppendChild($document.CreateElement($RootName))
    return $document
}

function Read-RenderKitMkvToolNixXmlDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateSet('Tags', 'Chapters')]
        [string]$RootName
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or
        (Get-Item -LiteralPath $Path).Length -eq 0) {
        return New-RenderKitMkvToolNixXmlDocument -RootName $RootName
    }
    $settings = [Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
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

function Save-RenderKitMkvToolNixXmlDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Xml.XmlDocument]$Document,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $settings = [Xml.XmlWriterSettings]::new()
    $settings.Encoding = [Text.UTF8Encoding]::new($false)
    $settings.Indent = $true
    $settings.NewLineChars = "`n"
    $settings.NewLineHandling = [Xml.NewLineHandling]::Replace
    $writer = [Xml.XmlWriter]::Create($Path, $settings)
    try {
        $Document.Save($writer)
    }
    finally {
        $writer.Dispose()
    }
}

function Test-RenderKitMkvToolNixGlobalTagElement {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [Xml.XmlElement]$Tag
    )

    $targets = @(
        $Tag.ChildNodes |
            Where-Object {
                $_ -is [Xml.XmlElement] -and
                    [string]$_.LocalName -eq 'Targets'
            } |
            Select-Object -First 1
    )
    if (-not $targets) {
        return $true
    }
    foreach ($targetName in @(
        'TrackUID',
        'EditionUID',
        'ChapterUID',
        'AttachmentUID'
    )) {
        if ($targets[0].SelectSingleNode("./$targetName")) {
            return $false
        }
    }
    return $true
}

function Get-RenderKitMkvToolNixSimpleTagName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [Xml.XmlElement]$Simple
    )

    $element = $Simple.SelectSingleNode('./Name')
    if (-not $element) {
        return $null
    }
    return ([string]$element.InnerText).Trim().ToUpperInvariant()
}

function Get-RenderKitMkvToolNixSimpleTagValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Xml.XmlDocument]$Document
    )

    $values = [ordered]@{}
    foreach ($tag in @($Document.DocumentElement.ChildNodes)) {
        if (-not ($tag -is [Xml.XmlElement]) -or
            [string]$tag.LocalName -ne 'Tag' -or
            -not (Test-RenderKitMkvToolNixGlobalTagElement -Tag $tag)) {
            continue
        }
        foreach ($simple in @($tag.ChildNodes)) {
            if (-not ($simple -is [Xml.XmlElement]) -or
                [string]$simple.LocalName -ne 'Simple') {
                continue
            }
            $name = Get-RenderKitMkvToolNixSimpleTagName -Simple $simple
            $stringElement = $simple.SelectSingleNode('./String')
            if ([string]::IsNullOrWhiteSpace($name) -or
                -not $stringElement) {
                continue
            }
            if (-not $values.Contains($name)) {
                $values[$name] = New-Object `
                    System.Collections.Generic.List[string]
            }
            $values[$name].Add([string]$stringElement.InnerText)
        }
    }
    return $values
}

function New-RenderKitMkvToolNixGlobalTagsDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Xml.XmlDocument]$Source
    )

    $document = New-RenderKitMkvToolNixXmlDocument -RootName Tags
    foreach ($tag in @($Source.DocumentElement.ChildNodes)) {
        if ($tag -is [Xml.XmlElement] -and
            [string]$tag.LocalName -eq 'Tag' -and
            (Test-RenderKitMkvToolNixGlobalTagElement -Tag $tag)) {
            [void]$document.DocumentElement.AppendChild(
                $document.ImportNode($tag, $true)
            )
        }
    }
    return $document
}

function Get-RenderKitMkvToolNixMetadataValue {
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

function ConvertTo-RenderKitMkvToolNixStringValues {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return @()
    }
    $items = if ($Value -is [Collections.IEnumerable] -and
        -not ($Value -is [string]) -and
        -not ($Value -is [Collections.IDictionary])) {
        @($Value)
    }
    else {
        @($Value)
    }
    return @(
        $items |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_)
            }
    )
}

function Set-RenderKitMkvToolNixGlobalTag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Xml.XmlDocument]$Document,

        [Parameter(Mandatory)]
        [string]$Name,

        [AllowNull()]
        [object]$Value
    )

    $upperName = $Name.ToUpperInvariant()
    $globalTags = @(
        $Document.DocumentElement.ChildNodes |
            Where-Object {
                $_ -is [Xml.XmlElement] -and
                    [string]$_.LocalName -eq 'Tag' -and
                    (Test-RenderKitMkvToolNixGlobalTagElement -Tag $_)
            }
    )
    foreach ($tag in $globalTags) {
        foreach ($simple in @($tag.ChildNodes)) {
            if ($simple -is [Xml.XmlElement] -and
                [string]$simple.LocalName -eq 'Simple' -and
                (Get-RenderKitMkvToolNixSimpleTagName -Simple $simple) -eq
                    $upperName) {
                [void]$tag.RemoveChild($simple)
            }
        }
    }

    $values = @(ConvertTo-RenderKitMkvToolNixStringValues -Value $Value)
    if ($values.Count -eq 0) {
        return
    }
    $targetTag = @($globalTags | Select-Object -First 1)
    if (-not $targetTag) {
        $tagElement = $Document.CreateElement('Tag')
        [void]$tagElement.AppendChild(
            $Document.CreateElement('Targets')
        )
        [void]$Document.DocumentElement.AppendChild($tagElement)
        $targetTag = @($tagElement)
    }
    foreach ($text in $values) {
        $simple = $Document.CreateElement('Simple')
        $nameElement = $Document.CreateElement('Name')
        $nameElement.InnerText = $upperName
        [void]$simple.AppendChild($nameElement)
        $stringElement = $Document.CreateElement('String')
        $stringElement.InnerText = $text
        [void]$simple.AppendChild($stringElement)
        [void]$targetTag[0].AppendChild($simple)
    }
}

function Get-RenderKitMkvToolNixObjectMember {
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
        if ($InputObject -is [Collections.IDictionary]) {
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

function ConvertTo-RenderKitMkvToolNixMilliseconds {
    [CmdletBinding()]
    [OutputType([int64])]
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Field
    )

    if ($Value -is [timespan]) {
        $milliseconds = $Value.TotalMilliseconds
    }
    elseif ([string]$Value -match
        '^\d{1,9}:\d{2}:\d{2}(?:\.\d{1,9})?$') {
        $parts = ([string]$Value).Split(':')
        $hours = [int64]$parts[0]
        $minutes = [int64]$parts[1]
        $seconds = [decimal]::Parse(
            $parts[2],
            [Globalization.CultureInfo]::InvariantCulture
        )
        $milliseconds = [decimal](
            (($hours * 3600) + ($minutes * 60)) * 1000
        ) + ($seconds * 1000)
    }
    else {
        $milliseconds = [decimal]0
        if (-not [decimal]::TryParse(
                ([string]$Value).Trim(),
                [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture,
                [ref]$milliseconds)) {
            throw "Matroska field '$Field' must be milliseconds or a timestamp."
        }
    }
    if ($milliseconds -lt 0 -or
        $milliseconds -gt [int64]::MaxValue) {
        throw "Matroska field '$Field' is outside the supported range."
    }
    return [int64][Math]::Round(
        [decimal]$milliseconds,
        0,
        [MidpointRounding]::AwayFromZero
    )
}

function ConvertTo-RenderKitMkvToolNixTimestamp {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [int64]$Milliseconds
    )

    $hours = [Math]::Floor($Milliseconds / 3600000)
    $remainder = $Milliseconds % 3600000
    $minutes = [Math]::Floor($remainder / 60000)
    $remainder = $remainder % 60000
    $seconds = [Math]::Floor($remainder / 1000)
    $millis = $remainder % 1000
    return '{0:D2}:{1:D2}:{2:D2}.{3:D3}000000' -f
        [int64]$hours,
        [int64]$minutes,
        [int64]$seconds,
        [int64]$millis
}

function Add-RenderKitMkvToolNixChapterAtom {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Xml.XmlDocument]$Document,

        [Parameter(Mandatory)]
        [Xml.XmlElement]$Parent,

        [Parameter(Mandatory)]
        [object]$Chapter
    )

    $startValue = Get-RenderKitMkvToolNixObjectMember `
        -InputObject $Chapter `
        -Name @('StartMilliseconds', 'Start')
    $endValue = Get-RenderKitMkvToolNixObjectMember `
        -InputObject $Chapter `
        -Name @('EndMilliseconds', 'End')
    $title = Get-RenderKitMkvToolNixObjectMember `
        -InputObject $Chapter `
        -Name @('Title')
    $language = Get-RenderKitMkvToolNixObjectMember `
        -InputObject $Chapter `
        -Name @('Language')
    $url = Get-RenderKitMkvToolNixObjectMember `
        -InputObject $Chapter `
        -Name @('Url', 'URL')
    if ($null -eq $startValue) {
        throw 'Each Matroska chapter requires a start timestamp.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$title)) {
        throw 'Each Matroska chapter requires a title.'
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$url)) {
        throw 'Canonical Matroska chapters do not support URL values.'
    }
    $start = ConvertTo-RenderKitMkvToolNixMilliseconds `
        -Value $startValue `
        -Field 'Chapter.Start'
    $end = if ($null -ne $endValue -and
        -not [string]::IsNullOrWhiteSpace([string]$endValue)) {
        ConvertTo-RenderKitMkvToolNixMilliseconds `
            -Value $endValue `
            -Field 'Chapter.End'
    }
    else {
        $null
    }
    if ($null -ne $end -and $end -lt $start) {
        throw 'A Matroska chapter cannot end before it starts.'
    }

    $atom = $Document.CreateElement('ChapterAtom')
    [void]$Parent.AppendChild($atom)
    $startElement = $Document.CreateElement('ChapterTimeStart')
    $startElement.InnerText = ConvertTo-RenderKitMkvToolNixTimestamp `
        -Milliseconds $start
    [void]$atom.AppendChild($startElement)
    if ($null -ne $end) {
        $endElement = $Document.CreateElement('ChapterTimeEnd')
        $endElement.InnerText = ConvertTo-RenderKitMkvToolNixTimestamp `
            -Milliseconds $end
        [void]$atom.AppendChild($endElement)
    }
    $uid = Get-RenderKitMkvToolNixObjectMember `
        -InputObject $Chapter `
        -Name @('Uid', 'UID')
    if ($null -ne $uid -and
        -not [string]::IsNullOrWhiteSpace([string]$uid)) {
        $parsedUid = [uint64]0
        if (-not [uint64]::TryParse([string]$uid, [ref]$parsedUid) -or
            $parsedUid -eq 0) {
            throw "Matroska chapter UID '$uid' is invalid."
        }
        $uidElement = $Document.CreateElement('ChapterUID')
        $uidElement.InnerText = [string]$parsedUid
        [void]$atom.AppendChild($uidElement)
    }
    foreach ($flag in @(
        [PSCustomObject]@{
            Member = @('Hidden')
            Element = 'ChapterFlagHidden'
        },
        [PSCustomObject]@{
            Member = @('Enabled')
            Element = 'ChapterFlagEnabled'
        }
    )) {
        $flagValue = Get-RenderKitMkvToolNixObjectMember `
            -InputObject $Chapter `
            -Name $flag.Member
        if ($null -ne $flagValue) {
            $bool = if ($flagValue -is [bool]) {
                [bool]$flagValue
            }
            elseif ([string]$flagValue -match
                '^(?i:true|yes|1)$') {
                $true
            }
            elseif ([string]$flagValue -match
                '^(?i:false|no|0)$') {
                $false
            }
            else {
                throw "Matroska chapter flag '$($flag.Element)' is invalid."
            }
            $flagElement = $Document.CreateElement($flag.Element)
            $flagElement.InnerText = if ($bool) { '1' } else { '0' }
            [void]$atom.AppendChild($flagElement)
        }
    }

    $display = $Document.CreateElement('ChapterDisplay')
    $titleElement = $Document.CreateElement('ChapterString')
    $titleElement.InnerText = [string]$title
    [void]$display.AppendChild($titleElement)
    if (-not [string]::IsNullOrWhiteSpace([string]$language)) {
        $languageElement = $Document.CreateElement('ChapLanguageIETF')
        $languageElement.InnerText = ([string]$language).Trim()
        [void]$display.AppendChild($languageElement)
    }
    [void]$atom.AppendChild($display)

    $children = Get-RenderKitMkvToolNixObjectMember `
        -InputObject $Chapter `
        -Name @('Children')
    if ($children) {
        foreach ($child in @($children)) {
            Add-RenderKitMkvToolNixChapterAtom `
                -Document $Document `
                -Parent $atom `
                -Chapter $child
        }
    }
}

function New-RenderKitMkvToolNixChaptersDocument {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    $document = New-RenderKitMkvToolNixXmlDocument -RootName Chapters
    $items = if ($Value -is [Collections.IEnumerable] -and
        -not ($Value -is [string]) -and
        -not ($Value -is [Collections.IDictionary])) {
        @($Value)
    }
    elseif ($null -eq $Value) {
        @()
    }
    else {
        @($Value)
    }
    if ($items.Count -eq 0) {
        return $document
    }
    $edition = $document.CreateElement('EditionEntry')
    [void]$document.DocumentElement.AppendChild($edition)
    foreach ($item in $items) {
        Add-RenderKitMkvToolNixChapterAtom `
            -Document $document `
            -Parent $edition `
            -Chapter $item
    }
    return $document
}

function ConvertFrom-RenderKitMkvToolNixChapterAtom {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Xml.XmlElement]$Atom,

        [Parameter(Mandatory)]
        [int]$EditionIndex,

        [int]$Depth = 0
    )

    $startText = [string]$Atom.SelectSingleNode(
        './ChapterTimeStart'
    ).InnerText
    $endElement = $Atom.SelectSingleNode('./ChapterTimeEnd')
    $uidElement = $Atom.SelectSingleNode('./ChapterUID')
    $hiddenElement = $Atom.SelectSingleNode('./ChapterFlagHidden')
    $enabledElement = $Atom.SelectSingleNode('./ChapterFlagEnabled')
    $displays = @(
        $Atom.SelectNodes('./ChapterDisplay') |
            ForEach-Object {
                $titleElement = $_.SelectSingleNode('./ChapterString')
                $languageElement = $_.SelectSingleNode(
                    './ChapLanguageIETF'
                )
                if (-not $languageElement) {
                    $languageElement = $_.SelectSingleNode(
                        './ChapterLanguage'
                    )
                }
                [PSCustomObject][ordered]@{
                    Title = if ($titleElement) {
                        [string]$titleElement.InnerText
                    }
                    else {
                        $null
                    }
                    Language = if ($languageElement) {
                        [string]$languageElement.InnerText
                    }
                    else {
                        $null
                    }
                }
            }
    )
    $firstDisplay = @($displays | Select-Object -First 1)
    $children = @(
        $Atom.ChildNodes |
            Where-Object {
                $_ -is [Xml.XmlElement] -and
                    [string]$_.LocalName -eq 'ChapterAtom'
            } |
            ForEach-Object {
                ConvertFrom-RenderKitMkvToolNixChapterAtom `
                    -Atom $_ `
                    -EditionIndex $EditionIndex `
                    -Depth ($Depth + 1)
            }
    )
    return [PSCustomObject][ordered]@{
        EditionIndex = $EditionIndex
        Depth = $Depth
        Uid = if ($uidElement) {
            [string]$uidElement.InnerText
        }
        else {
            $null
        }
        StartMilliseconds = ConvertTo-RenderKitMkvToolNixMilliseconds `
            -Value $startText `
            -Field 'ChapterTimeStart'
        EndMilliseconds = if ($endElement) {
            ConvertTo-RenderKitMkvToolNixMilliseconds `
                -Value ([string]$endElement.InnerText) `
                -Field 'ChapterTimeEnd'
        }
        else {
            $null
        }
        Title = if ($firstDisplay) {
            [string]$firstDisplay[0].Title
        }
        else {
            $null
        }
        Language = if ($firstDisplay) {
            [string]$firstDisplay[0].Language
        }
        else {
            $null
        }
        Hidden = if ($hiddenElement) {
            [string]$hiddenElement.InnerText -eq '1'
        }
        else {
            $false
        }
        Enabled = if ($enabledElement) {
            [string]$enabledElement.InnerText -ne '0'
        }
        else {
            $true
        }
        Displays = @($displays)
        Children = @($children)
    }
}

function Get-RenderKitMkvToolNixChapterCount {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [AllowNull()]
        [object[]]$Chapter
    )

    $count = 0
    foreach ($item in @($Chapter)) {
        $count++
        $count += Get-RenderKitMkvToolNixChapterCount `
            -Chapter @($item.Children)
    }
    return $count
}

function ConvertFrom-RenderKitMkvToolNixMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Xml.XmlDocument]$Tags,

        [Parameter(Mandatory)]
        [Xml.XmlDocument]$Chapters
    )

    $fields = [ordered]@{}
    $tagMap = [ordered]@{
        ALBUM = 'Album'
        DISCNUMBER = 'AudioDiscNumber'
        DISCTOTAL = 'AudioDiscTotal'
        TRACKNUMBER = 'AudioTrackNumber'
        TRACKTOTAL = 'AudioTrackTotal'
        COMPOSER = 'Composer'
        CONDUCTOR = 'Conductor'
        DIRECTOR = 'Director'
        GENRE = 'Genre'
        LABEL = 'Label'
        PRODUCER = 'Producer'
        PUBLISHER = 'Publisher'
        REEL_NAME = 'ReelName'
        DATE_RELEASED = 'ReleaseDate'
        SUBTITLE = 'Subtitle'
        SYNOPSIS = 'Synopsis'
    }
    $tagValues = Get-RenderKitMkvToolNixSimpleTagValues -Document $Tags
    foreach ($entry in $tagMap.GetEnumerator()) {
        if (-not $tagValues.Contains([string]$entry.Key)) {
            continue
        }
        $values = @($tagValues[[string]$entry.Key].ToArray())
        $value = if ($values.Count -eq 1) {
            $values[0]
        }
        else {
            @($values)
        }
        if ([string]$entry.Key -in @(
                'DISCNUMBER',
                'DISCTOTAL',
                'TRACKNUMBER',
                'TRACKTOTAL'
            ) -and $values.Count -eq 1) {
            $value = ConvertTo-RenderKitMetadataInt64 -Value $values[0]
        }
        elseif ([string]$entry.Key -eq 'DATE_RELEASED' -and
            $values.Count -eq 1) {
            $value =
                ConvertTo-RenderKitAudioContainerMetadataFieldValue `
                    -Value $values[0] `
                    -Converter Date
        }
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name ([string]$entry.Value) `
            -Value $value
    }

    $chapterItems = New-Object System.Collections.Generic.List[object]
    $editionIndex = 0
    foreach ($edition in @(
        $Chapters.DocumentElement.ChildNodes |
            Where-Object {
                $_ -is [Xml.XmlElement] -and
                    [string]$_.LocalName -eq 'EditionEntry'
            }
    )) {
        $editionIndex++
        foreach ($atom in @(
            $edition.ChildNodes |
                Where-Object {
                    $_ -is [Xml.XmlElement] -and
                        [string]$_.LocalName -eq 'ChapterAtom'
                }
        )) {
            $chapterItems.Add(
                (ConvertFrom-RenderKitMkvToolNixChapterAtom `
                    -Atom $atom `
                    -EditionIndex $editionIndex)
            )
        }
    }
    if ($chapterItems.Count -gt 0) {
        foreach ($field in @('Chapters', 'AudioChapters')) {
            Set-RenderKitMetadataFieldValue `
                -Fields $fields `
                -Name $field `
                -Value @($chapterItems.ToArray())
        }
        Set-RenderKitMetadataFieldValue `
            -Fields $fields `
            -Name 'ChapterCount' `
            -Value (Get-RenderKitMkvToolNixChapterCount `
                -Chapter @($chapterItems.ToArray()))
    }
    return $fields
}

function Read-RenderKitMkvToolNixEmbeddedMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $resolvedPath = (
        Resolve-Path -LiteralPath $Path -ErrorAction Stop
    ).ProviderPath
    if (-not (Test-RenderKitMkvToolNixPath -Path $resolvedPath)) {
        throw 'MKVToolNix metadata reads require a Matroska or WebM file.'
    }
    $runtime = Resolve-RenderKitMkvToolNixRuntime
    if (-not [bool]$runtime.Available) {
        throw [string]$runtime.Error
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
            -Arguments @(
                $resolvedPath,
                'tags',
                $tagsPath
            ) |
            Out-Null
        Invoke-RenderKitMkvToolNixApplication `
            -Path ([string]$runtime.ExtractPath) `
            -Name 'mkvextract chapters' `
            -Arguments @(
                $resolvedPath,
                'chapters',
                $chaptersPath
            ) |
            Out-Null
        $tags = Read-RenderKitMkvToolNixXmlDocument `
            -Path $tagsPath `
            -RootName Tags
        $chapters = Read-RenderKitMkvToolNixXmlDocument `
            -Path $chaptersPath `
            -RootName Chapters
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
                            (Test-RenderKitMkvToolNixGlobalTagElement `
                                -Tag $_)
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

function ConvertTo-RenderKitMkvToolNixBoolean {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Field
    )

    if ($Value -is [bool]) {
        return $(if ([bool]$Value) { '1' } else { '0' })
    }
    $text = ([string]$Value).Trim().ToLowerInvariant()
    if ($text -in @('1', 'true', 'yes', 'on')) {
        return '1'
    }
    if ($text -in @('0', 'false', 'no', 'off')) {
        return '0'
    }
    throw "Matroska field '$Field' must be boolean."
}

function ConvertTo-RenderKitMkvToolNixStereoMode {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$Value
    )

    switch (([string]$Value).Trim().ToLowerInvariant()) {
        'mono' { return '0' }
        'leftright' { return '1' }
        'topbottom' { return '3' }
        'anaglyph' { return '10' }
        'separatestreams' {
            throw 'StereoMode SeparateStreams requires Matroska TrackOperation metadata that the canonical field does not describe.'
        }
        'unknown' {
            throw 'StereoMode Unknown cannot be written without inventing a Matroska stereo layout.'
        }
        default {
            throw "StereoMode '$Value' is not supported for Matroska writes."
        }
    }
}

function Resolve-RenderKitMkvToolNixChapterValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Metadata,

        [ref]$Found
    )

    $selected = $null
    $selectedField = $null
    $Found.Value = $false
    foreach ($field in @('Chapters', 'AudioChapters')) {
        $hasValue = $false
        $value = Get-RenderKitMkvToolNixMetadataValue `
            -Metadata $Metadata `
            -Field $field `
            -Found ([ref]$hasValue)
        if (-not $hasValue) {
            continue
        }
        if (-not $Found.Value) {
            $Found.Value = $true
            $selected = $value
            $selectedField = $field
            continue
        }
        $selectedJson = $selected | ConvertTo-Json -Depth 50 -Compress
        $valueJson = $value | ConvertTo-Json -Depth 50 -Compress
        if ([string]$selectedJson -ne [string]$valueJson) {
            throw "Conflicting values for Matroska chapters were supplied by '$selectedField' and '$field'."
        }
    }
    return $selected
}

function New-RenderKitMkvToolNixWriteArtifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Metadata,

        [Parameter(Mandatory)]
        [object]$Runtime,

        [Parameter(Mandatory)]
        [string]$TemporaryRoot
    )

    $arguments = New-Object System.Collections.Generic.List[string]
    $arguments.Add('--abort-on-warnings')
    $arguments.Add('--normalize-language-ietf')
    $arguments.Add('canonical')
    $definitions = @(
        Get-RenderKitMkvToolNixWriteDefinitions
    )
    $definitionByField = @{}
    foreach ($definition in $definitions) {
        $definitionByField[[string]$definition.Field] = $definition
    }

    $tagDefinitions = @(
        $definitions |
            Where-Object { [string]$_.Target -like 'GlobalTag:*' }
    )
    $hasTagChanges = $false
    $tagsPath = Join-Path $TemporaryRoot 'existing-tags.xml'
    foreach ($definition in $tagDefinitions) {
        $found = $false
        Get-RenderKitMkvToolNixMetadataValue `
            -Metadata $Metadata `
            -Field ([string]$definition.Field) `
            -Found ([ref]$found) |
            Out-Null
        if ($found) {
            $hasTagChanges = $true
            break
        }
    }
    if ($hasTagChanges) {
        Invoke-RenderKitMkvToolNixApplication `
            -Path ([string]$Runtime.ExtractPath) `
            -Name 'mkvextract tags' `
            -Arguments @(
                $Path,
                'tags',
                $tagsPath
            ) |
            Out-Null
        $sourceTags = Read-RenderKitMkvToolNixXmlDocument `
            -Path $tagsPath `
            -RootName Tags
        $globalTags = New-RenderKitMkvToolNixGlobalTagsDocument `
            -Source $sourceTags
        foreach ($definition in $tagDefinitions) {
            $found = $false
            $value = Get-RenderKitMkvToolNixMetadataValue `
                -Metadata $Metadata `
                -Field ([string]$definition.Field) `
                -Found ([ref]$found)
            if (-not $found) {
                continue
            }
            if ([string]$definition.ValueType -eq 'DateText') {
                $value = if ($value -is [datetime]) {
                    $value.ToString(
                        'yyyy-MM-dd',
                        [Globalization.CultureInfo]::InvariantCulture
                    )
                }
                else {
                    [string]$value
                }
            }
            Set-RenderKitMkvToolNixGlobalTag `
                -Document $globalTags `
                -Name (
                    ([string]$definition.Target).Substring(
                        'GlobalTag:'.Length
                    )
                ) `
                -Value $value
        }
        $writeTagsPath = Join-Path $TemporaryRoot 'global-tags.xml'
        Save-RenderKitMkvToolNixXmlDocument `
            -Document $globalTags `
            -Path $writeTagsPath
        $arguments.Add('--tags')
        $arguments.Add("global:$writeTagsPath")
    }

    foreach ($trackGroup in @(
        [PSCustomObject]@{
            Selector = 'track:a1'
            Fields = [ordered]@{
                AudioDefaultStream = 'flag-default'
                AudioForcedStream = 'flag-forced'
                AudioLanguage = 'language'
                AudioTitle = 'name'
            }
        },
        [PSCustomObject]@{
            Selector = 'track:v1'
            Fields = [ordered]@{
                VideoDefaultStream = 'flag-default'
                VideoForcedStream = 'flag-forced'
                VideoLanguage = 'language'
                VideoTrackTitle = 'name'
                StereoMode = 'stereo-mode'
            }
        }
    )) {
        $changes = New-Object System.Collections.Generic.List[object]
        foreach ($entry in $trackGroup.Fields.GetEnumerator()) {
            $found = $false
            $value = Get-RenderKitMkvToolNixMetadataValue `
                -Metadata $Metadata `
                -Field ([string]$entry.Key) `
                -Found ([ref]$found)
            if (-not $found) {
                continue
            }
            $targetValue = if ([string]$entry.Value -in @(
                    'flag-default',
                    'flag-forced'
                )) {
                ConvertTo-RenderKitMkvToolNixBoolean `
                    -Value $value `
                    -Field ([string]$entry.Key)
            }
            elseif ([string]$entry.Value -eq 'stereo-mode') {
                ConvertTo-RenderKitMkvToolNixStereoMode -Value $value
            }
            elseif ([string]$entry.Value -eq 'language' -and
                [string]::IsNullOrWhiteSpace([string]$value)) {
                'und'
            }
            else {
                [string]$value
            }
            $changes.Add([PSCustomObject]@{
                Property = [string]$entry.Value
                Value = $targetValue
                Delete = (
                    [string]::IsNullOrWhiteSpace([string]$targetValue) -and
                    [string]$entry.Value -eq 'name'
                )
            })
        }
        if ($changes.Count -eq 0) {
            continue
        }
        $arguments.Add('--edit')
        $arguments.Add([string]$trackGroup.Selector)
        foreach ($change in $changes) {
            if ([bool]$change.Delete) {
                $arguments.Add('--delete')
                $arguments.Add([string]$change.Property)
            }
            else {
                $arguments.Add('--set')
                $arguments.Add((
                    '{0}={1}' -f
                        ([string]$change.Property),
                        ([string]$change.Value)
                ))
            }
        }
    }

    $hasChapters = $false
    $chapterValue = Resolve-RenderKitMkvToolNixChapterValue `
        -Metadata $Metadata `
        -Found ([ref]$hasChapters)
    if ($hasChapters) {
        $chapterDocument =
            New-RenderKitMkvToolNixChaptersDocument `
                -Value $chapterValue
        $chapterPath = Join-Path $TemporaryRoot 'chapters.xml'
        Save-RenderKitMkvToolNixXmlDocument `
            -Document $chapterDocument `
            -Path $chapterPath
        $arguments.Add('--chapters')
        $arguments.Add($chapterPath)
    }

    if ($arguments.Count -eq 3) {
        throw 'No MKVToolNix edit arguments were generated.'
    }
    return [PSCustomObject]@{
        Arguments = @($arguments.ToArray())
        HasTagChanges = $hasTagChanges
        HasChapterChanges = $hasChapters
    }
}

function Test-RenderKitMkvToolNixWrite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Metadata
    )

    $read = Read-RenderKitFileMetadata -Path $Path
    $definitions = @(
        Get-RenderKitMkvToolNixWriteDefinitions
    )
    $byField = @{}
    foreach ($definition in $definitions) {
        $byField[[string]$definition.Field] = $definition
    }
    foreach ($key in @($Metadata.Keys)) {
        $field = [string]$key
        if (-not $byField.ContainsKey($field)) {
            continue
        }
        if (-not $read.Fields.PSObject.Properties[$field]) {
            if (Test-RenderKitMetadataValueIsEmpty -Value $Metadata[$key]) {
                continue
            }
            throw "Matroska verification did not read field '$field' back."
        }
        $definition = $byField[$field]
        if ([string]$definition.ValueType -eq 'ChapterList') {
            $expected = @($Metadata[$key])
            $actual = @($read.Fields.$field)
            if ($expected.Count -ne $actual.Count) {
                throw "Matroska chapter verification failed for '$field'."
            }
            for ($index = 0; $index -lt $expected.Count; $index++) {
                foreach ($member in @(
                    [PSCustomObject]@{
                        Expected = @('StartMilliseconds', 'Start')
                        Actual = 'StartMilliseconds'
                        Timestamp = $true
                    },
                    [PSCustomObject]@{
                        Expected = @('EndMilliseconds', 'End')
                        Actual = 'EndMilliseconds'
                        Timestamp = $true
                    },
                    [PSCustomObject]@{
                        Expected = @('Title')
                        Actual = 'Title'
                        Timestamp = $false
                    },
                    [PSCustomObject]@{
                        Expected = @('Language')
                        Actual = 'Language'
                        Timestamp = $false
                    }
                )) {
                    $expectedValue = Get-RenderKitMkvToolNixObjectMember `
                        -InputObject $expected[$index] `
                        -Name $member.Expected
                    if ($null -eq $expectedValue) {
                        continue
                    }
                    $actualValue = Get-RenderKitMkvToolNixObjectMember `
                        -InputObject $actual[$index] `
                        -Name @([string]$member.Actual)
                    if ([bool]$member.Timestamp) {
                        $expectedValue =
                            ConvertTo-RenderKitMkvToolNixMilliseconds `
                                -Value $expectedValue `
                                -Field $field
                    }
                    if ([string]$expectedValue -ne
                        [string]$actualValue) {
                        throw "Matroska chapter verification failed for '$field'."
                    }
                }
            }
            continue
        }
        $expectedValue = $Metadata[$key]
        $actualValue = $read.Fields.$field
        if ([string]$definition.ValueType -eq 'Boolean') {
            $expectedValue =
                (ConvertTo-RenderKitMkvToolNixBoolean `
                    -Value $expectedValue `
                    -Field $field) -eq '1'
            $actualValue = [bool]$actualValue
        }
        elseif ([string]$definition.ValueType -eq 'UInt32') {
            $expectedValue = [int64]$expectedValue
            $actualValue = [int64]$actualValue
        }
        elseif ([string]$definition.ValueType -eq 'DateText' -and
            $expectedValue -is [datetime]) {
            $expectedValue = $expectedValue.ToString('yyyy-MM-dd')
        }
        if ([string]$expectedValue -ne [string]$actualValue) {
            throw "Matroska verification failed for field '$field'."
        }
    }
    return $read
}

function Invoke-RenderKitMkvToolNixMetadataWrite {
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
    if (-not (Test-RenderKitMkvToolNixPath -Path $resolvedPath)) {
        throw 'MKVToolNix writes require a Matroska or WebM file.'
    }
    $writtenFields = @(
        $Metadata.Keys |
            Where-Object {
                @(
                    Get-RenderKitMkvToolNixWriteDefinitions `
                        -Field ([string]$_)
                ).Count -gt 0
            } |
            ForEach-Object { [string]$_ } |
            Sort-Object -Unique
    )
    if ($writtenFields.Count -eq 0) {
        throw 'The metadata set contains no writable Matroska fields.'
    }
    $runtime = Resolve-RenderKitMkvToolNixRuntime
    if (-not [bool]$runtime.Available) {
        throw [string]$runtime.Error
    }

    $lockHandle = Enter-RenderKitFileLock `
        -Path "$resolvedPath.renderkit-metadata" `
        -TimeoutMilliseconds 30000
    $directory = Split-Path -Parent $resolvedPath
    $extension = [IO.Path]::GetExtension($resolvedPath)
    $baseName = [IO.Path]::GetFileNameWithoutExtension($resolvedPath)
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
                [IO.Path]::GetFileName($resolvedPath),
                [guid]::NewGuid().ToString('N')
        )
    $workRoot = Join-Path `
        -Path ([IO.Path]::GetTempPath()) `
        -ChildPath ('renderkit-mkv-write-{0}' -f
            [guid]::NewGuid().ToString('N'))
    $sourceTimestamp = [IO.File]::GetLastWriteTimeUtc($resolvedPath)
    $sourceAttributes = [IO.File]::GetAttributes($resolvedPath)
    $replacementComplete = $false
    $preserveBackup = $false
    New-Item -ItemType Directory -Path $workRoot -Force |
        Out-Null
    try {
        [IO.File]::Copy($resolvedPath, $temporaryPath, $false)
        $artifacts = New-RenderKitMkvToolNixWriteArtifacts `
            -Path $temporaryPath `
            -Metadata $Metadata `
            -Runtime $runtime `
            -TemporaryRoot $workRoot
        $command = Invoke-RenderKitMkvToolNixApplication `
            -Path ([string]$runtime.PropEditPath) `
            -Name 'mkvpropedit' `
            -Arguments (@($temporaryPath) + @($artifacts.Arguments))
        $candidateRead = Test-RenderKitMkvToolNixWrite `
            -Path $temporaryPath `
            -Metadata $Metadata

        try {
            [IO.File]::Replace(
                $temporaryPath,
                $resolvedPath,
                $backupPath,
                $true
            )
            $replacementComplete = $true
        }
        catch {
            try {
                [IO.File]::Move($resolvedPath, $backupPath)
                try {
                    [IO.File]::Move($temporaryPath, $resolvedPath)
                    $replacementComplete = $true
                }
                catch {
                    [IO.File]::Move($backupPath, $resolvedPath)
                    throw
                }
            }
            catch {
                throw "Atomic Matroska replacement failed: $($_.Exception.Message)"
            }
        }
        [IO.File]::SetLastWriteTimeUtc(
            $resolvedPath,
            $sourceTimestamp
        )
        [IO.File]::SetAttributes(
            $resolvedPath,
            $sourceAttributes
        )
        $finalRead = Test-RenderKitMkvToolNixWrite `
            -Path $resolvedPath `
            -Metadata $Metadata
        if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
            Remove-Item -LiteralPath $backupPath -Force
        }
        return [PSCustomObject]@{
            Path = $resolvedPath
            Profile = 'Matroska'
            Adapter = 'MkvToolNix'
            Backend = 'MkvPropEdit'
            BackendSource = [string]$runtime.Source
            BackendPath = [string]$runtime.PropEditPath
            BackendVersion = [string]$runtime.Version
            ExtractPath = [string]$runtime.ExtractPath
            Fields = @($writtenFields)
            Verified = $true
            GlobalTagsChanged = [bool]$artifacts.HasTagChanges
            ChaptersChanged = [bool]$artifacts.HasChapterChanges
            Output = @($command.Output)
            CandidateChapterCount = $candidateRead.Fields.ChapterCount
            ChapterCount = $finalRead.Fields.ChapterCount
        }
    }
    catch {
        $failure = $_
        if ($replacementComplete -and
            (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            try {
                if (Test-Path -LiteralPath $resolvedPath -PathType Leaf) {
                    try {
                        [IO.File]::Replace(
                            $backupPath,
                            $resolvedPath,
                            $null,
                            $true
                        )
                    }
                    catch {
                        [IO.File]::Copy(
                            $backupPath,
                            $resolvedPath,
                            $true
                        )
                    }
                }
                else {
                    [IO.File]::Move($backupPath, $resolvedPath)
                }
                [IO.File]::SetLastWriteTimeUtc(
                    $resolvedPath,
                    $sourceTimestamp
                )
                [IO.File]::SetAttributes(
                    $resolvedPath,
                    $sourceAttributes
                )
            }
            catch {
                $preserveBackup = $true
                throw "Matroska write failed and backup restoration also failed. Original error: $($failure.Exception.Message). Restore error: $($_.Exception.Message). Backup: '$backupPath'."
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
        Remove-Item `
            -LiteralPath $workRoot `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
        Exit-RenderKitFileLock -LockHandle $lockHandle
    }
}
