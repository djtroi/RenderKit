function ConvertTo-BackupRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,
        [Parameter(Mandatory)]
        [string]$Path
    )

    $resolvedRoot = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\', '/')
    $resolvedPath = [System.IO.Path]::GetFullPath($Path)

    if ($resolvedPath.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $resolvedPath.Substring($resolvedRoot.Length).TrimStart('\', '/') -replace '\\', '/'
    }

    return (Split-Path -Path $resolvedPath -Leaf)
}

function Get-BackupMediaType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $extension = ([System.IO.Path]::GetExtension($Path)).ToLowerInvariant()
    $videoExtensions = @(
        '.3g2', '.3gp', '.avi', '.braw', '.crm', '.m2ts', '.m4v',
        '.mkv', '.mov', '.mp4', '.mpeg', '.mpg', '.mts', '.mxf',
        '.r3d', '.ts', '.webm', '.wmv'
    )
    $audioExtensions = @(
        '.aac', '.aif', '.aiff', '.alac', '.flac', '.m4a', '.mp3',
        '.ogg', '.opus', '.wav', '.wma'
    )
    $imageExtensions = @(
        '.arw', '.avif', '.bmp', '.cr2', '.cr3', '.dng', '.gif',
        '.heic', '.heif', '.jpg', '.jpeg', '.nef', '.png', '.psd',
        '.raf', '.raw', '.tif', '.tiff', '.webp'
    )

    if ($videoExtensions -contains $extension) { return 'Video' }
    if ($audioExtensions -contains $extension) { return 'Audio' }
    if ($imageExtensions -contains $extension) { return 'Image' }

    return 'Other'
}

function Get-BackupFfprobeCommand {
    [CmdletBinding()]
    param()

    return Get-Command -Name ffprobe -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
}

function ConvertTo-BackupProbeNumber {
    [CmdletBinding()]
    param(
        [object]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    $number = 0.0
    if ([double]::TryParse(
            [string]$Value,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$number)) {
        return [double]$number
    }

    return $null
}

function Invoke-BackupFfprobe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [object]$Command
    )

    $arguments = @(
        '-v', 'quiet',
        '-print_format', 'json',
        '-show_format',
        '-show_streams',
        $Path
    )

    try {
        $json = & $Command.Source @arguments 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($json -join [Environment]::NewLine))) {
            return [PSCustomObject]@{
                succeeded = $false
                data      = $null
                error     = "ffprobe exited with code $LASTEXITCODE."
            }
        }

        return [PSCustomObject]@{
            succeeded = $true
            data      = (($json -join [Environment]::NewLine) | ConvertFrom-Json -ErrorAction Stop)
            error     = $null
        }
    }
    catch {
        return [PSCustomObject]@{
            succeeded = $false
            data      = $null
            error     = $_.Exception.Message
        }
    }
}

function ConvertTo-BackupMediaProbeMetadata {
    [CmdletBinding()]
    param(
        [object]$ProbeData
    )

    $duration = $null
    $formatName = $null
    $bitRate = $null
    $videoStreams = @()
    $audioStreams = @()

    if ($ProbeData -and $ProbeData.format) {
        $duration = ConvertTo-BackupProbeNumber -Value $ProbeData.format.duration
        $formatName = [string]$ProbeData.format.format_name
        $bitRate = ConvertTo-BackupProbeNumber -Value $ProbeData.format.bit_rate
    }

    foreach ($stream in @($ProbeData.streams)) {
        $codecType = [string]$stream.codec_type
        if ($null -eq $duration) {
            $duration = ConvertTo-BackupProbeNumber -Value $stream.duration
        }

        if ($codecType -eq 'video') {
            $videoStreams += [PSCustomObject]@{
                index       = [int]$stream.index
                codec       = [string]$stream.codec_name
                width       = if ($stream.width) { [int]$stream.width } else { $null }
                height      = if ($stream.height) { [int]$stream.height } else { $null }
                frameRate   = [string]$stream.avg_frame_rate
                pixelFormat = [string]$stream.pix_fmt
            }
        }
        elseif ($codecType -eq 'audio') {
            $audioStreams += [PSCustomObject]@{
                index      = [int]$stream.index
                codec      = [string]$stream.codec_name
                channels   = if ($stream.channels) { [int]$stream.channels } else { $null }
                sampleRate = [string]$stream.sample_rate
            }
        }
    }

    return [PSCustomObject]@{
        durationSeconds = $duration
        format          = $formatName
        bitRate         = $bitRate
        videoStreams    = @($videoStreams)
        audioStreams    = @($audioStreams)
        hasVideo        = @($videoStreams).Count -gt 0
        hasAudio        = @($audioStreams).Count -gt 0
    }
}

function Get-BackupMediaAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,
        [switch]$ProbeTimedMedia
    )

    $resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot -ErrorAction Stop).ProviderPath
    if (-not (Test-Path -LiteralPath $resolvedProjectRoot -PathType Container)) {
        throw "Project root '$ProjectRoot' is not a directory."
    }

    $startedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    $ffprobe = if ($ProbeTimedMedia) { Get-BackupFfprobeCommand } else { $null }
    $files = New-Object System.Collections.Generic.List[object]
    $totalBytes = [int64]0
    $probeAttemptCount = 0
    $probeSuccessCount = 0

    foreach ($file in @(Get-ChildItem -LiteralPath $resolvedProjectRoot -Recurse -File -Force -ErrorAction SilentlyContinue)) {
        $mediaType = Get-BackupMediaType -Path $file.FullName
        $isTimedMedia = $mediaType -in @('Video', 'Audio')
        $probe = [PSCustomObject]@{
            attempted = $false
            succeeded = $false
            error     = $null
            command   = if ($ffprobe) { [string]$ffprobe.Source } else { $null }
        }
        $metadata = [PSCustomObject]@{
            durationSeconds = $null
            format          = $null
            bitRate         = $null
            videoStreams    = @()
            audioStreams    = @()
            hasVideo        = $mediaType -eq 'Video'
            hasAudio        = $mediaType -eq 'Audio'
        }

        if ($ProbeTimedMedia -and $isTimedMedia -and $ffprobe) {
            $probeAttemptCount++
            $probeResult = Invoke-BackupFfprobe -Path $file.FullName -Command $ffprobe
            $probe.attempted = $true
            $probe.succeeded = [bool]$probeResult.succeeded
            $probe.error = $probeResult.error
            if ($probeResult.succeeded) {
                $probeSuccessCount++
                $metadata = ConvertTo-BackupMediaProbeMetadata -ProbeData $probeResult.data
            }
        }
        elseif ($ProbeTimedMedia -and $isTimedMedia -and -not $ffprobe) {
            $probe.error = 'ffprobe was not found.'
        }

        $totalBytes += [int64]$file.Length
        $files.Add([PSCustomObject]@{
            path             = [string]$file.FullName
            relativePath     = ConvertTo-BackupRelativePath -RootPath $resolvedProjectRoot -Path $file.FullName
            extension        = ([System.IO.Path]::GetExtension($file.FullName)).ToLowerInvariant()
            mediaType        = $mediaType
            isMedia          = $mediaType -ne 'Other'
            isTimedMedia     = $isTimedMedia
            isChunkable      = $isTimedMedia -and $null -ne $metadata.durationSeconds -and [double]$metadata.durationSeconds -gt 0
            sizeBytes        = [int64]$file.Length
            lastWriteTimeUtc = $file.LastWriteTimeUtc.ToString('o')
            probe            = $probe
            metadata         = $metadata
        })
    }

    $fileArray = @($files.ToArray())
    $mediaFiles = @($fileArray | Where-Object { [bool]$_.isMedia })
    $timedFiles = @($fileArray | Where-Object { [bool]$_.isTimedMedia })
    $chunkableFiles = @($fileArray | Where-Object { [bool]$_.isChunkable })

    return [PSCustomObject]@{
        schemaVersion = '1.0'
        projectRoot   = $resolvedProjectRoot
        startedAtUtc  = $startedAtUtc
        completedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        probe         = [PSCustomObject]@{
            requested    = [bool]$ProbeTimedMedia
            available    = $null -ne $ffprobe
            command      = if ($ffprobe) { [string]$ffprobe.Source } else { $null }
            attempted    = $probeAttemptCount
            succeeded    = $probeSuccessCount
        }
        summary       = [PSCustomObject]@{
            fileCount       = @($fileArray).Count
            totalBytes      = [int64]$totalBytes
            mediaFileCount  = @($mediaFiles).Count
            timedFileCount  = @($timedFiles).Count
            chunkableCount  = @($chunkableFiles).Count
            videoFileCount  = @($fileArray | Where-Object { $_.mediaType -eq 'Video' }).Count
            audioFileCount  = @($fileArray | Where-Object { $_.mediaType -eq 'Audio' }).Count
            imageFileCount  = @($fileArray | Where-Object { $_.mediaType -eq 'Image' }).Count
        }
        files         = @($fileArray | Sort-Object relativePath)
    }
}
