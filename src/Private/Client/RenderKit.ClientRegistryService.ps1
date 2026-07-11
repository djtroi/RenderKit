function New-RenderKitClientRegistry {
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        tool          = 'RenderKit'
        schemaVersion = '1.0'
        updatedAtUtc  = [DateTime]::UtcNow.ToString('o')
        clients       = @()
    }
}

function Test-RenderKitClientRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Registry
    )

    try {
        if ([string]$Registry.tool -ne 'RenderKit' -or
            [string]::IsNullOrWhiteSpace([string]$Registry.schemaVersion)) {
            return $false
        }
        $compatibility = Test-RenderKitArtifactCompatibility `
            -ArtifactType ClientRegistry `
            -Version ([string]$Registry.schemaVersion)
        if (-not ($compatibility.CanRead -and $compatibility.CanWrite) -or
            -not ($Registry.PSObject.Properties.Name -contains 'clients') -or
            $null -eq $Registry.clients) {
            return $false
        }

        $ids = @{}
        foreach ($client in @($Registry.clients)) {
            if (-not (Test-RenderKitClientRecord -Client $client)) {
                return $false
            }
            $id = ([string]$client.id).ToLowerInvariant()
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

function Test-RenderKitClientRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Client
    )

    $required = @(
        'id',
        'displayName',
        'status',
        'revision',
        'createdAtUtc',
        'updatedAtUtc',
        'tags',
        'contacts',
        'addresses'
    )
    foreach ($property in $required) {
        if (-not ($Client.PSObject.Properties.Name -contains $property)) {
            return $false
        }
    }
    if ([string]::IsNullOrWhiteSpace([string]$Client.id) -or
        [string]::IsNullOrWhiteSpace([string]$Client.displayName) -or
        ([string]$Client.displayName).Length -gt 255 -or
        @('Active', 'Inactive', 'Archived') -notcontains [string]$Client.status -or
        [int]$Client.revision -lt 1 -or
        -not (Test-RenderKitClientUtcTimestamp $Client.createdAtUtc) -or
        -not (Test-RenderKitClientUtcTimestamp $Client.updatedAtUtc)) {
        return $false
    }

    try {
        ConvertTo-RenderKitClientTags -Value $Client.tags | Out-Null
        ConvertTo-RenderKitClientContacts -Value $Client.contacts `
            -RequireIdentifiers | Out-Null
        ConvertTo-RenderKitClientAddresses -Value $Client.addresses `
            -RequireIdentifiers | Out-Null
    }
    catch {
        return $false
    }
    return $true
}

function Read-RenderKitClientRegistry {
    [CmdletBinding()]
    param()

    $registry = Read-RenderKitJsonFile `
        -Path (Get-RenderKitClientRegistryPath) `
        -AllowMissing `
        -Validator { param($value) Test-RenderKitClientRegistry $value }
    if (-not $registry) {
        return New-RenderKitClientRegistry
    }
    return $registry
}

function Write-RenderKitClientRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Registry
    )

    $Registry.updatedAtUtc = [DateTime]::UtcNow.ToString('o')
    return Write-RenderKitJsonFileAtomic `
        -Path (Get-RenderKitClientRegistryPath) `
        -Value $Registry `
        -Depth 12 `
        -Validator { param($value) Test-RenderKitClientRegistry $value }
}

function New-RenderKitClientRecord {
    [CmdletBinding()]
    param(
        [string]$Id,
        [Parameter(Mandatory)]
        [string]$DisplayName,
        [string]$LegalName,
        [ValidateSet('Active', 'Inactive', 'Archived')]
        [string]$Status = 'Active',
        [string[]]$Tags = @(),
        [string]$Notes,
        [object[]]$Contacts = @(),
        [object[]]$Addresses = @(),
        [object]$Consent,
        [object]$Retention,
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Revision = 1,
        [string]$CreatedAtUtc,
        [string]$UpdatedAtUtc
    )

    $now = [DateTime]::UtcNow.ToString('o')
    $normalizedDisplayName = ConvertTo-RenderKitClientText `
        -Value $DisplayName -Name DisplayName -MaximumLength 255 -Required
    $normalizedId = ConvertTo-RenderKitClientText `
        -Value $Id -Name Id -MaximumLength 128
    if ([string]::IsNullOrWhiteSpace($normalizedId)) {
        $normalizedId = [guid]::NewGuid().Guid
    }

    return [PSCustomObject]@{
        id           = $normalizedId
        displayName  = $normalizedDisplayName
        legalName    = ConvertTo-RenderKitClientText `
            -Value $LegalName -Name LegalName -MaximumLength 255
        status       = $Status
        tags         = @(ConvertTo-RenderKitClientTags -Value $Tags)
        notes        = ConvertTo-RenderKitClientText `
            -Value $Notes -Name Notes -MaximumLength 4000
        contacts     = @(ConvertTo-RenderKitClientContacts -Value $Contacts)
        addresses    = @(ConvertTo-RenderKitClientAddresses -Value $Addresses)
        consent      = ConvertTo-RenderKitClientConsent -Value $Consent
        retention    = ConvertTo-RenderKitClientRetention -Value $Retention
        revision     = $Revision
        createdAtUtc = ConvertTo-RenderKitClientUtcTimestamp `
            -Value $CreatedAtUtc -DefaultValue $now
        updatedAtUtc = ConvertTo-RenderKitClientUtcTimestamp `
            -Value $UpdatedAtUtc -DefaultValue $now
    }
}

function Add-RenderKitClientRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Client
    )

    if (-not (Test-RenderKitClientRecord -Client $Client)) {
        throw [System.ArgumentException]::new(
            'The RenderKit client record is invalid.')
    }
    $path = Get-RenderKitClientRegistryPath
    Invoke-RenderKitJsonFileTransaction `
        -Path $path `
        -DefaultValue (New-RenderKitClientRegistry) `
        -Depth 12 `
        -Validator { param($value) Test-RenderKitClientRegistry $value } `
        -Update {
            param($registry)
            if (@($registry.clients | Where-Object {
                [string]$_.id -eq [string]$Client.id
            }).Count -gt 0) {
                throw [System.InvalidOperationException]::new(
                    "RenderKit client '$($Client.id)' already exists.")
            }
            $registry.clients = @(
                @($registry.clients) + $Client |
                    Sort-Object -Property displayName, id
            )
            $registry.updatedAtUtc = [DateTime]::UtcNow.ToString('o')
            return $registry
        } | Out-Null

    return Get-RenderKitClientRecord -Id ([string]$Client.id)
}

function Update-RenderKitClientRecord {
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

    # Check the caller's revision inside the file transaction. Performing it
    # before acquiring the transaction lock would allow a read-check-write race.
    Invoke-RenderKitJsonFileTransaction `
        -Path (Get-RenderKitClientRegistryPath) `
        -DefaultValue (New-RenderKitClientRegistry) `
        -Depth 12 `
        -Validator { param($value) Test-RenderKitClientRegistry $value } `
        -Update {
            param($registry)
            $matches = @($registry.clients | Where-Object {
                [string]$_.id -eq $Id
            })
            if ($matches.Count -eq 0) {
                throw [System.Collections.Generic.KeyNotFoundException]::new(
                    "RenderKit client '$Id' was not found.")
            }
            $current = $matches[0]
            if ([int]$current.revision -ne $ExpectedRevision) {
                throw [System.InvalidOperationException]::new(
                    "RenderKit client '$Id' changed from revision " +
                    "$ExpectedRevision to $($current.revision).")
            }

            $parameters = @{
                Id = [string]$current.id
                DisplayName = [string]$current.displayName
                LegalName = [string]$current.legalName
                Status = [string]$current.status
                Tags = @($current.tags)
                Notes = [string]$current.notes
                Contacts = @($current.contacts)
                Addresses = @($current.addresses)
                Consent = $current.consent
                Retention = $current.retention
                Revision = ([int]$current.revision + 1)
                CreatedAtUtc = [string]$current.createdAtUtc
                UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
            }
            foreach ($key in $Changes.Keys) {
                if (@(
                    'DisplayName',
                    'LegalName',
                    'Status',
                    'Tags',
                    'Notes',
                    'Contacts',
                    'Addresses',
                    'Consent',
                    'Retention'
                ) -notcontains $key) {
                    throw [System.ArgumentException]::new(
                        "Unsupported client field '$key'.")
                }
                $parameters[$key] = $Changes[$key]
            }

            $updatedClient = New-RenderKitClientRecord @parameters
            $registry.clients = @(
                @($registry.clients | Where-Object {
                    [string]$_.id -ne $Id
                }) + $updatedClient |
                    Sort-Object -Property displayName, id
            )
            $registry.updatedAtUtc = [DateTime]::UtcNow.ToString('o')
            return $registry
        } | Out-Null

    return Get-RenderKitClientRecord -Id $Id
}

function Get-RenderKitClientRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    $matches = @((Read-RenderKitClientRegistry).clients | Where-Object {
        [string]$_.id -eq $Id
    })
    if ($matches.Count -eq 0) {
        return $null
    }
    return $matches[0]
}

function Get-RenderKitClientRecordList {
    [CmdletBinding()]
    param(
        [string]$Search,
        [ValidateSet('Active', 'Inactive', 'Archived')]
        [string]$Status,
        [string]$Tag
    )

    $clients = @((Read-RenderKitClientRegistry).clients)
    if (-not [string]::IsNullOrWhiteSpace($Status)) {
        $clients = @($clients | Where-Object {
            [string]$_.status -eq $Status
        })
    }
    if (-not [string]::IsNullOrWhiteSpace($Tag)) {
        $clients = @($clients | Where-Object {
            @($_.tags) -icontains $Tag.Trim()
        })
    }
    if (-not [string]::IsNullOrWhiteSpace($Search)) {
        $needle = $Search.Trim()
        $clients = @($clients | Where-Object {
            [string]$_.id -like "*$needle*" -or
            [string]$_.displayName -like "*$needle*" -or
            [string]$_.legalName -like "*$needle*" -or
            @($_.tags | Where-Object { [string]$_ -like "*$needle*" }).Count -gt 0
        })
    }
    return @($clients | Sort-Object -Property displayName, id)
}

function ConvertTo-RenderKitClientText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [int]$MaximumLength,
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

function ConvertTo-RenderKitClientTags {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$Value
    )

    $tags = @($Value | ForEach-Object {
        ConvertTo-RenderKitClientText `
            -Value $_ -Name Tag -MaximumLength 64
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique)
    if ($tags.Count -gt 50) {
        throw [System.ArgumentException]::new(
            'A RenderKit client supports at most 50 tags.')
    }
    return $tags
}

function ConvertTo-RenderKitClientContacts {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$Value,
        [switch]$RequireIdentifiers
    )

    $contacts = @($Value | Where-Object { $null -ne $_ })
    if ($contacts.Count -gt 100) {
        throw [System.ArgumentException]::new(
            'A RenderKit client supports at most 100 contacts.')
    }
    $primaryCount = 0
    $normalized = foreach ($contact in $contacts) {
        $id = ConvertTo-RenderKitClientText `
            -Value (Get-RenderKitClientProperty $contact id) `
            -Name ContactId -MaximumLength 128
        if ([string]::IsNullOrWhiteSpace($id)) {
            if ($RequireIdentifiers) {
                throw [System.ArgumentException]::new(
                    'Persisted contacts require an id.')
            }
            $id = [guid]::NewGuid().Guid
        }
        $email = ConvertTo-RenderKitClientText `
            -Value (Get-RenderKitClientProperty $contact email) `
            -Name ContactEmail -MaximumLength 320
        if (-not [string]::IsNullOrWhiteSpace($email) -and
            $email -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
            throw [System.ArgumentException]::new(
                'ContactEmail is not a valid email address.')
        }
        $isPrimary = [bool](Get-RenderKitClientProperty $contact isPrimary)
        if ($isPrimary) { $primaryCount += 1 }
        [PSCustomObject]@{
            id          = $id
            displayName = ConvertTo-RenderKitClientText `
                -Value (Get-RenderKitClientProperty $contact displayName) `
                -Name ContactDisplayName -MaximumLength 255 -Required
            role        = ConvertTo-RenderKitClientText `
                -Value (Get-RenderKitClientProperty $contact role) `
                -Name ContactRole -MaximumLength 128
            email       = $email
            phone       = ConvertTo-RenderKitClientText `
                -Value (Get-RenderKitClientProperty $contact phone) `
                -Name ContactPhone -MaximumLength 64
            isPrimary   = $isPrimary
        }
    }
    if ($primaryCount -gt 1) {
        throw [System.ArgumentException]::new(
            'A RenderKit client supports only one primary contact.')
    }
    return @($normalized)
}

function ConvertTo-RenderKitClientAddresses {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$Value,
        [switch]$RequireIdentifiers
    )

    $addresses = @($Value | Where-Object { $null -ne $_ })
    if ($addresses.Count -gt 20) {
        throw [System.ArgumentException]::new(
            'A RenderKit client supports at most 20 addresses.')
    }
    return @($addresses | ForEach-Object {
        $address = $_
        $id = ConvertTo-RenderKitClientText `
            -Value (Get-RenderKitClientProperty $address id) `
            -Name AddressId -MaximumLength 128
        if ([string]::IsNullOrWhiteSpace($id)) {
            if ($RequireIdentifiers) {
                throw [System.ArgumentException]::new(
                    'Persisted addresses require an id.')
            }
            $id = [guid]::NewGuid().Guid
        }
        $kind = ConvertTo-RenderKitClientText `
            -Value (Get-RenderKitClientProperty $address kind) `
            -Name AddressKind -MaximumLength 32
        if ([string]::IsNullOrWhiteSpace($kind)) { $kind = 'Other' }
        if (@('Billing', 'Delivery', 'Office', 'Other') -notcontains $kind) {
            throw [System.ArgumentException]::new(
                "Unsupported address kind '$kind'.")
        }
        [PSCustomObject]@{
            id          = $id
            kind        = $kind
            line1       = ConvertTo-RenderKitClientText `
                -Value (Get-RenderKitClientProperty $address line1) `
                -Name AddressLine1 -MaximumLength 255
            line2       = ConvertTo-RenderKitClientText `
                -Value (Get-RenderKitClientProperty $address line2) `
                -Name AddressLine2 -MaximumLength 255
            city        = ConvertTo-RenderKitClientText `
                -Value (Get-RenderKitClientProperty $address city) `
                -Name AddressCity -MaximumLength 128
            region      = ConvertTo-RenderKitClientText `
                -Value (Get-RenderKitClientProperty $address region) `
                -Name AddressRegion -MaximumLength 128
            postalCode  = ConvertTo-RenderKitClientText `
                -Value (Get-RenderKitClientProperty $address postalCode) `
                -Name AddressPostalCode -MaximumLength 32
            countryCode = ConvertTo-RenderKitClientText `
                -Value (Get-RenderKitClientProperty $address countryCode) `
                -Name AddressCountryCode -MaximumLength 2
        }
    })
}

function ConvertTo-RenderKitClientConsent {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return $null }
    $status = ConvertTo-RenderKitClientText `
        -Value (Get-RenderKitClientProperty $Value status) `
        -Name ConsentStatus -MaximumLength 32
    if ([string]::IsNullOrWhiteSpace($status)) { $status = 'Unknown' }
    if (@('Unknown', 'Granted', 'Denied', 'Withdrawn') -notcontains $status) {
        throw [System.ArgumentException]::new(
            "Unsupported consent status '$status'.")
    }
    return [PSCustomObject]@{
        status       = $status
        updatedAtUtc = ConvertTo-RenderKitClientUtcTimestamp `
            -Value (Get-RenderKitClientProperty $Value updatedAtUtc)
        source       = ConvertTo-RenderKitClientText `
            -Value (Get-RenderKitClientProperty $Value source) `
            -Name ConsentSource -MaximumLength 255
    }
}

function ConvertTo-RenderKitClientRetention {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return $null }
    return [PSCustomObject]@{
        policy         = ConvertTo-RenderKitClientText `
            -Value (Get-RenderKitClientProperty $Value policy) `
            -Name RetentionPolicy -MaximumLength 128
        retainUntilUtc = ConvertTo-RenderKitClientUtcTimestamp `
            -Value (Get-RenderKitClientProperty $Value retainUntilUtc)
        legalHold      = [bool](Get-RenderKitClientProperty $Value legalHold)
    }
}

function Get-RenderKitClientProperty {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [System.Collections.IDictionary]) {
        if ($Value.Contains($Name)) {
            return $Value[$Name]
        }
        return $null
    }
    if (
        -not ($Value.PSObject.Properties.Name -contains $Name)) {
        return $null
    }
    return $Value.$Name
}

function ConvertTo-RenderKitClientUtcTimestamp {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Value,
        [string]$DefaultValue
    )

    $text = if ($null -eq $Value) { '' } else { ([string]$Value).Trim() }
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $DefaultValue
    }
    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse(
        $text,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal,
        [ref]$parsed
    )) {
        throw [System.ArgumentException]::new(
            "Timestamp '$text' is not a valid UTC date.")
    }
    return $parsed.ToUniversalTime().ToString('o')
}

function Test-RenderKitClientUtcTimestamp {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return $false
    }
    try {
        ConvertTo-RenderKitClientUtcTimestamp -Value $Value | Out-Null
        return $true
    }
    catch {
        return $false
    }
}
