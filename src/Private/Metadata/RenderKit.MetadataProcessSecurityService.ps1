function ConvertTo-RenderKitMetadataProcessArgumentText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$Arguments
    )

    $encoded = foreach ($argumentValue in @($Arguments)) {
        $argument = if ($null -eq $argumentValue) { '' } else { [string]$argumentValue }
        if ($argument.Length -gt 0 -and $argument -notmatch '[\s"]') {
            $argument
            continue
        }

        $builder = New-Object System.Text.StringBuilder
        [void]$builder.Append('"')
        $backslashCount = 0
        foreach ($character in $argument.ToCharArray()) {
            if ($character -eq '\') {
                $backslashCount++
                continue
            }
            if ($character -eq '"') {
                for ($index = 0; $index -lt (($backslashCount * 2) + 1); $index++) {
                    [void]$builder.Append('\')
                }
                [void]$builder.Append('"')
                $backslashCount = 0
                continue
            }
            for ($index = 0; $index -lt $backslashCount; $index++) {
                [void]$builder.Append('\')
            }
            $backslashCount = 0
            [void]$builder.Append($character)
        }
        for ($index = 0; $index -lt ($backslashCount * 2); $index++) {
            [void]$builder.Append('\')
        }
        [void]$builder.Append('"')
        $builder.ToString()
    }

    return ($encoded -join ' ')
}

function ConvertTo-RenderKitMetadataProcessDiagnostic {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()][string]$Text,
        [ValidateRange(256, 65536)][int]$MaximumCharacters = 8192
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }
    $trimmed = $Text.Trim()
    if ($trimmed.Length -le $MaximumCharacters) {
        return $trimmed
    }
    return $trimmed.Substring(0, $MaximumCharacters) + '... [truncated]'
}

function Invoke-RenderKitBoundedMetadataProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [AllowEmptyCollection()][string[]]$Arguments = @(),
        [ValidateRange(1, 1800)][int]$TimeoutSeconds = 120,
        [ValidateRange(1024, 1073741824)][int64]$MaximumStandardOutputBytes = 32MB,
        [ValidateRange(1024, 1073741824)][int64]$MaximumStandardErrorBytes = 8MB,
        [AllowEmptyCollection()][string[]]$MonitoredPath = @(),
        [ValidateRange(1024, 1073741824)][int64]$MaximumMonitoredFileBytes = 64MB
    )

    $temporaryRoot = Join-Path `
        -Path ([System.IO.Path]::GetTempPath()) `
        -ChildPath ('renderkit-process-{0}' -f [guid]::NewGuid().ToString('N'))
    [void][System.IO.Directory]::CreateDirectory($temporaryRoot)
    $stdoutPath = Join-Path $temporaryRoot 'stdout.bin'
    $stderrPath = Join-Path $temporaryRoot 'stderr.bin'

    $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $processInfo.FileName = $FilePath
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.CreateNoWindow = $true
    if ($processInfo.PSObject.Properties.Name -contains 'ArgumentList') {
        foreach ($argument in @($Arguments)) {
            $processInfo.ArgumentList.Add([string]$argument)
        }
    }
    else {
        $processInfo.Arguments = ConvertTo-RenderKitMetadataProcessArgumentText `
            -Arguments $Arguments
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $processInfo
    $stdoutStream = $null
    $stderrStream = $null
    $stdoutTask = $null
    $stderrTask = $null
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $failure = $null

    try {
        $stdoutStream = [System.IO.File]::Open(
            $stdoutPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::Read
        )
        $stderrStream = [System.IO.File]::Open(
            $stderrPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::Read
        )

        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.BaseStream.CopyToAsync($stdoutStream)
        $stderrTask = $process.StandardError.BaseStream.CopyToAsync($stderrStream)

        while (-not $process.WaitForExit(50)) {
            if ($stopwatch.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
                $failure = "Metadata process '$FilePath' exceeded the $TimeoutSeconds second timeout."
                break
            }
            if ($stdoutStream.Length -gt $MaximumStandardOutputBytes) {
                $failure = "Metadata process '$FilePath' exceeded the $MaximumStandardOutputBytes byte stdout limit."
                break
            }
            if ($stderrStream.Length -gt $MaximumStandardErrorBytes) {
                $failure = "Metadata process '$FilePath' exceeded the $MaximumStandardErrorBytes byte stderr limit."
                break
            }
            foreach ($candidatePath in @($MonitoredPath)) {
                if ([string]::IsNullOrWhiteSpace($candidatePath) -or
                    -not [System.IO.File]::Exists($candidatePath)) {
                    continue
                }
                $length = [System.IO.FileInfo]::new($candidatePath).Length
                if ($length -gt $MaximumMonitoredFileBytes) {
                    $failure = (
                        "Metadata process '$FilePath' produced '$candidatePath' larger than " +
                        "$MaximumMonitoredFileBytes bytes."
                    )
                    break
                }
            }
            if ($failure) {
                break
            }
        }

        if ($failure) {
            try {
                $treeKill = @($process.PSObject.Methods['Kill'].OverloadDefinitions) |
                    Where-Object {
                        [string]$_ -match '(?:System\.)?(?:Boolean|bool)\s+entireProcessTree'
                    } |
                    Select-Object -First 1
                if ($treeKill) {
                    $process.Kill($true)
                }
                else {
                    $process.Kill()
                }
            }
            catch {
                Write-Verbose "Metadata process termination failed: $($_.Exception.Message)"
            }
            try {
                [void]$process.WaitForExit(5000)
            }
            catch {
                Write-Verbose "Metadata process exit wait failed: $($_.Exception.Message)"
            }
            foreach ($captureTask in @($stdoutTask, $stderrTask)) {
                if (-not $captureTask) {
                    continue
                }
                try {
                    $captureTask.GetAwaiter().GetResult()
                }
                catch {
                    Write-Verbose "Metadata process capture drain failed after termination: $($_.Exception.Message)"
                }
            }
            throw $failure
        }

        $process.WaitForExit()
        $stdoutTask.GetAwaiter().GetResult()
        $stderrTask.GetAwaiter().GetResult()
        $stdoutStream.Flush()
        $stderrStream.Flush()

        if ($stdoutStream.Length -gt $MaximumStandardOutputBytes) {
            throw "Metadata process '$FilePath' exceeded the $MaximumStandardOutputBytes byte stdout limit."
        }
        if ($stderrStream.Length -gt $MaximumStandardErrorBytes) {
            throw "Metadata process '$FilePath' exceeded the $MaximumStandardErrorBytes byte stderr limit."
        }
        foreach ($candidatePath in @($MonitoredPath)) {
            if (-not [string]::IsNullOrWhiteSpace($candidatePath) -and
                [System.IO.File]::Exists($candidatePath) -and
                [System.IO.FileInfo]::new($candidatePath).Length -gt $MaximumMonitoredFileBytes) {
                throw (
                    "Metadata process '$FilePath' produced '$candidatePath' larger than " +
                    "$MaximumMonitoredFileBytes bytes."
                )
            }
        }

        # Windows does not permit ReadAllText while the capture FileStream is
        # still open with FileShare.Read. Close both completed capture handles
        # before reopening the files for the final bounded read.
        $stdoutStream.Dispose()
        $stdoutStream = $null
        $stderrStream.Dispose()
        $stderrStream = $null

        $stdoutText = [System.IO.File]::ReadAllText($stdoutPath)
        $stderrText = [System.IO.File]::ReadAllText($stderrPath)
        return [PSCustomObject]@{
            ExitCode = [int]$process.ExitCode
            StandardOutput = $stdoutText
            StandardError = $stderrText
            StandardOutputLines = @(
                $stdoutText -split "`r?`n" |
                    Where-Object { $null -ne $_ -and $_ -ne '' }
            )
            StandardErrorLines = @(
                $stderrText -split "`r?`n" |
                    Where-Object { $null -ne $_ -and $_ -ne '' }
            )
            DurationMilliseconds = [int64]$stopwatch.ElapsedMilliseconds
        }
    }
    finally {
        $stopwatch.Stop()
        if ($stdoutStream) { $stdoutStream.Dispose() }
        if ($stderrStream) { $stderrStream.Dispose() }
        $process.Dispose()
        if ([System.IO.Directory]::Exists($temporaryRoot)) {
            [System.IO.Directory]::Delete($temporaryRoot, $true)
        }
    }
}
