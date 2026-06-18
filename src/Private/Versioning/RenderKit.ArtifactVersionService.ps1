function Get-RenderKitArtifactVersionCatalog {
    [CmdletBinding()]
    param()

    if ($script:RenderKitArtifactVersionCatalog) {
        return $script:RenderKitArtifactVersionCatalog
    }

    $path = Join-Path -Path $script:RenderKitModuleRoot `
        -ChildPath 'src/Resources/Schemas/ArtifactVersions.psd1'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "RenderKit artifact version catalog was not found at '$path'."
    }

    $catalog = Import-PowerShellDataFile -LiteralPath $path
    if (-not $catalog.Artifacts -or -not $catalog.CatalogVersion) {
        throw "RenderKit artifact version catalog '$path' is invalid."
    }

    $script:RenderKitArtifactVersionCatalog = $catalog
    return $catalog
}

function ConvertTo-RenderKitArtifactVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Version
    )

    $parsed = $null
    if ([string]::IsNullOrWhiteSpace($Version) -or
        -not [version]::TryParse($Version, [ref]$parsed)) {
        throw "Artifact version '$Version' is not a valid numeric version."
    }

    return $parsed
}

function Get-RenderKitArtifactVersionPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ArtifactType
    )

    $catalog = Get-RenderKitArtifactVersionCatalog
    $key = @($catalog.Artifacts.Keys |
        Where-Object { $_ -ieq $ArtifactType } |
        Select-Object -First 1)
    if ($key.Count -eq 0) {
        throw "Unknown RenderKit artifact type '$ArtifactType'."
    }

    $policy = $catalog.Artifacts[$key[0]]
    foreach ($property in @(
        'Current',
        'MinimumReadable',
        'MaximumReadable',
        'MinimumWritable',
        'MaximumWritable'
    )) {
        ConvertTo-RenderKitArtifactVersion -Version $policy[$property] |
            Out-Null
    }

    return [PSCustomObject]@{
        ArtifactType    = [string]$key[0]
        Current         = [string]$policy.Current
        MinimumReadable = [string]$policy.MinimumReadable
        MaximumReadable = [string]$policy.MaximumReadable
        MinimumWritable = [string]$policy.MinimumWritable
        MaximumWritable = [string]$policy.MaximumWritable
    }
}

function Test-RenderKitArtifactCompatibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ArtifactType,

        [Parameter(Mandatory)]
        [string]$Version
    )

    $policy = Get-RenderKitArtifactVersionPolicy -ArtifactType $ArtifactType
    $candidate = ConvertTo-RenderKitArtifactVersion -Version $Version
    $current = ConvertTo-RenderKitArtifactVersion -Version $policy.Current
    $minimumReadable = ConvertTo-RenderKitArtifactVersion `
        -Version $policy.MinimumReadable
    $maximumReadable = ConvertTo-RenderKitArtifactVersion `
        -Version $policy.MaximumReadable
    $minimumWritable = ConvertTo-RenderKitArtifactVersion `
        -Version $policy.MinimumWritable
    $maximumWritable = ConvertTo-RenderKitArtifactVersion `
        -Version $policy.MaximumWritable

    $canRead = $candidate -ge $minimumReadable -and
        $candidate -le $maximumReadable
    $canWrite = $candidate -ge $minimumWritable -and
        $candidate -le $maximumWritable

    if ($candidate -gt $maximumReadable) {
        $status = 'UnsupportedFutureVersion'
    }
    elseif (-not $canRead -or -not $canWrite) {
        $status = 'UpgradeRequired'
    }
    elseif ($candidate -lt $current) {
        $status = 'UpgradeAvailable'
    }
    else {
        $status = 'Current'
    }

    return [PSCustomObject]@{
        ArtifactType      = $policy.ArtifactType
        RequestedVersion  = $candidate.ToString()
        CurrentVersion    = $current.ToString()
        Status            = $status
        CanRead           = $canRead
        CanWrite          = $canWrite
        MigrationRequired = -not $canWrite
        IsFutureVersion   = $candidate -gt $current
    }
}

function Register-RenderKitArtifactMigration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ArtifactType,
        [Parameter(Mandatory)]
        [string]$FromVersion,
        [Parameter(Mandatory)]
        [string]$ToVersion,
        [Parameter(Mandatory)]
        [scriptblock]$Migration
    )

    $policy = Get-RenderKitArtifactVersionPolicy -ArtifactType $ArtifactType
    $from = (ConvertTo-RenderKitArtifactVersion $FromVersion).ToString()
    $to = (ConvertTo-RenderKitArtifactVersion $ToVersion).ToString()
    if ([version]$to -le [version]$from) {
        throw 'Artifact migrations must move to a newer version.'
    }

    if (-not $script:RenderKitArtifactMigrations) {
        $script:RenderKitArtifactMigrations = @{}
    }
    if (-not $script:RenderKitArtifactMigrations.ContainsKey($policy.ArtifactType)) {
        $script:RenderKitArtifactMigrations[$policy.ArtifactType] = @{}
    }

    $key = "$from->$to"
    $script:RenderKitArtifactMigrations[$policy.ArtifactType][$key] = @{
        FromVersion = $from
        ToVersion = $to
        Migration = $Migration
    }
}

function Get-RenderKitArtifactMigrationPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ArtifactType,
        [Parameter(Mandatory)]
        [string]$FromVersion,
        [string]$ToVersion
    )

    $policy = Get-RenderKitArtifactVersionPolicy -ArtifactType $ArtifactType
    $from = (ConvertTo-RenderKitArtifactVersion $FromVersion).ToString()
    if ([string]::IsNullOrWhiteSpace($ToVersion)) {
        $ToVersion = $policy.Current
    }
    $to = (ConvertTo-RenderKitArtifactVersion $ToVersion).ToString()
    if ($from -eq $to) {
        return @()
    }

    $migrations = @{}
    if ($script:RenderKitArtifactMigrations -and
        $script:RenderKitArtifactMigrations.ContainsKey($policy.ArtifactType)) {
        $migrations = $script:RenderKitArtifactMigrations[$policy.ArtifactType]
    }

    $queue = [System.Collections.Queue]::new()
    $queue.Enqueue(@{ Version = $from; Path = @() })
    $visited = @{ $from = $true }
    while ($queue.Count -gt 0) {
        $item = $queue.Dequeue()
        foreach ($migration in $migrations.Values |
            Where-Object { $_.FromVersion -eq $item.Version } |
            Sort-Object { [version]$_.ToVersion }) {
            $path = @($item.Path) + @([PSCustomObject]$migration)
            if ($migration.ToVersion -eq $to) {
                return $path
            }
            if (-not $visited.ContainsKey($migration.ToVersion)) {
                $visited[$migration.ToVersion] = $true
                $queue.Enqueue(@{
                    Version = $migration.ToVersion
                    Path = $path
                })
            }
        }
    }

    return @()
}
