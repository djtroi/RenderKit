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

    # Worker diagnostics are best-effort and must never become worker control
    # flow. The persisted worker/job state remains the durable source of truth
    # if a log path disappears, becomes read-only, or is temporarily unavailable.
    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        $LogPath = Get-RenderKitWorkerLogPath -WorkerId $WorkerId
    }

    try {
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
        # Explicit Continue prevents a caller-level WarningPreference=Stop from
        # turning this diagnostic fallback back into a worker failure.
        Write-Warning `
            -Message ("RenderKit could not write worker log '{0}': {1}" -f
                $LogPath,
                $_.Exception.Message) `
            -WarningAction Continue
        return $null
    }
}
