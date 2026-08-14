function Write-RenderKitWorkerLogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WorkerId,
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('Info', 'Debug', 'Warning', 'Error')]
        [string]$Level = 'Info',
        [string]$JobId,
        [string]$LogPath
    )

    # RS-1513: Worker diagnostics are strictly best-effort and must never become
    # worker control flow. Path resolution belongs inside the same protected
    # boundary as directory creation and file writes; otherwise a failing default
    # log-path resolver can still terminate an otherwise healthy worker tick.
    try {
        if ([string]::IsNullOrWhiteSpace($LogPath)) {
            $LogPath = Get-RenderKitWorkerLogPath -WorkerId $WorkerId
        }

        $logRoot = Split-Path -Path $LogPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($logRoot) -and
            -not (Test-Path -LiteralPath $logRoot -PathType Container)) {
            New-Item `
                -ItemType Directory `
                -Path $logRoot `
                -Force `
                -ErrorAction Stop |
                Out-Null
        }

        $entry = [ordered]@{
            timestampUtc = (Get-Date).ToUniversalTime().ToString('o')
            level        = $Level
            workerId     = $WorkerId
            jobId        = $JobId
            message      = $Message
        }
        Add-Content `
            -LiteralPath $LogPath `
            -Value (($entry | ConvertTo-Json -Compress -Depth 10)) `
            -Encoding UTF8 `
            -ErrorAction Stop

        return $LogPath
    }
    catch {
        # Explicit Continue prevents caller-level WarningPreference=Stop from
        # turning this diagnostic fallback back into a worker failure.
        $displayPath = if ([string]::IsNullOrWhiteSpace($LogPath)) {
            '<default worker log>'
        }
        else {
            $LogPath
        }
        Write-Warning `
            -Message ("RenderKit could not write worker log '{0}': {1}" -f
                $displayPath,
                $_.Exception.Message) `
            -WarningAction Continue
        return $null
    }
}
