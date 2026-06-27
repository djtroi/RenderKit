function Get-BackupBuiltInConfigProfileCatalog {
    [CmdletBinding()]
    param()

    if ($script:RenderKitBackupConfigProfiles) {
        return $script:RenderKitBackupConfigProfiles
    }

    $script:RenderKitBackupConfigProfiles = [ordered]@{
        'fastest' = [PSCustomObject]@{
            name               = 'fastest'
            displayName        = 'Fastest'
            description        = 'Prioritizes short processing time with hardware-assisted H.264 encoding.'
            intent             = 'FastMediaBackup'
            schemaVersion      = '1.0'
            profileVersion     = '1.0.0'
            source             = 'BuiltIn'
            requiresBackground = $true
            settings           = [PSCustomObject][ordered]@{
                ArchiveFormat           = 'Zip'
                CompressionMode         = 'TranscodeAndArchive'
                CompressionPreset       = 'Fastest'
                VideoCodec              = 'H264'
                EncoderDevice           = 'Auto'
                QualityPreset           = 'Draft'
                AudioProfile            = 'AAC_128'
                CreateProxy             = $false
                CreatePreview           = $false
                DisableChunking         = $false
                ChunkDurationSeconds    = 300
                MaxParallelJobs         = 4
                MaxCpuPercent           = 90
                MaxGpuPercent           = 95
                MaxDiskActivePercent    = 90
                KeepSourceProject       = $false
                MaxChunkRetryAttempts   = 3
                ChunkRetryDelaySeconds  = 1
            }
        }
        'balanced' = [PSCustomObject]@{
            name               = 'balanced'
            displayName        = 'Balanced'
            description        = 'Balances processing time, visual quality, and storage reduction.'
            intent             = 'BalancedMediaBackup'
            schemaVersion      = '1.0'
            profileVersion     = '1.0.0'
            source             = 'BuiltIn'
            requiresBackground = $true
            settings           = [PSCustomObject][ordered]@{
                ArchiveFormat           = 'Zip'
                CompressionMode         = 'TranscodeAndArchive'
                CompressionPreset       = 'Balanced'
                VideoCodec              = 'Auto'
                EncoderDevice           = 'Auto'
                QualityPreset           = 'Balanced'
                AudioProfile            = 'Auto'
                CreateProxy             = $false
                CreatePreview           = $false
                DisableChunking         = $false
                ChunkDurationSeconds    = 600
                MaxParallelJobs         = 2
                MaxCpuPercent           = 85
                MaxGpuPercent           = 90
                MaxDiskActivePercent    = 85
                KeepSourceProject       = $false
                MaxChunkRetryAttempts   = 3
                ChunkRetryDelaySeconds  = 2
            }
        }
        'smallest' = [PSCustomObject]@{
            name               = 'smallest'
            displayName        = 'Smallest'
            description        = 'Prioritizes minimum output size with AV1, Opus, and SevenZip.'
            intent             = 'MinimumStorage'
            schemaVersion      = '1.0'
            profileVersion     = '1.0.0'
            source             = 'BuiltIn'
            requiresBackground = $true
            settings           = [PSCustomObject][ordered]@{
                ArchiveFormat           = 'SevenZip'
                CompressionMode         = 'TranscodeAndArchive'
                CompressionPreset       = 'Smallest'
                VideoCodec              = 'AV1'
                EncoderDevice           = 'Auto'
                QualityPreset           = 'Smallest'
                AudioProfile            = 'Opus_96'
                CreateProxy             = $false
                CreatePreview           = $false
                DisableChunking         = $false
                ChunkDurationSeconds    = 600
                MaxParallelJobs         = 1
                MaxCpuPercent           = 90
                MaxGpuPercent           = 95
                MaxDiskActivePercent    = 80
                KeepSourceProject       = $false
                MaxChunkRetryAttempts   = 4
                ChunkRetryDelaySeconds  = 3
            }
        }
        'archive-safe' = [PSCustomObject]@{
            name               = 'archive-safe'
            displayName        = 'Archive Safe'
            description        = 'Preserves source media without transcoding and keeps the source project.'
            intent             = 'PreservationArchive'
            schemaVersion      = '1.0'
            profileVersion     = '1.0.0'
            source             = 'BuiltIn'
            requiresBackground = $true
            settings           = [PSCustomObject][ordered]@{
                ArchiveFormat           = 'TarZstd'
                CompressionMode         = 'ArchiveOnly'
                CompressionPreset       = 'Lossless'
                VideoCodec              = 'Auto'
                EncoderDevice           = 'Auto'
                QualityPreset           = 'Lossless'
                AudioProfile            = 'Copy'
                CreateProxy             = $false
                CreatePreview           = $false
                DisableChunking         = $true
                ChunkDurationSeconds    = 600
                MaxParallelJobs         = 2
                MaxCpuPercent           = 80
                MaxGpuPercent           = 80
                MaxDiskActivePercent    = 80
                KeepSourceProject       = $true
                MaxChunkRetryAttempts   = 5
                ChunkRetryDelaySeconds  = 5
            }
        }
        'proxy-only' = [PSCustomObject]@{
            name               = 'proxy-only'
            displayName        = 'Proxy Only'
            description        = 'Creates compact 720p H.264 proxy media instead of full-resolution archive encodes.'
            intent             = 'ProxyMedia'
            schemaVersion      = '1.0'
            profileVersion     = '1.0.0'
            source             = 'BuiltIn'
            requiresBackground = $true
            settings           = [PSCustomObject][ordered]@{
                ArchiveFormat           = 'Zip'
                CompressionMode         = 'ProxyOnly'
                CompressionPreset       = 'Fastest'
                VideoCodec              = 'H264'
                EncoderDevice           = 'Auto'
                QualityPreset           = 'Draft'
                AudioProfile            = 'AAC_128'
                CreateProxy             = $false
                CreatePreview           = $true
                DisableChunking         = $false
                ChunkDurationSeconds    = 300
                MaxParallelJobs         = 4
                MaxCpuPercent           = 85
                MaxGpuPercent           = 90
                MaxDiskActivePercent    = 85
                KeepSourceProject       = $true
                MaxChunkRetryAttempts   = 3
                ChunkRetryDelaySeconds  = 1
            }
        }
        'no-transcode' = [PSCustomObject]@{
            name               = 'no-transcode'
            displayName        = 'No Transcode'
            description        = 'Archives original project files without media transcoding.'
            intent             = 'OriginalMediaArchive'
            schemaVersion      = '1.0'
            profileVersion     = '1.0.0'
            source             = 'BuiltIn'
            requiresBackground = $false
            settings           = [PSCustomObject][ordered]@{
                ArchiveFormat           = 'Zip'
                CompressionMode         = 'ArchiveOnly'
                CompressionPreset       = 'Balanced'
                VideoCodec              = 'Auto'
                EncoderDevice           = 'Auto'
                QualityPreset           = 'Balanced'
                AudioProfile            = 'Auto'
                CreateProxy             = $false
                CreatePreview           = $false
                DisableChunking         = $false
                ChunkDurationSeconds    = 600
                MaxParallelJobs         = 1
                MaxCpuPercent           = 90
                MaxGpuPercent           = 95
                MaxDiskActivePercent    = 90
                KeepSourceProject       = $false
                MaxChunkRetryAttempts   = 3
                ChunkRetryDelaySeconds  = 1
            }
        }
    }

    return $script:RenderKitBackupConfigProfiles
}

function Resolve-BackupConfigProfileName {
    [CmdletBinding()]
    param(
        [string]$Name = 'no-transcode'
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $Name = 'no-transcode'
    }

    $normalized = $Name.Trim().ToLowerInvariant() -replace '[^a-z0-9]', ''
    $canonicalName = switch ($normalized) {
        'fastest' { 'fastest' }
        'balanced' { 'balanced' }
        'smallest' { 'smallest' }
        'archivesafe' { 'archive-safe' }
        'archive' { 'archive-safe' }
        'safe' { 'archive-safe' }
        'proxyonly' { 'proxy-only' }
        'proxy' { 'proxy-only' }
        'notranscode' { 'no-transcode' }
        'originals' { 'no-transcode' }
        default { $null }
    }

    if (-not $canonicalName) {
        $available = @((Get-BackupBuiltInConfigProfileCatalog).Keys) -join ', '
        throw "Unknown backup config profile '$Name'. Available profiles: $available."
    }

    return $canonicalName
}

function Get-BackupConfigProfileDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $canonicalName = Resolve-BackupConfigProfileName -Name $Name
    return (Get-BackupBuiltInConfigProfileCatalog)[$canonicalName]
}

function Copy-BackupConfigProfileSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Settings
    )

    $copy = [ordered]@{}
    foreach ($property in $Settings.PSObject.Properties) {
        $copy[[string]$property.Name] = $property.Value
    }
    return [PSCustomObject]$copy
}

function Resolve-BackupConfigProfile {
    [CmdletBinding()]
    param(
        [string]$Name = 'no-transcode',
        [string[]]$ExplicitParameters = @()
    )

    $definition = Get-BackupConfigProfileDefinition -Name $Name
    $settings = Copy-BackupConfigProfileSettings -Settings $definition.settings
    $settingNames = @($settings.PSObject.Properties.Name)
    $overridden = @(
        $ExplicitParameters |
            Where-Object { $settingNames -contains [string]$_ } |
            Sort-Object -Unique
    )

    return [PSCustomObject]@{
        schemaVersion       = [string]$definition.schemaVersion
        name                = [string]$definition.name
        displayName         = [string]$definition.displayName
        description         = [string]$definition.description
        intent              = [string]$definition.intent
        profileVersion      = [string]$definition.profileVersion
        source              = [string]$definition.source
        requiresBackground  = [bool]$definition.requiresBackground
        settings            = $settings
        appliedParameters   = @(
            $settingNames |
                Where-Object { $overridden -notcontains $_ }
        )
        overriddenParameters = @($overridden)
        effectiveSettings   = $null
    }
}

function Complete-BackupConfigProfileResolution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Resolution,
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$EffectiveSettings
    )

    $effective = [PSCustomObject][ordered]@{}
    foreach ($property in $Resolution.settings.PSObject.Properties) {
        if ($EffectiveSettings.Contains($property.Name)) {
            $effective |
                Add-Member `
                    -NotePropertyName $property.Name `
                    -NotePropertyValue $EffectiveSettings[$property.Name]
        }
    }

    $requiresBackground = (
        [string]$effective.ArchiveFormat -ne 'Zip' -or
        [string]$effective.CompressionMode -in @(
            'TranscodeAndArchive',
            'ProxyOnly',
            'CopyOnly'
        )
    )

    $Resolution.effectiveSettings = $effective
    $Resolution.requiresBackground = [bool]$requiresBackground
    return $Resolution
}
