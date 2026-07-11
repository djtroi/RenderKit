function Get-BackupAdapterContractCatalog {
    [CmdletBinding()]
    param()

    return [ordered]@{
        Storage = [PSCustomObject]@{
            type               = 'Storage'
            contractVersion    = '1.0'
            requiredOperations = @('TestHealth', 'Write')
            optionalOperations = @('Read', 'Remove', 'List')
        }
        Encoder = [PSCustomObject]@{
            type               = 'Encoder'
            contractVersion    = '1.0'
            requiredOperations = @('ResolveProfile', 'BuildCommand')
            optionalOperations = @('TestCapability', 'ReadProgress')
        }
        Verifier = [PSCustomObject]@{
            type               = 'Verifier'
            contractVersion    = '1.0'
            requiredOperations = @('Verify')
            optionalOperations = @('TestCapability')
        }
        Notifier = [PSCustomObject]@{
            type               = 'Notifier'
            contractVersion    = '1.0'
            requiredOperations = @('Notify')
            optionalOperations = @('TestConnection')
        }
    }
}

function New-BackupAdapterDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^(storage|encoder|verifier|notifier)\.[a-z0-9][a-z0-9.-]*$')]
        [string]$Id,
        [Parameter(Mandatory)]
        [ValidateSet('Storage', 'Encoder', 'Verifier', 'Notifier')]
        [string]$Type,
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [string]$Version,
        [string[]]$Aliases = @(),
        [string[]]$Capabilities = @(),
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Operations,
        [string]$ModuleName,
        [int]$Priority = 0,
        [switch]$BuiltIn,
        [object]$Metadata
    )

    try {
        [void][version]$Version
    }
    catch {
        throw "Backup adapter '$Id' has invalid version '$Version'. Use a numeric version such as 1.0.0."
    }

    $expectedPrefix = $Type.ToLowerInvariant() + '.'
    if (-not $Id.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Backup adapter '$Id' must use the '$expectedPrefix' prefix for type '$Type'."
    }

    $contract = (Get-BackupAdapterContractCatalog)[$Type]
    $normalizedOperations = @{}
    foreach ($entry in $Operations.GetEnumerator()) {
        $operationName = [string]$entry.Key
        $handler = $entry.Value
        if ([string]::IsNullOrWhiteSpace($operationName)) {
            throw "Backup adapter '$Id' contains an operation without a name."
        }
        if ($handler -isnot [scriptblock] -and
            ($handler -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$handler))) {
            throw "Backup adapter '$Id' operation '$operationName' must be a ScriptBlock or command name."
        }
        $normalizedOperations[$operationName] = $handler
    }

    $missingOperations = @(
        $contract.requiredOperations |
            Where-Object { -not $normalizedOperations.ContainsKey([string]$_) }
    )
    if ($missingOperations.Count -gt 0) {
        throw (
            "Backup adapter '$Id' does not implement required $Type operation(s): " +
            ($missingOperations -join ', ')
        )
    }

    $portability = if (-not [string]::IsNullOrWhiteSpace($ModuleName)) {
        'ProviderModule'
    }
    elseif ($BuiltIn) {
        'BuiltIn'
    }
    else {
        'ProcessScope'
    }

    return [PSCustomObject]@{
        schemaVersion   = '1.0'
        contractVersion = [string]$contract.contractVersion
        id              = $Id.ToLowerInvariant()
        type            = $Type
        name            = $Name
        version         = $Version
        aliases         = @($Aliases | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)
        capabilities    = @($Capabilities | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)
        priority        = $Priority
        builtIn         = [bool]$BuiltIn
        enabled         = $true
        state           = 'Ready'
        portability     = $portability
        provider        = [PSCustomObject]@{
            moduleName = $ModuleName
        }
        operationNames  = @($normalizedOperations.Keys | Sort-Object)
        operations      = $normalizedOperations
        metadata        = $Metadata
        registeredAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Add-BackupAdapterDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Definition,
        [switch]$Force
    )

    $id = [string]$Definition.id
    if ($script:RenderKitBackupAdapterRegistry.ContainsKey($id) -and -not $Force) {
        throw "Backup adapter '$id' is already registered. Use -Force to replace it."
    }

    $script:RenderKitBackupAdapterRegistry[$id] = $Definition
    return $Definition
}

function Initialize-BackupAdapterRegistry {
    [CmdletBinding()]
    param()

    if ($null -ne $script:RenderKitBackupAdapterRegistry) {
        return
    }

    $script:RenderKitBackupAdapterRegistry = @{}

    Add-BackupAdapterDefinition -Definition (
        New-BackupAdapterDefinition `
            -Id 'storage.filesystem' `
            -Type Storage `
            -Name 'File System' `
            -Version '1.0.0' `
            -Aliases @('FileSystem', 'SMBOrNFS', 'OfflineDisk', 'NAS', 'LocalFileSystem') `
            -Capabilities @('LocalPath', 'NetworkShare', 'HealthCheck', 'Copy', 'FreeSpace') `
            -BuiltIn `
            -Operations @{
                TestHealth = {
                    param($Context)
                    Invoke-BackupFileSystemAdapterHealth -Context $Context
                }
                Write = {
                    param($Context)
                    Invoke-BackupFileSystemAdapterWrite -Context $Context
                }
            }
    ) | Out-Null

    Add-BackupAdapterDefinition -Definition (
        New-BackupAdapterDefinition `
            -Id 'encoder.ffmpeg' `
            -Type Encoder `
            -Name 'FFmpeg' `
            -Version '1.0.0' `
            -Aliases @('FFmpeg') `
            -Capabilities @('H264', 'H265', 'AV1', 'CPU', 'GPU', 'ChunkEncoding', 'Progress') `
            -BuiltIn `
            -Operations @{
                ResolveProfile = {
                    param($Context)
                    Get-BackupEncodingProfile `
                        -CompressionPreset ([string]$Context.compressionPreset) `
                        -VideoCodec ([string]$Context.videoCodec) `
                        -EncoderDevice ([string]$Context.encoderDevice) `
                        -QualityPreset ([string]$Context.qualityPreset) `
                        -AudioProfile ([string]$Context.audioProfile) `
                        -GpuCapabilities $Context.gpuCapabilities
                }
                BuildCommand = {
                    param($Context)
                    $ffmpeg = Get-BackupFfmpegCommand
                    [PSCustomObject]@{
                        executable = if ($ffmpeg) { [string]$ffmpeg.Source } else { 'ffmpeg' }
                        arguments  = @(
                            New-BackupFfmpegChunkArguments `
                                -Chunk $Context.chunk `
                                -Profile $Context.profile `
                                -OutputPath ([string]$Context.outputPath)
                        )
                    }
                }
            }
    ) | Out-Null

    Add-BackupAdapterDefinition -Definition (
        New-BackupAdapterDefinition `
            -Id 'verifier.sha256' `
            -Type Verifier `
            -Name 'SHA256 Checksum' `
            -Version '1.0.0' `
            -Aliases @('SHA256', 'Checksum', 'HashAfterWrite') `
            -Capabilities @('Checksum', 'FileSize', 'PostWriteVerification') `
            -BuiltIn `
            -Operations @{
                Verify = {
                    param($Context)
                    Invoke-BackupSha256VerifierAdapter -Context $Context
                }
            }
    ) | Out-Null

    Add-BackupAdapterDefinition -Definition (
        New-BackupAdapterDefinition `
            -Id 'notifier.log' `
            -Type Notifier `
            -Name 'RenderKit Log' `
            -Version '1.0.0' `
            -Aliases @('Log', 'Default') `
            -Capabilities @('JobStarted', 'JobCompleted', 'JobFailed', 'PersistentLog') `
            -BuiltIn `
            -Operations @{
                Notify = {
                    param($Context)
                    Invoke-BackupLogNotifierAdapter -Context $Context
                }
            }
    ) | Out-Null
}

function Get-BackupAdapterRegistry {
    [CmdletBinding()]
    param()

    Initialize-BackupAdapterRegistry
    return $script:RenderKitBackupAdapterRegistry
}

function Resolve-BackupAdapterId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Storage', 'Encoder', 'Verifier', 'Notifier')]
        [string]$Type,
        [Parameter(Mandatory)]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "A backup $Type adapter name is required."
    }

    $registry = Get-BackupAdapterRegistry
    $requested = $Name.Trim()
    $directId = $requested.ToLowerInvariant()
    if ($registry.ContainsKey($directId) -and [string]$registry[$directId].type -eq $Type) {
        return $directId
    }

    $aliasMatch = @(
        $registry.Values |
            Where-Object {
                [string]$_.type -eq $Type -and (
                    [string]::Equals([string]$_.name, $requested, [System.StringComparison]::OrdinalIgnoreCase) -or
                    @($_.aliases) -contains $requested
                )
            } |
            Sort-Object @{ Expression = { [int]$_.priority }; Descending = $true }, id |
            Select-Object -First 1
    )
    if ($aliasMatch.Count -gt 0) {
        return [string]$aliasMatch[0].id
    }

    $normalized = $requested.ToLowerInvariant() -replace '[^a-z0-9.-]', ''
    $knownId = switch ("$Type/$normalized") {
        'Storage/filesystem' { 'storage.filesystem' }
        'Storage/smbornfs' { 'storage.filesystem' }
        'Storage/offlinedisk' { 'storage.filesystem' }
        'Storage/ltfs' { 'storage.ltfs' }
        'Storage/tape' { 'storage.ltfs' }
        'Storage/s3' { 'storage.s3' }
        'Storage/clouds3' { 'storage.s3' }
        'Encoder/ffmpeg' { 'encoder.ffmpeg' }
        'Verifier/sha256' { 'verifier.sha256' }
        'Notifier/log' { 'notifier.log' }
        default { $null }
    }
    if ($knownId) {
        return $knownId
    }

    if ([string]::IsNullOrWhiteSpace($normalized.Trim('.'))) {
        throw "Backup $Type adapter name '$Name' does not contain a valid identifier."
    }
    return ('{0}.{1}' -f $Type.ToLowerInvariant(), $normalized.Trim('.'))
}

function Get-BackupAdapterDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Storage', 'Encoder', 'Verifier', 'Notifier')]
        [string]$Type,
        [Parameter(Mandatory)]
        [string]$Name
    )

    $id = Resolve-BackupAdapterId -Type $Type -Name $Name
    $registry = Get-BackupAdapterRegistry
    if (-not $registry.ContainsKey($id)) {
        return $null
    }

    $adapter = $registry[$id]
    if ([string]$adapter.type -ne $Type -or -not [bool]$adapter.enabled) {
        return $null
    }
    return $adapter
}

function ConvertTo-BackupAdapterPublicView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Adapter
    )

    return [PSCustomObject]@{
        Id              = [string]$Adapter.id
        Type            = [string]$Adapter.type
        Name            = [string]$Adapter.name
        Version         = [string]$Adapter.version
        ContractVersion = [string]$Adapter.contractVersion
        Aliases         = @($Adapter.aliases)
        Capabilities    = @($Adapter.capabilities)
        Operations      = @($Adapter.operationNames)
        Priority        = [int]$Adapter.priority
        BuiltIn         = [bool]$Adapter.builtIn
        Enabled         = [bool]$Adapter.enabled
        State           = [string]$Adapter.state
        Portability     = [string]$Adapter.portability
        ModuleName      = [string]$Adapter.provider.moduleName
        RegisteredAtUtc = [string]$Adapter.registeredAtUtc
        Metadata        = $Adapter.metadata
    }
}

function Register-BackupAdapterDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id,
        [Parameter(Mandatory)]
        [ValidateSet('Storage', 'Encoder', 'Verifier', 'Notifier')]
        [string]$Type,
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [string]$Version,
        [string[]]$Aliases = @(),
        [string[]]$Capabilities = @(),
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Operations,
        [string]$ModuleName,
        [int]$Priority = 0,
        [switch]$Force,
        [object]$Metadata
    )

    Initialize-BackupAdapterRegistry
    $definition = New-BackupAdapterDefinition `
        -Id $Id `
        -Type $Type `
        -Name $Name `
        -Version $Version `
        -Aliases $Aliases `
        -Capabilities $Capabilities `
        -Operations $Operations `
        -ModuleName $ModuleName `
        -Priority $Priority `
        -Metadata $Metadata
    return Add-BackupAdapterDefinition -Definition $definition -Force:$Force
}

function Remove-BackupAdapterDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id,
        [switch]$Force
    )

    $registry = Get-BackupAdapterRegistry
    $normalizedId = $Id.Trim().ToLowerInvariant()
    if (-not $registry.ContainsKey($normalizedId)) {
        return $false
    }
    if ([bool]$registry[$normalizedId].builtIn -and -not $Force) {
        throw "Built-in backup adapter '$normalizedId' cannot be removed without -Force."
    }

    $registry.Remove($normalizedId)
    return $true
}

function Invoke-BackupAdapterOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Adapter,
        [Parameter(Mandatory)]
        [string]$Operation,
        [Parameter(Mandatory)]
        [object]$Context
    )

    if (-not $Adapter.operations.ContainsKey($Operation)) {
        throw "Backup adapter '$($Adapter.id)' does not support operation '$Operation'."
    }

    $moduleName = [string]$Adapter.provider.moduleName
    if (-not [string]::IsNullOrWhiteSpace($moduleName) -and
        -not (Get-Module -Name $moduleName)) {
        Import-Module -Name $moduleName -ErrorAction Stop
    }

    $handler = $Adapter.operations[$Operation]
    try {
        if ($handler -is [scriptblock]) {
            return & $handler $Context
        }
        return & ([string]$handler) $Context
    }
    catch {
        throw "Backup $($Adapter.type) adapter '$($Adapter.id)' operation '$Operation' failed: $($_.Exception.Message)"
    }
}

function New-BackupAdapterSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Storage', 'Encoder', 'Verifier', 'Notifier')]
        [string]$Type,
        [Parameter(Mandatory)]
        [string]$RequestedName,
        [bool]$Required = $true,
        [string]$ScopeId
    )

    $id = Resolve-BackupAdapterId -Type $Type -Name $RequestedName
    $adapter = Get-BackupAdapterDefinition -Type $Type -Name $id
    return [PSCustomObject]@{
        type            = $Type
        requestedName   = $RequestedName
        id              = $id
        scopeId         = $ScopeId
        required        = $Required
        state           = if ($adapter) { 'Ready' } else { 'AdapterRequired' }
        available       = $null -ne $adapter
        version         = if ($adapter) { [string]$adapter.version } else { $null }
        contractVersion = if ($adapter) { [string]$adapter.contractVersion } else { '1.0' }
        capabilities    = if ($adapter) { @($adapter.capabilities) } else { @() }
        operationNames  = if ($adapter) { @($adapter.operationNames) } else { @() }
        portability     = if ($adapter) { [string]$adapter.portability } else { 'ProviderRequired' }
        provider        = if ($adapter) {
            [PSCustomObject]@{ moduleName = [string]$adapter.provider.moduleName }
        }
        else {
            [PSCustomObject]@{ moduleName = $null }
        }
    }
}

function New-BackupAdapterPlan {
    [CmdletBinding()]
    param(
        [object[]]$StorageTiers = @(),
        [string]$EncoderAdapter = 'FFmpeg',
        [string]$VerifierAdapter = 'SHA256',
        [string[]]$NotifierAdapter = @('Log')
    )

    $storageSelections = @(
        foreach ($tier in @($StorageTiers)) {
            $requested = if ($tier.PSObject.Properties.Name -contains 'adapterId' -and
                -not [string]::IsNullOrWhiteSpace([string]$tier.adapterId)) {
                [string]$tier.adapterId
            }
            else {
                [string]$tier.adapter
            }
            New-BackupAdapterSelection `
                -Type Storage `
                -RequestedName $requested `
                -Required ([bool]$tier.required) `
                -ScopeId ([string]$tier.id)
        }
    )
    $notifierSelections = @(
        foreach ($requested in @($NotifierAdapter)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$requested)) {
                New-BackupAdapterSelection `
                    -Type Notifier `
                    -RequestedName ([string]$requested) `
                    -Required $false
            }
        }
    )
    $encoderSelection = New-BackupAdapterSelection `
        -Type Encoder `
        -RequestedName $EncoderAdapter `
        -Required $true
    $verifierSelection = New-BackupAdapterSelection `
        -Type Verifier `
        -RequestedName $VerifierAdapter `
        -Required $true
    $allSelections = @(
        @($storageSelections) +
        @($notifierSelections) +
        @($encoderSelection, $verifierSelection)
    )
    $contracts = @(
        foreach ($contract in (Get-BackupAdapterContractCatalog).Values) {
            [PSCustomObject]@{
                type               = [string]$contract.type
                contractVersion    = [string]$contract.contractVersion
                requiredOperations = @($contract.requiredOperations)
                optionalOperations = @($contract.optionalOperations)
            }
        }
    )

    return [PSCustomObject]@{
        schemaVersion = '1.0'
        state         = 'Planned'
        contracts     = @($contracts)
        storage       = @($storageSelections)
        encoder       = $encoderSelection
        verifier      = $verifierSelection
        notifiers     = @($notifierSelections)
        summary       = [PSCustomObject]@{
            selectedCount        = @($allSelections).Count
            readyCount           = @($allSelections | Where-Object { [bool]$_.available }).Count
            adapterRequiredCount = @($allSelections | Where-Object { -not [bool]$_.available }).Count
        }
    }
}

function Import-BackupAdapterProvidersFromPlan {
    [CmdletBinding()]
    param(
        [object]$Plan
    )

    if (-not $Plan) {
        return @()
    }

    $moduleNames = @(
        @($Plan.storage) +
        @($Plan.encoder) +
        @($Plan.verifier) +
        @($Plan.notifiers) |
            ForEach-Object { [string]$_.provider.moduleName } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
    foreach ($moduleName in $moduleNames) {
        Import-Module -Name $moduleName -ErrorAction Stop
    }
    return @($moduleNames)
}

function Send-BackupAdapterNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Job,
        [Parameter(Mandatory)]
        [ValidateSet('JobStarted', 'JobCompleted', 'JobFailed', 'JobCancelled')]
        [string]$EventName,
        [object]$Data,
        [switch]$ThrowOnFailure
    )

    $payload = $Job.payload
    $selections = if ($payload -and $payload.adapters -and $payload.adapters.notifiers) {
        @($payload.adapters.notifiers)
    }
    else {
        @(New-BackupAdapterSelection -Type Notifier -RequestedName Log -Required $false)
    }
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($selection in $selections) {
        $adapter = Get-BackupAdapterDefinition -Type Notifier -Name ([string]$selection.id)
        if (-not $adapter) {
            $results.Add([PSCustomObject]@{
                    adapterId = [string]$selection.id
                    event     = $EventName
                    state     = 'AdapterRequired'
                    error     = "Notifier adapter '$($selection.id)' is not registered."
                })
            continue
        }

        try {
            $adapterResult = Invoke-BackupAdapterOperation `
                -Adapter $adapter `
                -Operation Notify `
                -Context ([PSCustomObject]@{
                    eventName = $EventName
                    job       = $Job
                    payload   = $payload
                    data      = $Data
                    occurredAtUtc = (Get-Date).ToUniversalTime().ToString('o')
                })
            $results.Add([PSCustomObject]@{
                    adapterId = [string]$adapter.id
                    event     = $EventName
                    state     = 'Sent'
                    result    = $adapterResult
                    error     = $null
                })
        }
        catch {
            $results.Add([PSCustomObject]@{
                    adapterId = [string]$adapter.id
                    event     = $EventName
                    state     = 'Failed'
                    result    = $null
                    error     = $_.Exception.Message
                })
            if ($ThrowOnFailure) {
                throw
            }
        }
    }
    return @($results.ToArray())
}

function Invoke-BackupFileSystemAdapterHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context
    )

    $target = [string]$Context.target
    $requiredBytes = [int64]$Context.requiredBytes
    if (Test-BackupPathLooksLikeUri -Path $target) {
        throw "File-system adapter cannot use URI target '$target'."
    }
    if (Test-Path -LiteralPath $target -PathType Leaf) {
        throw "Storage tier target '$target' is a file, not a directory."
    }

    $created = $false
    if (-not (Test-Path -LiteralPath $target -PathType Container)) {
        if (-not [bool]$Context.createTargetRoot) {
            throw "Storage tier target '$target' does not exist."
        }
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        $created = $true
    }

    $probePath = Join-Path -Path $target -ChildPath (".renderkit-health-{0}.tmp" -f [guid]::NewGuid().ToString('N'))
    Set-Content -LiteralPath $probePath -Value 'renderkit-storage-health' -Encoding UTF8 -ErrorAction Stop
    Remove-Item -LiteralPath $probePath -Force -ErrorAction Stop

    $freeBytes = $null
    $hasEnoughSpace = $true
    try {
        $targetItem = Get-Item -LiteralPath $target -ErrorAction Stop
        if ($targetItem.PSDrive -and $null -ne $targetItem.PSDrive.Free) {
            $freeBytes = [int64]$targetItem.PSDrive.Free
            if ($requiredBytes -gt 0) {
                $hasEnoughSpace = $freeBytes -gt $requiredBytes
            }
        }
    }
    catch {
        $freeBytes = $null
    }

    return [PSCustomObject]@{
        healthy       = [bool]$hasEnoughSpace
        state         = if ($hasEnoughSpace) { 'Healthy' } else { 'InsufficientSpace' }
        reason        = if ($hasEnoughSpace) { 'Writable' } else { 'InsufficientFreeSpace' }
        canWrite      = $true
        created       = $created
        freeBytes     = $freeBytes
        requiredBytes = $requiredBytes
        error         = $null
    }
}

function Invoke-BackupFileSystemAdapterWrite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context
    )

    $samePath = Test-BackupPathEquivalent `
        -Left ([string]$Context.sourcePath) `
        -Right ([string]$Context.targetPath)
    if (-not $samePath) {
        Copy-Item `
            -LiteralPath ([string]$Context.sourcePath) `
            -Destination ([string]$Context.targetPath) `
            -Force `
            -ErrorAction Stop
    }
    $targetItem = Get-Item -LiteralPath ([string]$Context.targetPath) -ErrorAction Stop
    return [PSCustomObject]@{
        copied    = -not $samePath
        targetPath = [string]$Context.targetPath
        sizeBytes = [int64]$targetItem.Length
    }
}

function Invoke-BackupSha256VerifierAdapter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context
    )

    $algorithm = if ([string]::IsNullOrWhiteSpace([string]$Context.algorithm)) {
        'SHA256'
    }
    else {
        [string]$Context.algorithm
    }
    $targetItem = Get-Item -LiteralPath ([string]$Context.targetPath) -ErrorAction Stop
    $targetHash = Get-FileHash `
        -LiteralPath ([string]$Context.targetPath) `
        -Algorithm $algorithm `
        -ErrorAction Stop
    $hashMatches = [string]::Equals(
        [string]$Context.expectedHash,
        [string]$targetHash.Hash,
        [System.StringComparison]::OrdinalIgnoreCase)
    $sizeMatches = (
        [int64]$Context.expectedSizeBytes -le 0 -or
        [int64]$targetItem.Length -eq [int64]$Context.expectedSizeBytes
    )

    return [PSCustomObject]@{
        verified    = [bool]($hashMatches -and $sizeMatches)
        targetHash  = [string]$targetHash.Hash
        sizeBytes   = [int64]$targetItem.Length
        hashMatches = $hashMatches
        sizeMatches = $sizeMatches
        algorithm   = $algorithm
        error       = if ($hashMatches -and $sizeMatches) {
            $null
        }
        else {
            "Checksum verification failed. HashMatches=$hashMatches SizeMatches=$sizeMatches."
        }
    }
}

function Invoke-BackupLogNotifierAdapter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context
    )

    $level = if ([string]$Context.eventName -eq 'JobFailed') { 'Error' } else { 'Info' }
    $jobId = if ($Context.job) { [string]$Context.job.id } else { $null }
    $message = "Backup notification '$($Context.eventName)' for job '$jobId'."
    Write-RenderKitLog -Level $level -Message $message
    return [PSCustomObject]@{
        delivered = $true
        channel   = 'RenderKitLog'
        message   = $message
    }
}
