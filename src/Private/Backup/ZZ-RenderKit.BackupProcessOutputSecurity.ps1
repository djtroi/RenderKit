# RS-1571: This late-loaded implementation replaces the legacy backup process
# worker with bounded output capture. Encoder runtime itself remains unbounded:
# long-running media encodes are valid, but diagnostics and progress storage are
# not allowed to grow without limit.
function ConvertTo-BackupBoundedProcessArgumentText {
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

function Start-BackupScheduledThreadJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Command
    )

    $fallbackArgumentTextForJob = ConvertTo-BackupBoundedProcessArgumentText `
        -Arguments @($Command.arguments)
    $scheduledCommandForJob = $Command

    Start-ThreadJob `
        -Name ([string]$Command.id) `
        -ScriptBlock {
            $ScheduledCommand = $using:scheduledCommandForJob
            $FallbackArgumentText = $using:fallbackArgumentTextForJob

            $maximumCapturedLineCharacters = 16384
            $maximumOutputLines = 2048
            $maximumOutputCharacters = 1048576
            $maximumErrorLines = 1024
            $maximumErrorCharacters = 524288
            $maximumProgressLogBytes = 1048576
            $progressTailLines = 512

            function Add-BoundedBackupProcessLine {
                param(
                    [Parameter(Mandatory)]$Queue,
                    [Parameter(Mandatory)][ref]$CharacterCount,
                    [AllowNull()][string]$Line,
                    [Parameter(Mandatory)][int]$MaximumLines,
                    [Parameter(Mandatory)][int]$MaximumCharacters,
                    [Parameter(Mandatory)][int]$MaximumLineCharacters
                )

                if ($null -eq $Line) {
                    return $null
                }
                $boundedLine = [string]$Line
                if ($boundedLine.Length -gt $MaximumLineCharacters) {
                    $boundedLine = $boundedLine.Substring(0, $MaximumLineCharacters) + '… [line truncated]'
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
                return $boundedLine
            }

            function Write-BoundedBackupProgressLine {
                param(
                    [AllowNull()][string]$Path,
                    [AllowNull()][string]$Line,
                    [Parameter(Mandatory)]$TailQueue,
                    [Parameter(Mandatory)][int64]$MaximumBytes,
                    [Parameter(Mandatory)][int]$MaximumTailLines
                )

                if ([string]::IsNullOrWhiteSpace($Path) -or $null -eq $Line) {
                    return
                }
                $TailQueue.Enqueue([string]$Line)
                while ($TailQueue.Count -gt $MaximumTailLines) {
                    [void]$TailQueue.Dequeue()
                }

                Add-Content -LiteralPath $Path -Value ([string]$Line) -Encoding UTF8
                try {
                    $length = [System.IO.FileInfo]::new($Path).Length
                    if ($length -gt $MaximumBytes) {
                        Set-Content `
                            -LiteralPath $Path `
                            -Value @($TailQueue.ToArray()) `
                            -Encoding UTF8
                    }
                }
                catch {
                    # Progress reporting is observational and must never abort a
                    # valid encode. A later line will retry compaction.
                    Write-Verbose "Progress log compaction failed: $($_.Exception.Message)"
                }
            }

            $progressLogPath = if ($ScheduledCommand.progress -and $ScheduledCommand.progress.logPath) {
                [string]$ScheduledCommand.progress.logPath
            }
            else {
                $null
            }
            if (-not [string]::IsNullOrWhiteSpace($progressLogPath)) {
                $progressFolder = Split-Path -Path $progressLogPath -Parent
                if (-not [string]::IsNullOrWhiteSpace($progressFolder) -and
                    -not (Test-Path -LiteralPath $progressFolder -PathType Container)) {
                    New-Item -ItemType Directory -Path $progressFolder -Force | Out-Null
                }
                Set-Content -LiteralPath $progressLogPath -Value @() -Encoding UTF8
            }

            $pidPath = if ($ScheduledCommand.progress -and $ScheduledCommand.progress.pidPath) {
                [string]$ScheduledCommand.progress.pidPath
            }
            else {
                $null
            }

            $failureSimulation = if ($ScheduledCommand.PSObject.Properties.Name -contains 'failureSimulation') {
                $ScheduledCommand.failureSimulation
            }
            else {
                $null
            }
            $scenarios = @()
            if ($failureSimulation -and $failureSimulation.PSObject.Properties.Name -contains 'scenarios') {
                $scenarios = @($failureSimulation.scenarios | ForEach-Object { [string]$_ })
            }
            elseif ($failureSimulation -and $failureSimulation.PSObject.Properties.Name -contains 'scenario') {
                $scenarios = @([string]$failureSimulation.scenario)
            }
            $failAttempts = if ($failureSimulation -and $failureSimulation.PSObject.Properties.Name -contains 'failAttempts') {
                [Math]::Max(1, [int]$failureSimulation.failAttempts)
            }
            else {
                1
            }
            $attempt = if ($ScheduledCommand.control -and $ScheduledCommand.control.PSObject.Properties.Name -contains 'attempts') {
                [int]$ScheduledCommand.control.attempts
            }
            elseif ($ScheduledCommand.PSObject.Properties.Name -contains 'attempts') {
                [int]$ScheduledCommand.attempts
            }
            else {
                1
            }
            if ($failureSimulation -and
                ($failureSimulation.PSObject.Properties.Name -notcontains 'enabled' -or [bool]$failureSimulation.enabled) -and
                $scenarios -contains 'CorruptChunk' -and
                $attempt -le $failAttempts) {
                [PSCustomObject]@{
                    commandId = [string]$ScheduledCommand.id
                    processId = 0
                    exitCode  = 23
                    output    = @()
                    error     = @("Simulated corrupt encoded chunk for command '$($ScheduledCommand.id)' on attempt $attempt.")
                    outputTruncated = $false
                    errorTruncated = $false
                }
                return
            }

            $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
            $processInfo.FileName = [string]$ScheduledCommand.executable
            $processInfo.UseShellExecute = $false
            $processInfo.RedirectStandardOutput = $true
            $processInfo.RedirectStandardError = $true
            $processInfo.CreateNoWindow = $true
            try {
                foreach ($argument in @($ScheduledCommand.arguments)) {
                    $processInfo.ArgumentList.Add([string]$argument)
                }
            }
            catch {
                $processInfo.Arguments = [string]$FallbackArgumentText
            }

            $process = [System.Diagnostics.Process]::new()
            $process.StartInfo = $processInfo
            try {
                [void]$process.Start()
                if (-not [string]::IsNullOrWhiteSpace($pidPath)) {
                    $pidFolder = Split-Path -Path $pidPath -Parent
                    if (-not [string]::IsNullOrWhiteSpace($pidFolder) -and
                        -not (Test-Path -LiteralPath $pidFolder -PathType Container)) {
                        New-Item -ItemType Directory -Path $pidFolder -Force | Out-Null
                    }
                    Set-Content -LiteralPath $pidPath -Value ([string]$process.Id) -Encoding UTF8
                }

                $outputQueue = New-Object 'System.Collections.Generic.Queue[string]'
                $errorQueue = New-Object 'System.Collections.Generic.Queue[string]'
                $progressQueue = New-Object 'System.Collections.Generic.Queue[string]'
                $outputCharacterCount = 0
                $errorCharacterCount = 0
                $totalOutputLines = 0
                $totalErrorLines = 0

                $outputTask = $process.StandardOutput.ReadLineAsync()
                $errorTask = $process.StandardError.ReadLineAsync()
                while ($null -ne $outputTask -or $null -ne $errorTask) {
                    $pendingTasks = New-Object 'System.Collections.Generic.List[System.Threading.Tasks.Task]'
                    if ($null -ne $outputTask) { $pendingTasks.Add($outputTask) }
                    if ($null -ne $errorTask) { $pendingTasks.Add($errorTask) }
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
                            $boundedLine = Add-BoundedBackupProcessLine `
                                -Queue $outputQueue `
                                -CharacterCount ([ref]$outputCharacterCount) `
                                -Line ([string]$line) `
                                -MaximumLines $maximumOutputLines `
                                -MaximumCharacters $maximumOutputCharacters `
                                -MaximumLineCharacters $maximumCapturedLineCharacters
                            Write-BoundedBackupProgressLine `
                                -Path $progressLogPath `
                                -Line $boundedLine `
                                -TailQueue $progressQueue `
                                -MaximumBytes $maximumProgressLogBytes `
                                -MaximumTailLines $progressTailLines
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
                            Add-BoundedBackupProcessLine `
                                -Queue $errorQueue `
                                -CharacterCount ([ref]$errorCharacterCount) `
                                -Line ([string]$line) `
                                -MaximumLines $maximumErrorLines `
                                -MaximumCharacters $maximumErrorCharacters `
                                -MaximumLineCharacters $maximumCapturedLineCharacters |
                                Out-Null
                            $errorTask = $process.StandardError.ReadLineAsync()
                        }
                    }
                }

                $process.WaitForExit()
                $processId = [int]$process.Id
                $exitCode = [int]$process.ExitCode
                $outputLines = @($outputQueue.ToArray())
                $errorLines = @($errorQueue.ToArray())

                [PSCustomObject]@{
                    commandId = [string]$ScheduledCommand.id
                    processId = $processId
                    exitCode  = $exitCode
                    output    = $outputLines
                    error     = $errorLines
                    outputTruncated = ($totalOutputLines -gt $outputLines.Count)
                    errorTruncated = ($totalErrorLines -gt $errorLines.Count)
                    totalOutputLines = [int64]$totalOutputLines
                    totalErrorLines = [int64]$totalErrorLines
                }
            }
            finally {
                $process.Dispose()
            }
        }
}
