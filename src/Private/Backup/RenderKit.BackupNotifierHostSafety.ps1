# RS-1508: A notifier records diagnostics about a job failure; it must not create
# a second PowerShell ErrorRecord that can mask the original failure for hosts
# that inspect the error stream independently from normal command output.
function Invoke-BackupLogNotifierAdapter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context
    )

    $isFailure = [string]$Context.eventName -eq 'JobFailed'
    $level = if ($isFailure) { 'Error' } else { 'Info' }
    $jobId = if ($Context.job) { [string]$Context.job.id } else { $null }
    $message = "Backup notification '$($Context.eventName)' for job '$jobId'."

    if ($isFailure) {
        Write-RenderKitLog -Level $level -Message $message -NoConsole
    }
    else {
        Write-RenderKitLog -Level $level -Message $message
    }

    return [PSCustomObject]@{
        delivered = $true
        channel   = 'RenderKitLog'
        message   = $message
    }
}
