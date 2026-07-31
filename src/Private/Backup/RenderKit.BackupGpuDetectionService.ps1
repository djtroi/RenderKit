function Get-BackupGpuObjectValue {
    [CmdletBinding()]
    param(
        [object]$InputObject,
        [Parameter(Mandatory)]
        [string]$Name,
        [object]$DefaultValue = $null
    )

    if ($null -eq $InputObject) {
        return $DefaultValue
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return $InputObject[$Name]
        }

        return $DefaultValue
    }
    if ($InputObject.PSObject.Properties.Name -contains $Name) {
        return $InputObject.$Name
    }

    return $DefaultValue
}

function Get-BackupGpuCapabilityCachePath {
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    $cacheRoot = Get-RenderKitStorageRoot -Kind Cache -Ensure
    $backupCacheRoot = New-RenderKitStorageDirectory -Path (
        Join-Path -Path $cacheRoot -ChildPath 'backup'
    )

    return Join-Path -Path $backupCacheRoot -ChildPath 'gpu-capabilities.json'
}

function Get-BackupGpuProviderDefinition {
    [CmdletBinding()]
    param()

    return @(
        [PSCustomObject]@{
            id             = 'Nvidia'
            displayName    = 'NVIDIA NVENC'
            rank           = 30
            vendorPatterns = @('nvidia', 'geforce', 'quadro', 'rtx', 'gtx')
            probeCommands  = @('nvidia-smi')
            encoders       = [PSCustomObject]@{
                H264 = 'h264_nvenc'
                H265 = 'hevc_nvenc'
                AV1  = 'av1_nvenc'
            }
        }
        [PSCustomObject]@{
            id             = 'IntelQuickSync'
            displayName    = 'Intel Quick Sync'
            rank           = 20
            vendorPatterns = @('intel', 'iris', 'uhd graphics', 'arc')
            probeCommands  = @()
            encoders       = [PSCustomObject]@{
                H264 = 'h264_qsv'
                H265 = 'hevc_qsv'
                AV1  = 'av1_qsv'
            }
        }
        [PSCustomObject]@{
            id             = 'AMD'
            displayName    = 'AMD AMF'
            rank           = 10
            vendorPatterns = @('amd', 'radeon')
            probeCommands  = @()
            encoders       = [PSCustomObject]@{
                H264 = 'h264_amf'
                H265 = 'hevc_amf'
                AV1  = 'av1_amf'
            }
        }
    )
}

function ConvertFrom-BackupFfmpegEncoderList {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string[]]$Text
    )

    $names = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($Text)) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $trimmed = ([string]$line).Trim()
        if ($trimmed -match '^[A-Z\.]{6}\s+([A-Za-z0-9_]+)\s+') {
            $names.Add($Matches[1])
            continue
        }
        if ($trimmed -match '\b([A-Za-z0-9]+_(?:nvenc|qsv|amf))\b') {
            $names.Add($Matches[1])
            continue
        }
    }

    return @(
        $names.ToArray() |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
}

function Get-BackupFfmpegEncoderNameList {
    [CmdletBinding()]
    param(
        [object]$FfmpegCommand
    )

    if (-not $FfmpegCommand) {
        $FfmpegCommand = Get-BackupFfmpegCommand
    }
    if (-not $FfmpegCommand -or [string]::IsNullOrWhiteSpace([string]$FfmpegCommand.Source)) {
        return @()
    }

    try {
        $output = & ([string]$FfmpegCommand.Source) -hide_banner -encoders 2>&1
        return @(ConvertFrom-BackupFfmpegEncoderList -Text @($output | ForEach-Object { [string]$_ }))
    }
    catch {
        return @()
    }
}

function Test-BackupFfmpegEncoderCapability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FfmpegPath,
        [Parameter(Mandatory)]
        [string]$EncoderName,
        [ValidateRange(1, 60)]
        [int]$TimeoutSeconds = 15
    )

    $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $processInfo.FileName = $FfmpegPath
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.CreateNoWindow = $true
    foreach ($argument in @(
            '-hide_banner',
            '-loglevel', 'error',
            '-f', 'lavfi',
            '-i', 'color=c=black:s=64x64:d=0.1',
            '-frames:v', '1',
            '-an',
            '-c:v', $EncoderName,
            '-f', 'null',
            '-')) {
        $processInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $processInfo
    try {
        [void]$process.Start()
        $standardOutput = $process.StandardOutput.ReadToEndAsync()
        $standardError = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill($true)
            $process.WaitForExit()
            return [PSCustomObject]@{
                encoderName = $EncoderName
                usable = $false
                exitCode = $null
                reason = 'ProbeTimedOut'
                error = "Encoder probe exceeded $TimeoutSeconds second(s)."
            }
        }

        $outputText = $standardOutput.GetAwaiter().GetResult()
        $errorText = $standardError.GetAwaiter().GetResult()
        return [PSCustomObject]@{
            encoderName = $EncoderName
            usable = $process.ExitCode -eq 0
            exitCode = [int]$process.ExitCode
            reason = if ($process.ExitCode -eq 0) {
                'ProbeSucceeded'
            }
            else {
                'ProbeFailed'
            }
            error = if ([string]::IsNullOrWhiteSpace($errorText)) {
                $outputText
            }
            else {
                $errorText
            }
        }
    }
    catch {
        return [PSCustomObject]@{
            encoderName = $EncoderName
            usable = $false
            exitCode = $null
            reason = 'ProbeFailed'
            error = $_.Exception.Message
        }
    }
    finally {
        $process.Dispose()
    }
}

function Get-BackupVideoControllerNameList {
    [CmdletBinding()]
    param()

    $names = New-Object System.Collections.Generic.List[string]
    try {
        $platform = Get-RenderKitPlatform
        if ($platform -eq 'Windows') {
            Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop |
                ForEach-Object {
                    if (-not [string]::IsNullOrWhiteSpace([string]$_.Name)) {
                        $names.Add([string]$_.Name)
                    }
                }
        }
        elseif ($platform -eq 'Linux') {
            $lspci = Get-Command -Name lspci -CommandType Application -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($lspci) {
                & ([string]$lspci.Source) 2>$null |
                    Where-Object { [string]$_ -match '(VGA|3D|Display)' } |
                    ForEach-Object { $names.Add([string]$_) }
            }
        }
        elseif ($platform -eq 'macOS') {
            $systemProfiler = Get-Command -Name system_profiler -CommandType Application -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($systemProfiler) {
                & ([string]$systemProfiler.Source) SPDisplaysDataType 2>$null |
                    Where-Object { [string]$_ -match '(Chipset Model|Graphics)' } |
                    ForEach-Object { $names.Add(([string]$_).Trim()) }
            }
        }
    }
    catch {
        return @()
    }

    return @(
        $names.ToArray() |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
}

function New-BackupGpuCapabilityReport {
    [CmdletBinding()]
    param(
        [string[]]$EncoderNames = @(),
        [string[]]$VideoControllerNames = @(),
        [string[]]$DetectedCommands = @(),
        [string]$FfmpegPath,
        [string]$CachePath,
        [ValidateRange(1, 8760)]
        [int]$CacheTtlHours = 168,
        [string]$Source = 'Provided',
        [hashtable]$EncoderProbeResults,
        [switch]$RunBenchmark
    )

    $normalizedEncoderNames = @(
        $EncoderNames |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } |
            Sort-Object -Unique
    )
    $controllerText = (@($VideoControllerNames) -join ' ').ToLowerInvariant()
    $detectedCommandNames = @(
        $DetectedCommands |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } |
            Sort-Object -Unique
    )

    $providers = New-Object System.Collections.Generic.List[object]
    foreach ($definition in @(Get-BackupGpuProviderDefinition)) {
        $hardwareDetected = $false
        foreach ($pattern in @($definition.vendorPatterns)) {
            if ($controllerText -match [regex]::Escape(([string]$pattern).ToLowerInvariant())) {
                $hardwareDetected = $true
                break
            }
        }
        foreach ($command in @($definition.probeCommands)) {
            if ($detectedCommandNames -contains ([string]$command).ToLowerInvariant()) {
                $hardwareDetected = $true
            }
        }

        $codecCapabilities = [ordered]@{}
        foreach ($codec in @('H264', 'H265', 'AV1')) {
            $encoder = [string](Get-BackupGpuObjectValue -InputObject $definition.encoders -Name $codec)
            $ffmpegSupported = $normalizedEncoderNames -contains $encoder.ToLowerInvariant()
            $probeKnown = $null -ne $EncoderProbeResults -and
                $EncoderProbeResults.ContainsKey($encoder)
            $probeSucceeded = $probeKnown -and
                [bool]$EncoderProbeResults[$encoder].usable
            $codecCapabilities[$codec] = [PSCustomObject]@{
                codec          = $codec
                encoderName    = $encoder
                ffmpegSupported = [bool]$ffmpegSupported
                hardwareDetected = [bool]$hardwareDetected
                probeKnown     = [bool]$probeKnown
                probeSucceeded = if ($probeKnown) {
                    [bool]$probeSucceeded
                }
                else {
                    $null
                }
                probeReason    = if ($probeKnown) {
                    [string]$EncoderProbeResults[$encoder].reason
                }
                else {
                    $null
                }
                usableForAuto = [bool](
                    $ffmpegSupported -and
                    $hardwareDetected -and
                    (-not $RunBenchmark -or $probeSucceeded))
            }
        }

        $supportedCodecs = @(
            $codecCapabilities.Keys |
                Where-Object { [bool]$codecCapabilities[$_].ffmpegSupported }
        )
        $usableCodecs = @(
            $codecCapabilities.Keys |
                Where-Object { [bool]$codecCapabilities[$_].usableForAuto }
        )

        $providers.Add([PSCustomObject]@{
                id                = [string]$definition.id
                displayName       = [string]$definition.displayName
                rank              = [int]$definition.rank
                hardwareDetected  = [bool]$hardwareDetected
                ffmpegSupported   = $supportedCodecs.Count -gt 0
                availableForAuto  = $usableCodecs.Count -gt 0
                supportedCodecs   = @($supportedCodecs)
                usableCodecs      = @($usableCodecs)
                codecCapabilities = [PSCustomObject]$codecCapabilities
            })
    }

    $providerArray = @($providers.ToArray())
    $recommendations = [ordered]@{}
    foreach ($codec in @('H264', 'H265', 'AV1')) {
        $candidate = @(
            $providerArray |
                Where-Object {
                    $capability = Get-BackupGpuObjectValue -InputObject $_.codecCapabilities -Name $codec
                    $capability -and [bool]$capability.usableForAuto
                } |
                Sort-Object -Property @{ Expression = 'rank'; Descending = $true }, id |
                Select-Object -First 1
        )

        if ($candidate.Count -gt 0) {
            $capability = Get-BackupGpuObjectValue -InputObject $candidate[0].codecCapabilities -Name $codec
            $recommendations[$codec] = [PSCustomObject]@{
                device      = [string]$candidate[0].id
                encoderName = [string]$capability.encoderName
                reason      = 'HardwareEncoderAvailable'
            }
        }
        else {
            $recommendations[$codec] = [PSCustomObject]@{
                device      = 'CPU'
                encoderName = Get-BackupCpuEncoderName -VideoCodec $codec
                reason      = 'NoUsableHardwareEncoderDetected'
            }
        }
    }

    $detectedAtUtc = (Get-Date).ToUniversalTime()
    return [PSCustomObject]@{
        schemaVersion = '1.1'
        source        = $Source
        detectedAtUtc = $detectedAtUtc.ToString('o')
        expiresAtUtc  = $detectedAtUtc.AddHours($CacheTtlHours).ToString('o')
        ffmpeg        = [PSCustomObject]@{
            available    = -not [string]::IsNullOrWhiteSpace($FfmpegPath)
            path         = $FfmpegPath
            encoderCount = $normalizedEncoderNames.Count
            encoderNames = @($normalizedEncoderNames)
        }
        hardware      = [PSCustomObject]@{
            controllerNames = @($VideoControllerNames)
            detectedCommands = @($DetectedCommands)
        }
        providers     = @($providerArray)
        recommendations = [PSCustomObject]$recommendations
        benchmark     = [PSCustomObject]@{
            requested = [bool]$RunBenchmark
            state     = if ($RunBenchmark) { 'Completed' } else { 'NotRun' }
            mode      = 'CapabilityCacheMicroBenchmark'
            reason    = if ($RunBenchmark) { 'Hardware encoders were validated with a one-frame capability probe.' } else { 'Capability detection did not run encode probes.' }
            results   = if ($null -ne $EncoderProbeResults) {
                [PSCustomObject]$EncoderProbeResults
            }
            else {
                [PSCustomObject]@{}
            }
        }
        cache         = [PSCustomObject]@{
            enabled  = $true
            path     = $CachePath
            ttlHours = $CacheTtlHours
            source   = $Source
        }
        summary       = [PSCustomObject]@{
            providerCount             = $providerArray.Count
            hardwareProviderCount     = @($providerArray | Where-Object { [bool]$_.hardwareDetected }).Count
            autoHardwareProviderCount = @($providerArray | Where-Object { [bool]$_.availableForAuto }).Count
            av1HardwareEncoderAvailable = @(
                $providerArray |
                    Where-Object {
                        $capability = Get-BackupGpuObjectValue -InputObject $_.codecCapabilities -Name 'AV1'
                        $capability -and [bool]$capability.usableForAuto
                    }
            ).Count -gt 0
        }
    }
}

function Save-BackupGpuCapabilityCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Report,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Get-BackupGpuCapabilityCachePath
    }

    $parent = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-RenderKitStorageDirectory -Path $parent | Out-Null
    }

    $Report |
        ConvertTo-Json -Depth 24 |
        Set-Content -LiteralPath $Path -Encoding UTF8

    return $Path
}

function Read-BackupGpuCapabilityCache {
    [CmdletBinding()]
    param(
        [string]$Path,
        [switch]$AllowExpired
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Get-BackupGpuCapabilityCachePath
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    try {
        $report = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
        if ([string]$report.schemaVersion -ne '1.1') {
            return $null
        }
        $expiresAtText = [string](Get-BackupGpuObjectValue -InputObject $report -Name 'expiresAtUtc')
        $expiresAt = [datetime]::MinValue
        $isExpired = -not [datetime]::TryParse(
            $expiresAtText,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AssumeUniversal,
            [ref]$expiresAt
        ) -or $expiresAt.ToUniversalTime() -lt (Get-Date).ToUniversalTime()

        if ($isExpired -and -not $AllowExpired) {
            return $null
        }
        if ($report.PSObject.Properties.Name -contains 'cache' -and $report.cache) {
            $report.cache.source = 'Cache'
            $report.cache.path = $Path
        }

        return $report
    }
    catch {
        return $null
    }
}

function Get-BackupGpuCapabilityReport {
    [CmdletBinding()]
    param(
        [switch]$Refresh,
        [switch]$SkipCacheWrite,
        [switch]$RunBenchmark,
        [ValidateRange(1, 8760)]
        [int]$CacheTtlHours = 168
    )

    $cachePath = Get-BackupGpuCapabilityCachePath
    if (-not $Refresh) {
        $cached = Read-BackupGpuCapabilityCache -Path $cachePath
        if ($cached) {
            return $cached
        }
    }

    $ffmpeg = Get-BackupFfmpegCommand
    $ffmpegPath = if ($ffmpeg) { [string]$ffmpeg.Source } else { $null }
    $encoderNames = Get-BackupFfmpegEncoderNameList -FfmpegCommand $ffmpeg
    $controllerNames = Get-BackupVideoControllerNameList
    $detectedCommands = @(
        foreach ($commandName in @('nvidia-smi')) {
            $command = Get-Command -Name $commandName -CommandType Application -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($command) {
                [string]$commandName
            }
        }
    )

    $detectedReport = New-BackupGpuCapabilityReport `
        -EncoderNames @($encoderNames) `
        -VideoControllerNames @($controllerNames) `
        -DetectedCommands @($detectedCommands) `
        -FfmpegPath $ffmpegPath `
        -CachePath $cachePath `
        -CacheTtlHours $CacheTtlHours `
        -Source 'Live'

    $probeResults = @{}
    if (-not [string]::IsNullOrWhiteSpace($ffmpegPath)) {
        foreach ($provider in @($detectedReport.providers |
                Where-Object { [bool]$_.hardwareDetected })) {
            foreach ($codec in @('H264', 'H265', 'AV1')) {
                $capability = Get-BackupGpuObjectValue `
                    -InputObject $provider.codecCapabilities `
                    -Name $codec
                if (-not $capability -or
                    -not [bool]$capability.ffmpegSupported) {
                    continue
                }
                $encoderName = [string]$capability.encoderName
                if ($probeResults.ContainsKey($encoderName)) {
                    continue
                }
                $probeResults[$encoderName] =
                    Test-BackupFfmpegEncoderCapability `
                        -FfmpegPath $ffmpegPath `
                        -EncoderName $encoderName
            }
        }
    }

    $report = New-BackupGpuCapabilityReport `
        -EncoderNames @($encoderNames) `
        -VideoControllerNames @($controllerNames) `
        -DetectedCommands @($detectedCommands) `
        -FfmpegPath $ffmpegPath `
        -CachePath $cachePath `
        -CacheTtlHours $CacheTtlHours `
        -Source 'Live' `
        -EncoderProbeResults $probeResults `
        -RunBenchmark

    if (-not $SkipCacheWrite) {
        Save-BackupGpuCapabilityCache -Report $report -Path $cachePath | Out-Null
    }

    return $report
}

function Resolve-BackupEncoderDeviceFromCapabilities {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('H264', 'H265', 'AV1')]
        [string]$VideoCodec,
        [ValidateSet('Auto', 'CPU', 'Nvidia', 'IntelQuickSync', 'AMD')]
        [string]$EncoderDevice = 'Auto',
        [object]$GpuCapabilities
    )

    if ($EncoderDevice -ne 'Auto') {
        return [PSCustomObject]@{
            requestedDevice = $EncoderDevice
            device          = $EncoderDevice
            source          = 'UserRequested'
            reason          = 'ExplicitEncoderDevice'
            encoderName     = if ($EncoderDevice -eq 'CPU') {
                Get-BackupCpuEncoderName -VideoCodec $VideoCodec
            }
            else {
                Get-BackupHardwareEncoderName -VideoCodec $VideoCodec -EncoderDevice $EncoderDevice
            }
        }
    }

    $recommendations = Get-BackupGpuObjectValue -InputObject $GpuCapabilities -Name 'recommendations'
    $recommendation = Get-BackupGpuObjectValue -InputObject $recommendations -Name $VideoCodec
    $device = [string](Get-BackupGpuObjectValue -InputObject $recommendation -Name 'device' -DefaultValue 'CPU')
    if ([string]::IsNullOrWhiteSpace($device)) {
        $device = 'CPU'
    }

    return [PSCustomObject]@{
        requestedDevice = 'Auto'
        device          = $device
        source          = if ($device -eq 'CPU') { 'CpuFallback' } else { 'GpuCapabilityAuto' }
        reason          = [string](Get-BackupGpuObjectValue -InputObject $recommendation -Name 'reason' -DefaultValue 'NoCapabilityReport')
        encoderName     = if ($device -eq 'CPU') {
            Get-BackupCpuEncoderName -VideoCodec $VideoCodec
        }
        else {
            Get-BackupHardwareEncoderName -VideoCodec $VideoCodec -EncoderDevice $device
        }
    }
}

function New-BackupGpuDetectionPlan {
    [CmdletBinding()]
    param(
        [ValidateSet('Auto', 'H264', 'H265', 'AV1')]
        [string]$VideoCodec = 'Auto',
        [ValidateSet('Auto', 'CPU', 'Nvidia', 'IntelQuickSync', 'AMD')]
        [string]$EncoderDevice = 'Auto',
        [ValidateSet('Fastest', 'Balanced', 'Smallest', 'Lossless')]
        [string]$CompressionPreset = 'Balanced'
    )

    return [PSCustomObject]@{
        schemaVersion = '1.0'
        enabled       = $true
        state         = 'Planned'
        mode          = if ($EncoderDevice -eq 'Auto') { 'AutoSelectBestAvailable' } else { 'UserSelectedDevice' }
        requested     = [PSCustomObject]@{
            videoCodec    = $VideoCodec
            resolvedCodec = Resolve-BackupVideoCodec -VideoCodec $VideoCodec -CompressionPreset $CompressionPreset
            encoderDevice = $EncoderDevice
        }
        providers     = @('Nvidia', 'IntelQuickSync', 'AMD')
        codecSupport  = @('H264', 'H265', 'AV1')
        cache         = [PSCustomObject]@{
            enabled  = $true
            path     = Get-BackupGpuCapabilityCachePath
            ttlHours = 168
        }
        benchmark     = [PSCustomObject]@{
            enabled = $true
            mode    = 'CapabilityCacheMicroBenchmark'
            state   = 'AvailableOnWorker'
        }
    }
}
