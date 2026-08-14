# RS-1508: Process.ErrorDataReceived invokes PowerShell script blocks on .NET
# thread-pool threads that do not have a DefaultRunspace in embedded hosts.
# Read redirected stderr directly instead so backup workers remain safe in hosted runspaces.
function Start-BackupScheduledThreadJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Command
    )

    Start-ThreadJob `
        -Name ([string]$Command.id) `
        -ArgumentList $Command `
        -ScriptBlock {
            param($ScheduledCommand)

            function ConvertTo-BackupProcessArgumentText {
                param([string[]]$Arguments)

                $escaped = foreach ($argument in @($Arguments)) {
                    if ($argument -match '[\s"]') {
                        '"' + ($argument -replace '"', '\"') + '"'
                    }
                    else {
                        $argument
                    }
                }

                return ($escaped -join ' ')
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
                $processInfo.Arguments = ConvertTo-BackupProcessArgumentText -Arguments @($ScheduledCommand.arguments)
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

                $standardErrorTask = $process.StandardError.ReadToEndAsync()
                $lines = New-Object System.Collections.Generic.List[string]
                while (-not $process.StandardOutput.EndOfStream) {
                    $line = $process.StandardOutput.ReadLine()
                    if ($null -eq $line) {
                        continue
                    }
                    $lines.Add([string]$line)
                    if (-not [string]::IsNullOrWhiteSpace($progressLogPath)) {
                        Add-Content -LiteralPath $progressLogPath -Value ([string]$line) -Encoding UTF8
                    }
                }

                $process.WaitForExit()
                $standardError = [string]$standardErrorTask.GetAwaiter().GetResult()
                $errorLines = @(
                    $standardError -split "`r?`n" |
                        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                )
                $processId = [int]$process.Id
                $exitCode = [int]$process.ExitCode

                [PSCustomObject]@{
                    commandId = [string]$ScheduledCommand.id
                    processId = $processId
                    exitCode  = $exitCode
                    output    = @($lines.ToArray())
                    error     = @($errorLines)
                }
            }
            finally {
                $process.Dispose()
            }
        }
}
