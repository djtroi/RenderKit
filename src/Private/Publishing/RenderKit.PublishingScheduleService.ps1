function New-RenderKitPublishingSchedule {
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        tool          = 'RenderKit'
        schemaVersion = '1.0'
        updatedAtUtc  = [DateTime]::UtcNow.ToString('o')
        publications  = @()
    }
}

function Test-RenderKitPublishingSchedule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Schedule
    )

    try {
        if ([string]$Schedule.tool -ne 'RenderKit' -or
            [string]::IsNullOrWhiteSpace([string]$Schedule.schemaVersion)) {
            return $false
        }
        $compatibility = Test-RenderKitArtifactCompatibility `
            -ArtifactType PublishingSchedule `
            -Version ([string]$Schedule.schemaVersion)
        if (-not ($compatibility.CanRead -and $compatibility.CanWrite) -or
            -not ($Schedule.PSObject.Properties.Name -contains 'publications') -or
            $null -eq $Schedule.publications) {
            return $false
        }
        $records = @($Schedule.publications)
        if ($records.Count -gt 50000) {
            return $false
        }
        $ids = @{}
        foreach ($record in $records) {
            if (-not (Test-RenderKitPublicationRecord -Publication $record)) {
                return $false
            }
            $id = ([string]$record.id).ToLowerInvariant()
            if ($ids.ContainsKey($id)) {
                return $false
            }
            $ids[$id] = $true
        }
        return $true
    }
    catch {
        return $false
    }
}

function Test-RenderKitPublicationRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Publication
    )

    $required = @(
        'id',
        'title',
        'status',
        'startUtc',
        'endUtc',
        'timeZone',
        'media',
        'revision',
        'createdAtUtc',
        'updatedAtUtc'
    )
    foreach ($property in $required) {
        if (-not ($Publication.PSObject.Properties.Name -contains $property)) {
            return $false
        }
    }

    try {
        $normalized = New-RenderKitPublicationRecord `
            -Id ([string]$Publication.id) `
            -Title ([string]$Publication.title) `
            -Description ([string]$Publication.description) `
            -Status ([string]$Publication.status) `
            -StartUtc $Publication.startUtc `
            -EndUtc $Publication.endUtc `
            -TimeZone ([string]$Publication.timeZone) `
            -ProjectId ([string]$Publication.projectId) `
            -ProjectNameSnapshot ([string]$Publication.projectNameSnapshot) `
            -ClientId ([string]$Publication.clientId) `
            -ClientNameSnapshot ([string]$Publication.clientNameSnapshot) `
            -ChannelProvider ([string]$Publication.channelProvider) `
            -ChannelId ([string]$Publication.channelId) `
            -ChannelNameSnapshot ([string]$Publication.channelNameSnapshot) `
            -OwnerId ([string]$Publication.ownerId) `
            -OwnerNameSnapshot ([string]$Publication.ownerNameSnapshot) `
            -Media @($Publication.media) `
            -ExternalUrl ([string]$Publication.externalUrl) `
            -PublishedAtUtc $Publication.publishedAtUtc `
            -Revision ([int]$Publication.revision) `
            -CreatedAtUtc $Publication.createdAtUtc `
            -UpdatedAtUtc $Publication.updatedAtUtc
        return (
            [string]$normalized.id -eq [string]$Publication.id -and
            [int]$normalized.revision -ge 1
        )
    }
    catch {
        return $false
    }
}

function Read-RenderKitPublishingSchedule {
    [CmdletBinding()]
    param()

    $schedule = Read-RenderKitJsonFile `
        -Path (Get-RenderKitPublishingSchedulePath) `
        -AllowMissing `
        -Validator { param($value) Test-RenderKitPublishingSchedule $value }
    if (-not $schedule) {
        return New-RenderKitPublishingSchedule
    }
    foreach ($publication in @($schedule.publications)) {
        $publication.startUtc = ConvertTo-RenderKitPublicationUtcTimestamp `
            -Value $publication.startUtc -Name StartUtc -Required
        $publication.endUtc = ConvertTo-RenderKitPublicationUtcTimestamp `
            -Value $publication.endUtc -Name EndUtc
        $publication.publishedAtUtc =
            ConvertTo-RenderKitPublicationUtcTimestamp `
                -Value $publication.publishedAtUtc -Name PublishedAtUtc
        $publication.createdAtUtc = ConvertTo-RenderKitPublicationUtcTimestamp `
            -Value $publication.createdAtUtc -Name CreatedAtUtc -Required
        $publication.updatedAtUtc = ConvertTo-RenderKitPublicationUtcTimestamp `
            -Value $publication.updatedAtUtc -Name UpdatedAtUtc -Required
    }
    $schedule.updatedAtUtc = ConvertTo-RenderKitPublicationUtcTimestamp `
        -Value $schedule.updatedAtUtc -Name UpdatedAtUtc -Required
    return $schedule
}

function New-RenderKitPublicationRecord {
    [CmdletBinding()]
    param(
        [string]$Id,
        [Parameter(Mandatory)]
        [string]$Title,
        [string]$Description,
        [ValidateSet(
            'Draft',
            'Scheduled',
            'Publishing',
            'Published',
            'Failed',
            'Cancelled'
        )]
        [string]$Status = 'Draft',
        [Parameter(Mandatory)]
        [object]$StartUtc,
        [object]$EndUtc,
        [Parameter(Mandatory)]
        [string]$TimeZone,
        [string]$ProjectId,
        [string]$ProjectNameSnapshot,
        [string]$ClientId,
        [string]$ClientNameSnapshot,
        [string]$ChannelProvider,
        [string]$ChannelId,
        [string]$ChannelNameSnapshot,
        [string]$OwnerId,
        [string]$OwnerNameSnapshot,
        [object[]]$Media = @(),
        [string]$ExternalUrl,
        [object]$PublishedAtUtc,
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Revision = 1,
        [object]$CreatedAtUtc,
        [object]$UpdatedAtUtc
    )

    $now = [DateTime]::UtcNow.ToString('o')
    $normalizedId = ConvertTo-RenderKitPublicationText `
        -Value $Id -Name Id -MaximumLength 128
    if ([string]::IsNullOrWhiteSpace($normalizedId)) {
        $normalizedId = [guid]::NewGuid().Guid
    }
    $normalizedStart = ConvertTo-RenderKitPublicationUtcTimestamp `
        -Value $StartUtc -Name StartUtc -Required
    $normalizedEnd = ConvertTo-RenderKitPublicationUtcTimestamp `
        -Value $EndUtc -Name EndUtc
    if (-not [string]::IsNullOrWhiteSpace($normalizedEnd) -and
        [DateTimeOffset]::Parse($normalizedEnd) -le
        [DateTimeOffset]::Parse($normalizedStart)) {
        throw [System.ArgumentException]::new(
            'EndUtc must be later than StartUtc.')
    }
    $normalizedTimeZone = ConvertTo-RenderKitPublicationTimeZone $TimeZone
    $normalizedExternalUrl = ConvertTo-RenderKitPublicationText `
        -Value $ExternalUrl -Name ExternalUrl -MaximumLength 2048
    if (-not [string]::IsNullOrWhiteSpace($normalizedExternalUrl)) {
        $uri = $null
        if (-not [Uri]::TryCreate(
            $normalizedExternalUrl,
            [UriKind]::Absolute,
            [ref]$uri
        ) -or @('https', 'http') -notcontains $uri.Scheme) {
            throw [System.ArgumentException]::new(
                'ExternalUrl must be an absolute HTTP or HTTPS URL.')
        }
    }

    return [PSCustomObject]@{
        id                  = $normalizedId
        title               = ConvertTo-RenderKitPublicationText `
            -Value $Title -Name Title -MaximumLength 255 -Required
        description         = ConvertTo-RenderKitPublicationText `
            -Value $Description -Name Description -MaximumLength 8000
        status              = $Status
        startUtc            = $normalizedStart
        endUtc              = $normalizedEnd
        timeZone            = $normalizedTimeZone
        projectId           = ConvertTo-RenderKitPublicationText `
            -Value $ProjectId -Name ProjectId -MaximumLength 128
        projectNameSnapshot = ConvertTo-RenderKitPublicationText `
            -Value $ProjectNameSnapshot -Name ProjectNameSnapshot `
            -MaximumLength 255
        clientId            = ConvertTo-RenderKitPublicationText `
            -Value $ClientId -Name ClientId -MaximumLength 128
        clientNameSnapshot  = ConvertTo-RenderKitPublicationText `
            -Value $ClientNameSnapshot -Name ClientNameSnapshot `
            -MaximumLength 255
        channelProvider     = ConvertTo-RenderKitPublicationText `
            -Value $ChannelProvider -Name ChannelProvider -MaximumLength 64
        channelId           = ConvertTo-RenderKitPublicationText `
            -Value $ChannelId -Name ChannelId -MaximumLength 255
        channelNameSnapshot = ConvertTo-RenderKitPublicationText `
            -Value $ChannelNameSnapshot -Name ChannelNameSnapshot `
            -MaximumLength 255
        ownerId             = ConvertTo-RenderKitPublicationText `
            -Value $OwnerId -Name OwnerId -MaximumLength 128
        ownerNameSnapshot   = ConvertTo-RenderKitPublicationText `
            -Value $OwnerNameSnapshot -Name OwnerNameSnapshot `
            -MaximumLength 255
        media               = @(
            ConvertTo-RenderKitPublicationMedia -Value $Media
        )
        externalUrl         = $normalizedExternalUrl
        publishedAtUtc      = ConvertTo-RenderKitPublicationUtcTimestamp `
            -Value $PublishedAtUtc -Name PublishedAtUtc
        recurrence          = $null
        revision            = $Revision
        createdAtUtc        = ConvertTo-RenderKitPublicationUtcTimestamp `
            -Value $CreatedAtUtc -Name CreatedAtUtc -DefaultValue $now
        updatedAtUtc        = ConvertTo-RenderKitPublicationUtcTimestamp `
            -Value $UpdatedAtUtc -Name UpdatedAtUtc -DefaultValue $now
    }
}

function Add-RenderKitPublicationRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Publication
    )

    if (-not (Test-RenderKitPublicationRecord -Publication $Publication)) {
        throw [System.ArgumentException]::new(
            'The RenderKit publication record is invalid.')
    }
    Invoke-RenderKitJsonFileTransaction `
        -Path (Get-RenderKitPublishingSchedulePath) `
        -DefaultValue (New-RenderKitPublishingSchedule) `
        -Depth 12 `
        -Validator { param($value) Test-RenderKitPublishingSchedule $value } `
        -Update {
            param($schedule)
            if (@($schedule.publications | Where-Object {
                [string]$_.id -eq [string]$Publication.id
            }).Count -gt 0) {
                throw [System.InvalidOperationException]::new(
                    "RenderKit publication '$($Publication.id)' already exists.")
            }
            $schedule.publications = @(
                @($schedule.publications) + $Publication |
                    Sort-Object -Property startUtc, title, id
            )
            $schedule.updatedAtUtc = [DateTime]::UtcNow.ToString('o')
            return $schedule
        } | Out-Null

    return Get-RenderKitPublicationRecord -Id ([string]$Publication.id)
}

function Update-RenderKitPublicationRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id,
        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$ExpectedRevision,
        [Parameter(Mandatory)]
        [hashtable]$Changes
    )

    Invoke-RenderKitJsonFileTransaction `
        -Path (Get-RenderKitPublishingSchedulePath) `
        -DefaultValue (New-RenderKitPublishingSchedule) `
        -Depth 12 `
        -Validator { param($value) Test-RenderKitPublishingSchedule $value } `
        -Update {
            param($schedule)
            $matches = @($schedule.publications | Where-Object {
                [string]$_.id -eq $Id
            })
            if ($matches.Count -eq 0) {
                throw [System.Collections.Generic.KeyNotFoundException]::new(
                    "RenderKit publication '$Id' was not found.")
            }
            $current = $matches[0]
            if ([int]$current.revision -ne $ExpectedRevision) {
                throw [System.InvalidOperationException]::new(
                    "RenderKit publication '$Id' changed from revision " +
                    "$ExpectedRevision to $($current.revision).")
            }
            $parameters = @{
                Id = [string]$current.id
                Title = [string]$current.title
                Description = [string]$current.description
                Status = [string]$current.status
                StartUtc = $current.startUtc
                EndUtc = $current.endUtc
                TimeZone = [string]$current.timeZone
                ProjectId = [string]$current.projectId
                ProjectNameSnapshot = [string]$current.projectNameSnapshot
                ClientId = [string]$current.clientId
                ClientNameSnapshot = [string]$current.clientNameSnapshot
                ChannelProvider = [string]$current.channelProvider
                ChannelId = [string]$current.channelId
                ChannelNameSnapshot = [string]$current.channelNameSnapshot
                OwnerId = [string]$current.ownerId
                OwnerNameSnapshot = [string]$current.ownerNameSnapshot
                Media = @($current.media)
                ExternalUrl = [string]$current.externalUrl
                PublishedAtUtc = $current.publishedAtUtc
                Revision = ([int]$current.revision + 1)
                CreatedAtUtc = $current.createdAtUtc
                UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
            }
            $allowed = @(
                'Title',
                'Description',
                'Status',
                'StartUtc',
                'EndUtc',
                'TimeZone',
                'ProjectId',
                'ProjectNameSnapshot',
                'ClientId',
                'ClientNameSnapshot',
                'ChannelProvider',
                'ChannelId',
                'ChannelNameSnapshot',
                'OwnerId',
                'OwnerNameSnapshot',
                'Media',
                'ExternalUrl',
                'PublishedAtUtc'
            )
            foreach ($key in $Changes.Keys) {
                if ($allowed -notcontains $key) {
                    throw [System.ArgumentException]::new(
                        "Unsupported publication field '$key'.")
                }
                $parameters[$key] = $Changes[$key]
            }
            if ($Changes.ContainsKey('Status')) {
                Assert-RenderKitPublicationStatusTransition `
                    -Current ([string]$current.status) `
                    -Next ([string]$Changes.Status)
            }
            $updated = New-RenderKitPublicationRecord @parameters
            $schedule.publications = @(
                @($schedule.publications | Where-Object {
                    [string]$_.id -ne $Id
                }) + $updated |
                    Sort-Object -Property startUtc, title, id
            )
            $schedule.updatedAtUtc = [DateTime]::UtcNow.ToString('o')
            return $schedule
        } | Out-Null

    return Get-RenderKitPublicationRecord -Id $Id
}

function Get-RenderKitPublicationRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    $matches = @((Read-RenderKitPublishingSchedule).publications |
        Where-Object { [string]$_.id -eq $Id })
    if ($matches.Count -eq 0) {
        return $null
    }
    return $matches[0]
}

function Get-RenderKitPublicationRecordList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FromUtc,
        [Parameter(Mandatory)]
        [string]$ToUtc,
        [string]$Search,
        [string]$Status,
        [string]$ProjectId,
        [string]$ClientId,
        [string]$ChannelProvider
    )

    $from = ConvertTo-RenderKitPublicationUtcTimestamp `
        -Value $FromUtc -Name FromUtc -Required
    $to = ConvertTo-RenderKitPublicationUtcTimestamp `
        -Value $ToUtc -Name ToUtc -Required
    if ([DateTimeOffset]::Parse($to) -le [DateTimeOffset]::Parse($from)) {
        throw [System.ArgumentException]::new(
            'ToUtc must be later than FromUtc.')
    }
    if (([DateTimeOffset]::Parse($to) - [DateTimeOffset]::Parse($from)).
        TotalDays -gt 370) {
        throw [System.ArgumentException]::new(
            'Publication queries may cover at most 370 days.')
    }

    $records = @((Read-RenderKitPublishingSchedule).publications |
        Where-Object {
            $start = [DateTimeOffset]::Parse(
                (ConvertTo-RenderKitPublicationUtcTimestamp `
                    -Value $_.startUtc -Name StartUtc -Required)
            )
            $end = if ([string]::IsNullOrWhiteSpace([string]$_.endUtc)) {
                $start.AddTicks(1)
            }
            else {
                [DateTimeOffset]::Parse(
                    (ConvertTo-RenderKitPublicationUtcTimestamp `
                        -Value $_.endUtc -Name EndUtc)
                )
            }
            $start -lt [DateTimeOffset]::Parse($to) -and
            $end -gt [DateTimeOffset]::Parse($from)
        })
    if (-not [string]::IsNullOrWhiteSpace($Status)) {
        if (@(
            'Draft',
            'Scheduled',
            'Publishing',
            'Published',
            'Failed',
            'Cancelled'
        ) -notcontains $Status) {
            throw [System.ArgumentException]::new(
                "Unsupported publication status '$Status'.")
        }
        $records = @($records | Where-Object {
            [string]$_.status -eq $Status
        })
    }
    foreach ($filter in @(
        @{ Name = 'projectId'; Value = $ProjectId },
        @{ Name = 'clientId'; Value = $ClientId },
        @{ Name = 'channelProvider'; Value = $ChannelProvider }
    )) {
        if (-not [string]::IsNullOrWhiteSpace([string]$filter.Value)) {
            $name = [string]$filter.Name
            $value = [string]$filter.Value
            $records = @($records | Where-Object {
                [string]$_.$name -eq $value
            })
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($Search)) {
        $needle = $Search.Trim()
        $records = @($records | Where-Object {
            [string]$_.id -like "*$needle*" -or
            [string]$_.title -like "*$needle*" -or
            [string]$_.projectNameSnapshot -like "*$needle*" -or
            [string]$_.clientNameSnapshot -like "*$needle*" -or
            [string]$_.channelNameSnapshot -like "*$needle*"
        })
    }
    return @($records | Sort-Object -Property startUtc, title, id)
}

function Assert-RenderKitPublicationStatusTransition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Current,
        [Parameter(Mandatory)][string]$Next
    )

    $allowed = @{
        Draft = @('Draft', 'Scheduled', 'Cancelled')
        Scheduled = @('Draft', 'Scheduled', 'Publishing', 'Cancelled')
        Publishing = @('Publishing', 'Published', 'Failed')
        Failed = @('Failed', 'Scheduled', 'Cancelled')
        Published = @('Published')
        Cancelled = @('Cancelled')
    }
    if (-not $allowed.ContainsKey($Current) -or
        $allowed[$Current] -notcontains $Next) {
        throw [System.InvalidOperationException]::new(
            "Publication status cannot change from '$Current' to '$Next'.")
    }
}

function ConvertTo-RenderKitPublicationText {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$MaximumLength,
        [switch]$Required
    )

    $text = if ($null -eq $Value) { '' } else { ([string]$Value).Trim() }
    if ($Required -and [string]::IsNullOrWhiteSpace($text)) {
        throw [System.ArgumentException]::new("$Name must not be empty.")
    }
    if ($text.Length -gt $MaximumLength) {
        throw [System.ArgumentException]::new(
            "$Name exceeds the $MaximumLength character limit.")
    }
    return $text
}

function ConvertTo-RenderKitPublicationUtcTimestamp {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][string]$Name,
        [string]$DefaultValue,
        [switch]$Required
    )

    $text = if ($null -eq $Value) { '' } else { ([string]$Value).Trim() }
    if ($Value -is [DateTimeOffset]) {
        return ([DateTimeOffset]$Value).ToUniversalTime().ToString('o')
    }
    if ($Value -is [DateTime]) {
        $dateTime = [DateTime]$Value
        return ([DateTimeOffset]$dateTime).ToUniversalTime().ToString('o')
    }
    if ([string]::IsNullOrWhiteSpace($text)) {
        if ($Required -and [string]::IsNullOrWhiteSpace($DefaultValue)) {
            throw [System.ArgumentException]::new("$Name must not be empty.")
        }
        return $DefaultValue
    }
    if ($text -notmatch '(?:Z|[+-]\d{2}:\d{2})$') {
        throw [System.ArgumentException]::new(
            "$Name requires an explicit UTC offset.")
    }
    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse(
        $text,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None,
        [ref]$parsed
    )) {
        throw [System.ArgumentException]::new(
            "$Name is not a valid ISO-8601 timestamp.")
    }
    return $parsed.ToUniversalTime().ToString('o')
}

function ConvertTo-RenderKitPublicationTimeZone {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Value
    )

    $timeZone = ConvertTo-RenderKitPublicationText `
        -Value $Value -Name TimeZone -MaximumLength 128 -Required
    try {
        [TimeZoneInfo]::FindSystemTimeZoneById($timeZone) | Out-Null
        return $timeZone
    }
    catch {
        if ($timeZone -eq 'UTC' -or
            $timeZone -match '^[A-Za-z_]+(?:/[A-Za-z0-9_+\-]+)+$') {
            return $timeZone
        }
        throw [System.ArgumentException]::new(
            "TimeZone '$timeZone' is not a valid IANA timezone identifier.")
    }
}

function ConvertTo-RenderKitPublicationMedia {
    [CmdletBinding()]
    param(
        [AllowNull()][object[]]$Value
    )

    $items = @($Value | Where-Object { $null -ne $_ })
    if ($items.Count -gt 200) {
        throw [System.ArgumentException]::new(
            'A publication supports at most 200 media references.')
    }
    return @($items | ForEach-Object {
        $item = $_
        $id = Get-RenderKitPublicationProperty -Value $item -Name id
        [PSCustomObject]@{
            id = ConvertTo-RenderKitPublicationText `
                -Value $id -Name MediaId -MaximumLength 512 -Required
            nameSnapshot = ConvertTo-RenderKitPublicationText `
                -Value (Get-RenderKitPublicationProperty `
                    -Value $item -Name nameSnapshot) `
                -Name MediaNameSnapshot -MaximumLength 255
        }
    })
}

function Get-RenderKitPublicationProperty {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        if ($Value.Contains($Name)) { return $Value[$Name] }
        return $null
    }
    if ($Value.PSObject.Properties.Name -contains $Name) {
        return $Value.$Name
    }
    return $null
}
