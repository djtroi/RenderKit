function Get-BackupWorkerCapabilitySnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WorkerId,
        [switch]$Refresh
    )

    $gpu = Get-BackupGpuCapabilityReport -Refresh:$Refresh
    $encoderNames = @(
        @($gpu.ffmpeg.encoderNames) |
            ForEach-Object { ([string]$_).ToLowerInvariant() }
    )
    $cpuCodecs = @(
        foreach ($codec in @('H264', 'H265', 'AV1')) {
            $encoderName = Get-BackupCpuEncoderName -VideoCodec $codec
            if ($encoderNames -contains $encoderName.ToLowerInvariant()) {
                $codec
            }
        }
    )
    $devices = New-Object System.Collections.Generic.List[object]
    $devices.Add([PSCustomObject]@{
            id               = 'CPU'
            displayName      = 'CPU'
            hardwareDetected = $true
            codecs           = @($cpuCodecs)
            encoderNames     = [PSCustomObject]@{
                H264 = Get-BackupCpuEncoderName -VideoCodec H264
                H265 = Get-BackupCpuEncoderName -VideoCodec H265
                AV1  = Get-BackupCpuEncoderName -VideoCodec AV1
            }
        })
    foreach ($provider in @($gpu.providers)) {
        $devices.Add([PSCustomObject]@{
                id               = [string]$provider.id
                displayName      = [string]$provider.displayName
                hardwareDetected = [bool]$provider.hardwareDetected
                codecs           = @($provider.usableCodecs)
                encoderNames     = [PSCustomObject]@{
                    H264 = [string]$provider.codecCapabilities.H264.encoderName
                    H265 = [string]$provider.codecCapabilities.H265.encoderName
                    AV1  = [string]$provider.codecCapabilities.AV1.encoderName
                }
            })
    }

    return [PSCustomObject]@{
        schemaVersion = '1.0'
        workerId       = $WorkerId
        machine        = [Environment]::MachineName
        online         = $true
        status         = 'Ready'
        detectedAtUtc  = [string]$gpu.detectedAtUtc
        expiresAtUtc   = [string]$gpu.expiresAtUtc
        source         = [string]$gpu.source
        runtime        = [PSCustomObject]@{
            platform       = Get-RenderKitPlatform
            processorCount = [Environment]::ProcessorCount
            powerShell     = $PSVersionTable.PSVersion.ToString()
        }
        ffmpeg         = [PSCustomObject]@{
            available = [bool]$gpu.ffmpeg.available
            path      = [string]$gpu.ffmpeg.path
        }
        devices        = @($devices.ToArray())
    }
}

function Test-BackupProfileWorkerCompatibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Settings,
        [object[]]$WorkerCapability = @()
    )

    $resolvedCodec = Resolve-BackupVideoCodec `
        -VideoCodec ([string]$Settings.VideoCodec) `
        -CompressionPreset ([string]$Settings.CompressionPreset)
    $requiresEncoding = [string]$Settings.CompressionMode -notin @(
        'ArchiveOnly',
        'CopyOnly'
    )
    $requestedDevice = [string]$Settings.EncoderDevice
    $workers = New-Object System.Collections.Generic.List[object]

    foreach ($capability in @($WorkerCapability)) {
        $online = if (
            $capability.PSObject.Properties.Name -contains 'online'
        ) {
            [bool]$capability.online
        }
        else {
            $true
        }
        $compatible = $false
        $resolvedDevice = $null
        $reason = 'NoCompatibleEncoder'
        $usesCpuFallback = $false

        if (-not $online) {
            $reason = 'WorkerOffline'
        }
        elseif (-not $requiresEncoding) {
            $compatible = $true
            $reason = 'NoEncodingRequired'
        }
        else {
            $devices = @($capability.devices)
            if ($requestedDevice -eq 'Auto') {
                $hardware = @(
                    $devices |
                        Where-Object {
                            [string]$_.id -ne 'CPU' -and
                            @($_.codecs) -contains $resolvedCodec
                        } |
                        Select-Object -First 1
                )
                $cpu = @(
                    $devices |
                        Where-Object {
                            [string]$_.id -eq 'CPU' -and
                            @($_.codecs) -contains $resolvedCodec
                        } |
                        Select-Object -First 1
                )
                if ($hardware.Count -gt 0) {
                    $compatible = $true
                    $resolvedDevice = [string]$hardware[0].id
                    $reason = 'HardwareEncoderAvailable'
                }
                elseif ($cpu.Count -gt 0) {
                    $compatible = $true
                    $resolvedDevice = 'CPU'
                    $reason = 'CpuFallback'
                    $usesCpuFallback = $true
                }
            }
            else {
                $requested = @(
                    $devices |
                        Where-Object {
                            [string]$_.id -eq $requestedDevice -and
                            @($_.codecs) -contains $resolvedCodec
                        } |
                        Select-Object -First 1
                )
                if ($requested.Count -gt 0) {
                    $compatible = $true
                    $resolvedDevice = $requestedDevice
                    $reason = if ($requestedDevice -eq 'CPU') {
                        'CpuEncoderAvailable'
                    }
                    else {
                        'HardwareEncoderAvailable'
                    }
                }
                else {
                    $reason = 'RequestedDeviceUnavailable'
                }
            }
        }

        $workers.Add([PSCustomObject]@{
                workerId       = [string]$capability.workerId
                machine        = [string]$capability.machine
                online         = $online
                compatible     = $compatible
                resolvedCodec  = $resolvedCodec
                requestedDevice = $requestedDevice
                resolvedDevice = $resolvedDevice
                usesCpuFallback = $usesCpuFallback
                reason         = $reason
            })
    }

    $workerArray = @($workers.ToArray())
    $onlineWorkers = @($workerArray | Where-Object { $_.online })
    $compatibleWorkers = @(
        $onlineWorkers | Where-Object { $_.compatible }
    )
    $fallbackWorkers = @(
        $compatibleWorkers | Where-Object { $_.usesCpuFallback }
    )
    $status = if ($compatibleWorkers.Count -eq 0) {
        'Unavailable'
    }
    elseif (
        $compatibleWorkers.Count -lt $onlineWorkers.Count -or
        $fallbackWorkers.Count -gt 0
    ) {
        'Degraded'
    }
    else {
        'Available'
    }

    return [PSCustomObject]@{
        schemaVersion       = '1.0'
        status              = $status
        isExecutable        = $compatibleWorkers.Count -gt 0
        requiresEncoding    = $requiresEncoding
        requestedCodec      = [string]$Settings.VideoCodec
        resolvedCodec       = $resolvedCodec
        requestedDevice     = $requestedDevice
        compatibleWorkerIds = @(
            $compatibleWorkers | ForEach-Object { [string]$_.workerId }
        )
        workers             = $workerArray
    }
}
