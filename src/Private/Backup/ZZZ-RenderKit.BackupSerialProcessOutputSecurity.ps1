# RS-1571: Windows PowerShell 5.1 does not provide Start-ThreadJob by
# default, so the backup scheduler deliberately falls back to serial command
# execution. Keep that fallback resource-bounded as well: invoking an encoder
# through PowerShell's native pipeline would otherwise accumulate arbitrary
# stdout in memory before the caller can process it.
function Invoke-BackupBoundedSerialProcessCapture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Command
    )

    $maximumCapturedLineCharacters = 16384
    $maximumOutputLines = 2048
    $maximumOutputCharacters = 1048576
    $maximumErrorLines = 1024
    $maximumErrorCharacters = 524288

    function Add-BoundedSerialProcessLine {
        param(
            [Parameter(Mandatory)]$Queue,
            [Parameter(Mandatory)][ref]$CharacterCount,
            [AllowNull()][string]$Line,
            [Parameter(Mandatory)][int]$MaximumLines,
            [Parameter(Mandatory)][int]$MaximumCharacters,
            [Parameter(Mandatory)][int]$MaximumLineCharacters
        )

        if ($null -eq $Line) {
            return
        }

        $boundedLine = [string]$Line
        if ($boundedLine.Length -gt $MaximumLineCharacters) {
            $boundedLine = $boundedLine.Substring(0, $MaximumLineCharacters) +
                '… [line truncated]'
        }

        $Queue.Enqueue($boundedLine)
        $CharacterCount.Value += $boundedLine.Length
        while ($Queue.Count -gt $MaximumLines -or
            $CharacterCount.Value -gt $MaximumCharacters) {
            if ($Queue.Count -eq 0) {
                break
            }
            $removed = [string]$Queue.Dequeue()
            $CharacterCount.Value -= $removed.Length
        }
    }

    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = [string]$Command.executable
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.CreateNoWindow = $true
    try {
        foreach ($argument in @($Command.arguments)) {
            $processInfo.ArgumentList.Add([string]$argument)
        }
    }
    catch {
        $processInfo.Arguments = ConvertTo-BackupBoundedProcessArgumentText `
            -Arguments @($Command.arguments)
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    try {
        [void]$process.Start()

        $outputQueue = New-Object 'System.Collections.Generic.Queue[string]'
        $errorQueue = New-Object 'System.Collections.Generic.Queue[string]'
        $outputCharacterCount = 0
        $errorCharacterCount = 0
        $totalOutputLines = 0
        $totalErrorLines = 0

        $outputTask = $process.StandardOutput.ReadLineAsync()
        $errorTask = $process.StandardError.ReadLineAsync()
        while ($null -ne $outputTask -or $null -ne $errorTask) {
            $pendingTasks = New-Object 'System.Collections.Generic.List[System.Threading.Tasks.Task]'
            if ($null -ne $outputTask) { [void]$pendingTasks.Add($outputTask) }
            if ($null -ne $errorTask) { [void]$pendingTasks.Add($errorTask) }
            if ($pendingTasks.Count -eq 0) { break }

            $completedTask = [System.Threading.Tasks.Task]::WhenAny(
                $pendingTasks.ToArray()
            ).GetAwaiter().GetResult()

            if ($null -ne $outputTask -and
                [object]::ReferenceEquals($completedTask, $outputTask)) {
                $line = $outputTask.GetAwaiter().GetResult()
                if ($null -eq $line) {
                    $outputTask = $null
                }
                else {
                    $totalOutputLines++
                    Add-BoundedSerialProcessLine `
                        -Queue $outputQueue `
                        -CharacterCount ([ref]$outputCharacterCount) `
                        -Line ([string]$line) `
                        -MaximumLines $maximumOutputLines `
                        -MaximumCharacters $maximumOutputCharacters `
                        -MaximumLineCharacters $maximumCapturedLineCharacters
                    $outputTask = $process.StandardOutput.ReadLineAsync()
                }
            }

            if ($null -ne $errorTask -and
                [object]::ReferenceEquals($completedTask, $errorTask)) {
                $line = $errorTask.GetAwaiter().GetResult()
                if ($null -eq $line) {
                    $errorTask = $null
                }
                else {
                    $totalErrorLines++
                    Add-BoundedSerialProcessLine `
                        -Queue $errorQueue `
                        -CharacterCount ([ref]$errorCharacterCount) `
                        -Line ([string]$line) `
                        -MaximumLines $maximumErrorLines `
                        -MaximumCharacters $maximumErrorCharacters `
                        -MaximumLineCharacters $maximumCapturedLineCharacters
                    $errorTask = $process.StandardError.ReadLineAsync()
                }
            }
        }

        $process.WaitForExit()
        $outputLines = @($outputQueue.ToArray())
        $errorLines = @($errorQueue.ToArray())

        return [PSCustomObject]@{
            commandId        = [string]$Command.id
            processId        = [int]$process.Id
            exitCode         = [int]$process.ExitCode
            output           = $outputLines
            error            = $errorLines
            outputTruncated  = ($totalOutputLines -gt $outputLines.Count)
            errorTruncated   = ($totalErrorLines -gt $errorLines.Count)
            totalOutputLines = [int64]$totalOutputLines
            totalErrorLines  = [int64]$totalErrorLines
        }
    }
    finally {
        $process.Dispose()
    }
}

# Late override of the legacy native-pipeline implementation. This function is
# used by the scheduler whenever ThreadJob is unavailable, including the
# supported Windows PowerShell 5.1 package-validation host.
function Invoke-BackupFfmpegCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Command,
        [string]$JobId
    )

    if ([string]::IsNullOrWhiteSpace([string]$Command.executable) -or
        -not (Test-Path -LiteralPath ([string]$Command.executable) -PathType Leaf)) {
        throw 'ffmpeg executable was not found.'
    }

    $capture = Invoke-BackupBoundedSerialProcessCapture -Command $Command
    if ([int]$capture.exitCode -ne 0) {
        $errorTail = (@($capture.error) -join [Environment]::NewLine)
        if ($errorTail.Length -gt 4096) {
            $errorTail = $errorTail.Substring($errorTail.Length - 4096)
        }
        $suffix = if ([string]::IsNullOrWhiteSpace($errorTail)) {
            ''
        }
        else {
            " Error tail: $errorTail"
        }
        throw "ffmpeg command '$($Command.id)' failed with exit code $($capture.exitCode).$suffix"
    }

    return @($capture.output)
}
