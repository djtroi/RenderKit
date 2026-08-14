# RS-1508: Keep the hardware encoder probe compatible with Windows PowerShell 5.1
# while preserving the hosted-runspace-safe process handling used by newer runtimes.
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

    function ConvertTo-BackupProbeArgumentText {
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

    $arguments = @(
        '-hide_banner',
        '-loglevel', 'error',
        '-f', 'lavfi',
        '-i', 'color=c=black:s=640x360:d=0.1',
        '-frames:v', '1',
        '-an',
        '-c:v', $EncoderName,
        '-f', 'null',
        '-'
    )

    $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $processInfo.FileName = $FfmpegPath
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.CreateNoWindow = $true

    if ($processInfo.PSObject.Properties.Name -contains 'ArgumentList') {
        foreach ($argument in $arguments) {
            $processInfo.ArgumentList.Add([string]$argument)
        }
    }
    else {
        $processInfo.Arguments = ConvertTo-BackupProbeArgumentText -Arguments $arguments
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $processInfo
    try {
        [void]$process.Start()
        $standardOutputTask = $process.StandardOutput.ReadToEndAsync()
        $standardErrorTask = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $supportsTreeKill = @($process.PSObject.Methods['Kill'].OverloadDefinitions) |
                Where-Object {
                    [string]$_ -match '(?:System\.)?(?:Boolean|bool)\s+entireProcessTree'
                } |
                Select-Object -First 1

            if ($supportsTreeKill) {
                $process.Kill($true)
            }
            else {
                $process.Kill()
            }
            $process.WaitForExit()

            $outputText = [string]$standardOutputTask.GetAwaiter().GetResult()
            $errorText = [string]$standardErrorTask.GetAwaiter().GetResult()
            $detail = if (-not [string]::IsNullOrWhiteSpace($errorText)) {
                $errorText.Trim()
            }
            elseif (-not [string]::IsNullOrWhiteSpace($outputText)) {
                $outputText.Trim()
            }
            else {
                $null
            }

            return [PSCustomObject]@{
                encoderName = $EncoderName
                usable      = $false
                exitCode    = $null
                reason      = 'ProbeTimedOut'
                error       = if ($detail) {
                    "Encoder probe exceeded $TimeoutSeconds second(s). $detail"
                }
                else {
                    "Encoder probe exceeded $TimeoutSeconds second(s)."
                }
            }
        }

        $outputText = [string]$standardOutputTask.GetAwaiter().GetResult()
        $errorText = [string]$standardErrorTask.GetAwaiter().GetResult()
        return [PSCustomObject]@{
            encoderName = $EncoderName
            usable      = $process.ExitCode -eq 0
            exitCode    = [int]$process.ExitCode
            reason      = if ($process.ExitCode -eq 0) {
                'ProbeSucceeded'
            }
            else {
                'ProbeFailed'
            }
            error       = if ([string]::IsNullOrWhiteSpace($errorText)) {
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
            usable      = $false
            exitCode    = $null
            reason      = 'ProbeFailed'
            error       = $_.Exception.Message
        }
    }
    finally {
        $process.Dispose()
    }
}
