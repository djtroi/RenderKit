function Get-RenderKitCurrentModuleVersion {
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    $loadedModule = Get-Module -Name RenderKit | Select-Object -First 1
    if ($loadedModule -and $loadedModule.Version) {
        return $loadedModule.Version.ToString()
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$script:RenderKitModuleVersion) -and
        [version]$script:RenderKitModuleVersion -gt [version]'0.0.0') {
        return [string]$script:RenderKitModuleVersion
    }

    $manifestPath = Join-Path -Path $script:RenderKitModuleRoot -ChildPath 'RenderKit.psd1'
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        return ([version](Import-PowerShellDataFile -LiteralPath $manifestPath).ModuleVersion).ToString()
    }
    return '0.0.0'
}

function ConvertTo-BackupConfigProfileName {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $normalized = $Name.Trim().ToLowerInvariant()
    $normalized = $normalized -replace '[\s_]+', '-'
    $normalized = $normalized -replace '[^a-z0-9-]', ''
    $normalized = $normalized -replace '-{2,}', '-'
    $normalized = $normalized.Trim('-')
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        throw "Backup config profile name '$Name' does not contain a usable identifier."
    }
    return $normalized
}

function Get-BackupConfigProfileSettingSchema {
    [CmdletBinding()]
    param()

    return [ordered]@{
        ArchiveFormat = [PSCustomObject]@{
            type = 'String'; validValues = @('Zip', 'SevenZip', 'TarZstd', 'Folder')
        }
        CompressionMode = [PSCustomObject]@{
            type = 'String'; validValues = @('ArchiveOnly', 'TranscodeAndArchive', 'ProxyOnly', 'CopyOnly')
        }
        CompressionPreset = [PSCustomObject]@{
            type = 'String'; validValues = @('Fastest', 'Balanced', 'Smallest', 'Lossless')
        }
        VideoCodec = [PSCustomObject]@{
            type = 'String'; validValues = @('Auto', 'H264', 'H265', 'AV1')
        }
        EncoderDevice = [PSCustomObject]@{
            type = 'String'; validValues = @('Auto', 'CPU', 'Nvidia', 'IntelQuickSync', 'AMD')
        }
        QualityPreset = [PSCustomObject]@{
            type = 'String'; validValues = @('Draft', 'Balanced', 'High', 'Smallest', 'Lossless')
        }
        AudioProfile = [PSCustomObject]@{
            type = 'String'; validValues = @('Auto', 'AAC_128', 'AAC_192', 'Opus_96', 'Opus_128', 'Copy', 'Lossless')
        }
        EncoderAdapter = [PSCustomObject]@{
            type = 'String'; validValues = @()
        }
        VerifierAdapter = [PSCustomObject]@{
            type = 'String'; validValues = @()
        }
        NotifierAdapter = [PSCustomObject]@{
            type = 'StringArray'; validValues = @()
        }
        CreateProxy = [PSCustomObject]@{
            type = 'Boolean'; validValues = @()
        }
        CreatePreview = [PSCustomObject]@{
            type = 'Boolean'; validValues = @()
        }
        DisableChunking = [PSCustomObject]@{
            type = 'Boolean'; validValues = @()
        }
        ChunkDurationSeconds = [PSCustomObject]@{
            type = 'Integer'; minimum = 10; maximum = 86400; validValues = @()
        }
        MaxParallelJobs = [PSCustomObject]@{
            type = 'Integer'; minimum = 1; maximum = 64; validValues = @()
        }
        MaxCpuPercent = [PSCustomObject]@{
            type = 'Integer'; minimum = 1; maximum = 100; validValues = @()
        }
        MaxGpuPercent = [PSCustomObject]@{
            type = 'Integer'; minimum = 1; maximum = 100; validValues = @()
        }
        MaxDiskActivePercent = [PSCustomObject]@{
            type = 'Integer'; minimum = 1; maximum = 100; validValues = @()
        }
        KeepSourceProject = [PSCustomObject]@{
            type = 'Boolean'; validValues = @()
        }
        MaxChunkRetryAttempts = [PSCustomObject]@{
            type = 'Integer'; minimum = 1; maximum = 20; validValues = @()
        }
        ChunkRetryDelaySeconds = [PSCustomObject]@{
            type = 'Integer'; minimum = 0; maximum = 3600; validValues = @()
        }
    }
}

function ConvertTo-BackupConfigProfileSettingValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [AllowNull()]
        [object]$Value
    )

    $schema = Get-BackupConfigProfileSettingSchema
    if (-not $schema.Contains($Name)) {
        throw "Unknown backup config profile setting '$Name'."
    }
    $rule = $schema[$Name]
    switch ([string]$rule.type) {
        'Boolean' {
            if ($Value -is [bool]) {
                return [bool]$Value
            }
            $text = [string]$Value
            if ($text -match '^(?i:true|yes|y|1|on)$') { return $true }
            if ($text -match '^(?i:false|no|n|0|off)$') { return $false }
            throw "Setting '$Name' expects a boolean value."
        }
        'Integer' {
            $number = 0
            if (-not [int]::TryParse([string]$Value, [ref]$number)) {
                throw "Setting '$Name' expects an integer value."
            }
            if ($number -lt [int]$rule.minimum -or $number -gt [int]$rule.maximum) {
                throw "Setting '$Name' must be between $($rule.minimum) and $($rule.maximum)."
            }
            return $number
        }
        'StringArray' {
            $values = @(
                if ($Value -is [string]) {
                    ([string]$Value).Split(',') |
                        ForEach-Object { $_.Trim() }
                }
                else {
                    @($Value) | ForEach-Object { ([string]$_).Trim() }
                }
            ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            if ($values.Count -eq 0) {
                throw "Setting '$Name' requires at least one value."
            }
            return @($values)
        }
        default {
            $text = ([string]$Value).Trim()
            if ([string]::IsNullOrWhiteSpace($text)) {
                throw "Setting '$Name' must not be empty."
            }
            if (@($rule.validValues).Count -gt 0) {
                $canonical = @(
                    $rule.validValues |
                        Where-Object { [string]::Equals([string]$_, $text, [System.StringComparison]::OrdinalIgnoreCase) } |
                        Select-Object -First 1
                )
                if ($canonical.Count -eq 0) {
                    throw "Setting '$Name' must be one of: $($rule.validValues -join ', ')."
                }
                return [string]$canonical[0]
            }
            return $text
        }
    }
}

function ConvertTo-BackupConfigProfileSettingsDictionary {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Settings
    )

    $dictionary = [ordered]@{}
    if ($null -eq $Settings) {
        return $dictionary
    }
    if ($Settings -is [System.Collections.IDictionary]) {
        foreach ($entry in $Settings.GetEnumerator()) {
            $dictionary[[string]$entry.Key] = $entry.Value
        }
    }
    else {
        foreach ($property in $Settings.PSObject.Properties) {
            $dictionary[[string]$property.Name] = $property.Value
        }
    }
    return $dictionary
}

function Merge-BackupConfigProfileSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$BaseSettings,
        [AllowNull()]
        [object]$Overrides
    )

    $schema = Get-BackupConfigProfileSettingSchema
    $base = ConvertTo-BackupConfigProfileSettingsDictionary -Settings $BaseSettings
    $overrideDictionary = ConvertTo-BackupConfigProfileSettingsDictionary -Settings $Overrides
    $unknown = @($overrideDictionary.Keys | Where-Object { -not $schema.Contains([string]$_) })
    if ($unknown.Count -gt 0) {
        throw "Unknown backup config profile setting(s): $($unknown -join ', ')."
    }

    $merged = [ordered]@{}
    foreach ($settingName in $schema.Keys) {
        $value = if ($overrideDictionary.Contains($settingName)) {
            $overrideDictionary[$settingName]
        }
        elseif ($base.Contains($settingName)) {
            $base[$settingName]
        }
        else {
            throw "Base profile is missing required setting '$settingName'."
        }
        $merged[$settingName] = ConvertTo-BackupConfigProfileSettingValue `
            -Name $settingName `
            -Value $value
    }
    return [PSCustomObject]$merged
}

function Test-BackupConfigProfileSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Settings,
        [switch]$CheckAdapters
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $normalized = $null
    try {
        $normalized = Merge-BackupConfigProfileSettings `
            -BaseSettings $Settings `
            -Overrides @{}
    }
    catch {
        $errors.Add($_.Exception.Message)
    }

    if ($normalized) {
        if ([string]$normalized.CompressionMode -eq 'ProxyOnly' -and
            [string]$normalized.VideoCodec -notin @('Auto', 'H264')) {
            $errors.Add('ProxyOnly profiles must use H264 or Auto video codec.')
        }
        if ([string]$normalized.CompressionPreset -eq 'Lossless' -and
            [string]$normalized.QualityPreset -ne 'Lossless') {
            $warnings.Add('Lossless compression is paired with a non-lossless quality preset.')
        }
        if ($CheckAdapters) {
            foreach ($adapterCheck in @(
                    [PSCustomObject]@{ Type = 'Encoder'; Name = [string]$normalized.EncoderAdapter }
                    [PSCustomObject]@{ Type = 'Verifier'; Name = [string]$normalized.VerifierAdapter }
                )) {
                if (-not (Get-BackupAdapterDefinition -Type $adapterCheck.Type -Name $adapterCheck.Name)) {
                    $warnings.Add("$($adapterCheck.Type) adapter '$($adapterCheck.Name)' is not registered.")
                }
            }
            foreach ($notifier in @($normalized.NotifierAdapter)) {
                if (-not (Get-BackupAdapterDefinition -Type Notifier -Name ([string]$notifier))) {
                    $warnings.Add("Notifier adapter '$notifier' is not registered.")
                }
            }
        }
    }

    return [PSCustomObject]@{
        isValid            = $errors.Count -eq 0
        errors             = @($errors.ToArray())
        warnings           = @($warnings.ToArray())
        normalizedSettings = $normalized
    }
}

function Initialize-BackupConfigProfileMigrations {
    [CmdletBinding()]
    param()

    if ($script:RenderKitBackupConfigProfileMigrationsInitialized) {
        return
    }

    Register-RenderKitArtifactMigration `
        -ArtifactType BackupConfigProfile `
        -FromVersion '1.0' `
        -ToVersion '1.1' `
        -Migration {
            param($Value)

            $baseName = if ($Value.PSObject.Properties.Name -contains 'baseProfile' -and
                -not [string]::IsNullOrWhiteSpace([string]$Value.baseProfile)) {
                [string]$Value.baseProfile
            }
            else {
                'no-transcode'
            }
            $builtInCatalog = Get-BackupBuiltInConfigProfileCatalog
            if (-not $builtInCatalog.Contains($baseName)) {
                $baseName = 'no-transcode'
            }
            $Value.settings = Merge-BackupConfigProfileSettings `
                -BaseSettings $builtInCatalog[$baseName].settings `
                -Overrides $Value.settings
            $now = (Get-Date).ToUniversalTime().ToString('o')
            if ($Value.PSObject.Properties.Name -notcontains 'kind') {
                $Value | Add-Member -NotePropertyName kind -NotePropertyValue 'RenderKit.BackupConfigProfile'
            }
            if ($Value.PSObject.Properties.Name -notcontains 'source') {
                $Value | Add-Member -NotePropertyName source -NotePropertyValue 'User'
            }
            if ($Value.PSObject.Properties.Name -notcontains 'createdWith') {
                $Value |
                    Add-Member `
                        -NotePropertyName createdWith `
                        -NotePropertyValue ([PSCustomObject]@{
                            moduleVersion = Get-RenderKitCurrentModuleVersion
                        })
            }
            if ($Value.PSObject.Properties.Name -notcontains 'compatibility') {
                $Value |
                    Add-Member `
                        -NotePropertyName compatibility `
                        -NotePropertyValue ([PSCustomObject]@{
                            minimumModuleVersion = '1.0.0'
                            previousSchemaVersion = '1.0'
                            lastUpgradedAtUtc = $now
                        })
            }
            if ($Value.PSObject.Properties.Name -notcontains 'revision') {
                $Value |
                    Add-Member `
                        -NotePropertyName revision `
                        -NotePropertyValue ([PSCustomObject]@{
                            generation = 1
                            createdAtUtc = $now
                            updatedAtUtc = $now
                        })
            }
            $Value.schemaVersion = '1.1'
            return $Value
        }
    $script:RenderKitBackupConfigProfileMigrationsInitialized = $true
}

function ConvertTo-BackupConfigProfileCurrentSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Profile
    )

    Initialize-BackupConfigProfileMigrations
    $schemaVersion = if ($Profile.PSObject.Properties.Name -contains 'schemaVersion') {
        [string]$Profile.schemaVersion
    }
    else {
        '1.0'
    }
    $compatibility = Test-RenderKitArtifactCompatibility `
        -ArtifactType BackupConfigProfile `
        -Version $schemaVersion
    if (-not [bool]$compatibility.CanRead) {
        throw "Backup config profile schema '$schemaVersion' is not readable by this RenderKit version."
    }
    if ([string]$compatibility.Status -eq 'Current') {
        return $Profile
    }

    $path = @(
        Get-RenderKitArtifactMigrationPath `
            -ArtifactType BackupConfigProfile `
            -FromVersion $schemaVersion
    )
    if ($path.Count -eq 0) {
        throw "No BackupConfigProfile migration path exists from schema '$schemaVersion'."
    }
    $migrated = $Profile
    foreach ($migration in $path) {
        $migrated = & $migration.Migration $migrated
    }
    return $migrated
}

function Test-BackupConfigProfileDocumentDetailed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Profile,
        [switch]$CheckAdapters
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    if ([string]$Profile.kind -ne 'RenderKit.BackupConfigProfile') {
        $errors.Add("Profile kind must be 'RenderKit.BackupConfigProfile'.")
    }
    try {
        $canonicalName = ConvertTo-BackupConfigProfileName -Name ([string]$Profile.name)
        if ($canonicalName -ne [string]$Profile.name) {
            $errors.Add("Profile name must use canonical form '$canonicalName'.")
        }
    }
    catch {
        $errors.Add($_.Exception.Message)
    }
    try {
        [void][version]([string]$Profile.profileVersion)
    }
    catch {
        $errors.Add("Profile version '$($Profile.profileVersion)' is invalid.")
    }

    $artifactCompatibility = $null
    try {
        $artifactCompatibility = Test-RenderKitArtifactCompatibility `
            -ArtifactType BackupConfigProfile `
            -Version ([string]$Profile.schemaVersion)
        if (-not [bool]$artifactCompatibility.CanRead) {
            $errors.Add("Schema version '$($Profile.schemaVersion)' is not readable.")
        }
        elseif ([string]$artifactCompatibility.Status -eq 'UpgradeAvailable') {
            $warnings.Add("Schema version '$($Profile.schemaVersion)' can be upgraded to '$($artifactCompatibility.CurrentVersion)'.")
        }
    }
    catch {
        $errors.Add($_.Exception.Message)
    }

    $settingsValidation = if ($Profile.PSObject.Properties.Name -contains 'settings' -and $Profile.settings) {
        Test-BackupConfigProfileSettings `
            -Settings $Profile.settings `
            -CheckAdapters:$CheckAdapters
    }
    else {
        [PSCustomObject]@{
            isValid = $false
            errors = @('Profile does not contain settings.')
            warnings = @()
            normalizedSettings = $null
        }
    }
    foreach ($errorMessage in @($settingsValidation.errors)) {
        $errors.Add([string]$errorMessage)
    }
    foreach ($warningMessage in @($settingsValidation.warnings)) {
        $warnings.Add([string]$warningMessage)
    }

    $minimumModuleVersion = if ($Profile.compatibility -and
        $Profile.compatibility.PSObject.Properties.Name -contains 'minimumModuleVersion') {
        [string]$Profile.compatibility.minimumModuleVersion
    }
    else {
        '1.0.0'
    }
    try {
        if ([version](Get-RenderKitCurrentModuleVersion) -lt [version]$minimumModuleVersion) {
            $errors.Add("Profile requires RenderKit module $minimumModuleVersion or newer.")
        }
    }
    catch {
        $errors.Add("Profile minimum module version '$minimumModuleVersion' is invalid.")
    }

    return [PSCustomObject]@{
        isValid              = $errors.Count -eq 0
        name                 = [string]$Profile.name
        schemaVersion        = [string]$Profile.schemaVersion
        profileVersion       = [string]$Profile.profileVersion
        compatibility        = $artifactCompatibility
        errors               = @($errors.ToArray())
        warnings             = @($warnings.ToArray())
        normalizedSettings   = $settingsValidation.normalizedSettings
    }
}

function Test-BackupConfigProfileDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Profile
    )

    return [bool](Test-BackupConfigProfileDocumentDetailed -Profile $Profile).isValid
}

function Get-BackupUserConfigProfileByName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [switch]$AllowMissing,
        [switch]$Raw
    )

    $canonicalName = ConvertTo-BackupConfigProfileName -Name $Name
    $path = Get-RenderKitBackupConfigProfilePath -Name $canonicalName
    $profile = Read-RenderKitJsonFile -Path $path -AllowMissing:$AllowMissing
    if (-not $profile) {
        return $null
    }
    if ($Raw) {
        return $profile
    }

    $profile = ConvertTo-BackupConfigProfileCurrentSchema -Profile $profile
    $validation = Test-BackupConfigProfileDocumentDetailed -Profile $profile
    if (-not [bool]$validation.isValid) {
        throw "Backup config profile '$canonicalName' is invalid: $($validation.errors -join '; ')"
    }
    $profile.settings = $validation.normalizedSettings
    $profile |
        Add-Member -NotePropertyName path -NotePropertyValue $path -Force
    $profile |
        Add-Member -NotePropertyName requiresBackground -NotePropertyValue (
            [string]$profile.settings.ArchiveFormat -ne 'Zip' -or
            [string]$profile.settings.CompressionMode -in @('TranscodeAndArchive', 'ProxyOnly', 'CopyOnly')
        ) -Force
    return $profile
}

function Get-BackupUserConfigProfileList {
    [CmdletBinding()]
    param()

    $root = Get-RenderKitBackupConfigProfilesRoot
    $profiles = New-Object System.Collections.Generic.List[object]
    foreach ($file in @(Get-ChildItem -LiteralPath $root -File -Filter '*.rkprofile.json' | Sort-Object Name)) {
        try {
            $profile = Get-BackupUserConfigProfileByName `
                -Name ($file.Name -replace '\.rkprofile\.json$', '')
            if ($profile) {
                $profiles.Add($profile)
            }
        }
        catch {
            Write-Warning "Skipping invalid backup config profile '$($file.FullName)': $($_.Exception.Message)"
        }
    }
    return @($profiles.ToArray())
}

function Save-BackupUserConfigProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Profile
    )

    $Profile = ConvertTo-BackupConfigProfileCurrentSchema -Profile $Profile
    $validation = Test-BackupConfigProfileDocumentDetailed -Profile $Profile
    if (-not [bool]$validation.isValid) {
        throw "Backup config profile '$($Profile.name)' is invalid: $($validation.errors -join '; ')"
    }
    $Profile.settings = $validation.normalizedSettings
    foreach ($transientProperty in @('path', 'requiresBackground', 'export')) {
        if ($Profile.PSObject.Properties.Name -contains $transientProperty) {
            $Profile.PSObject.Properties.Remove($transientProperty)
        }
    }
    $path = Get-RenderKitBackupConfigProfilePath -Name ([string]$Profile.name)
    Write-RenderKitJsonFileAtomic `
        -Value $Profile `
        -Path $path `
        -Depth 30 `
        -Validator { param($value) Test-BackupConfigProfileDocument -Profile $value } |
        Out-Null
    return Get-BackupUserConfigProfileByName -Name ([string]$Profile.name)
}

function New-BackupUserConfigProfileDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [string]$DisplayName,
        [string]$Description,
        [string]$BaseProfile = 'balanced',
        [string]$ProfileVersion = '1.0.0',
        [object]$Settings,
        [string[]]$Tags = @(),
        [string]$Author
    )

    $canonicalName = ConvertTo-BackupConfigProfileName -Name $Name
    if ((Get-BackupBuiltInConfigProfileCatalog).Contains($canonicalName)) {
        throw "User profile name '$canonicalName' conflicts with a built-in profile."
    }
    [void][version]$ProfileVersion
    $baseDefinition = Get-BackupConfigProfileDefinition -Name $BaseProfile
    $mergedSettings = Merge-BackupConfigProfileSettings `
        -BaseSettings $baseDefinition.settings `
        -Overrides $Settings
    $now = (Get-Date).ToUniversalTime().ToString('o')
    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        $DisplayName = $Name.Trim()
    }

    return [PSCustomObject]@{
        kind           = 'RenderKit.BackupConfigProfile'
        schemaVersion  = '1.1'
        name           = $canonicalName
        displayName    = $DisplayName
        description    = $Description
        intent         = 'UserDefined'
        profileVersion = ([version]$ProfileVersion).ToString()
        source         = 'User'
        baseProfile    = [string]$baseDefinition.name
        settings       = $mergedSettings
        tags           = @($Tags | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)
        author         = $Author
        createdWith    = [PSCustomObject]@{
            moduleVersion = Get-RenderKitCurrentModuleVersion
        }
        compatibility  = [PSCustomObject]@{
            minimumModuleVersion  = '1.0.0'
            previousSchemaVersion = $null
            lastUpgradedAtUtc      = $null
        }
        revision       = [PSCustomObject]@{
            generation   = 1
            createdAtUtc = $now
            updatedAtUtc = $now
        }
    }
}

function Get-NextBackupConfigProfileVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Version,
        [ValidateSet('None', 'Patch', 'Minor', 'Major')]
        [string]$Bump = 'Patch'
    )

    $current = [version]$Version
    switch ($Bump) {
        'None' { return $current.ToString() }
        'Major' { return ([version]::new($current.Major + 1, 0, 0)).ToString() }
        'Minor' { return ([version]::new($current.Major, $current.Minor + 1, 0)).ToString() }
        default {
            $build = if ($current.Build -lt 0) { 0 } else { $current.Build }
            return ([version]::new($current.Major, $current.Minor, $build + 1)).ToString()
        }
    }
}

function Read-BackupConfigProfileInteractiveSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$BaseSettings
    )

    $schema = Get-BackupConfigProfileSettingSchema
    $settings = [ordered]@{}
    foreach ($settingName in $schema.Keys) {
        $currentValue = $BaseSettings.$settingName
        $displayValue = if ($schema[$settingName].type -eq 'StringArray') {
            @($currentValue) -join ','
        }
        else {
            [string]$currentValue
        }
        $answer = Read-Host "$settingName [$displayValue]"
        if ([string]::IsNullOrWhiteSpace($answer)) {
            $settings[$settingName] = $currentValue
        }
        else {
            $settings[$settingName] = ConvertTo-BackupConfigProfileSettingValue `
                -Name $settingName `
                -Value $answer
        }
    }
    return [PSCustomObject]$settings
}

function Update-BackupConfigProfileToCurrentVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Profile
    )

    $previousSchema = [string]$Profile.schemaVersion
    $Profile = ConvertTo-BackupConfigProfileCurrentSchema -Profile $Profile
    $baseName = if ([string]::IsNullOrWhiteSpace([string]$Profile.baseProfile)) {
        'no-transcode'
    }
    else {
        [string]$Profile.baseProfile
    }
    $baseDefinition = Get-BackupConfigProfileDefinition -Name $baseName
    $Profile.settings = Merge-BackupConfigProfileSettings `
        -BaseSettings $baseDefinition.settings `
        -Overrides $Profile.settings
    $now = (Get-Date).ToUniversalTime().ToString('o')
    $Profile.schemaVersion = '1.1'
    $Profile.createdWith.moduleVersion = Get-RenderKitCurrentModuleVersion
    $Profile.compatibility.previousSchemaVersion = $previousSchema
    $Profile.compatibility.lastUpgradedAtUtc = $now
    $Profile.revision.generation = [int]$Profile.revision.generation + 1
    $Profile.revision.updatedAtUtc = $now
    return $Profile
}
