function Test-BackupLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,
        [Parameter()]
        [TimeSpan]$StaleThreshold = (New-TimeSpan -Hours 24)
    )

    $lockPath = Get-BackupLockPath -ProjectRoot $ProjectRoot

    if (-not (Test-Path -Path $lockPath -PathType Leaf)) {
        return [PSCustomObject]@{
            Exists   = $false
            IsLocked = $false
            IsStale  = $false
            LockPath = $lockPath
            Lock     = $null
        }
    }

    try {
        $lock = Get-Content -LiteralPath $lockPath -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        # Parsing failure is reported by the terminating exception below; keep
        # the diagnostic log off the error stream to avoid a duplicate record.
        Write-RenderKitLog `
            -Level Error `
            -Message "Backup lock exists but is corrupted: '$lockPath'." `
            -NoConsole
        throw "Backup lock exists but is corrupted $lockPath"
    }

    $lockMachine = $null
    if ($lock.PSObject.Properties.Name -contains "machine") {
        $lockMachine = [string]$lock.machine
    }
    elseif ($lock.PSObject.Properties.Name -contains "maschine") {
        $lockMachine = [string]$lock.maschine
    }

    # PID checks are meaningful only for a lock that positively identifies the
    # current machine. Legacy/foreign locks without machine identity are treated
    # as remote and may become stale only by age; guessing "local" can delete an
    # active lock on a shared project path when another host happens to use it.
    $currentMachine = [System.Environment]::MachineName
    $isLocalMachine = -not [string]::IsNullOrWhiteSpace($lockMachine) -and
        $lockMachine.Equals(
            $currentMachine,
            [System.StringComparison]::OrdinalIgnoreCase
        )

    $isStale = $false

    if ($isLocalMachine) {
        if ($lock.processId -and -not (Get-Process -Id $lock.processId -ErrorAction SilentlyContinue)) {
            $isStale = $true
        }
    }
    else {
        $lockAge = (Get-Date) - (Get-Item -LiteralPath $lockPath -ErrorAction Stop).LastWriteTime
        $displayMachine = if ([string]::IsNullOrWhiteSpace($lockMachine)) {
            'unknown-machine'
        }
        else {
            $lockMachine
        }

        if ($lockAge -gt $StaleThreshold) {
            $isStale = $true
            Write-RenderKitLog `
                -Level Warning `
                -Message "Lock originates from machine '$displayMachine' and is $([int]$lockAge.TotalHours)h old. Treating as stale."
        }
        else {
            Write-RenderKitLog `
                -Level Warning `
                -Message "Lock originates from machine '$displayMachine'. Cannot verify remote process. Lock age: $([int]$lockAge.TotalHours)h (threshold: $([int]$StaleThreshold.TotalHours)h)."
        }
    }

    if ($isStale) {
        return [PSCustomObject]@{
            Exists      = $true
            IsLocked    = $false
            IsStale     = $true
            LockPath    = $lockPath
            Lock        = $lock
        }
    }

    return [PSCustomObject]@{
        Exists   = $true
        IsLocked = $true
        IsStale  = $false
        LockPath = $lockPath
        Lock     = $lock
    }
}
