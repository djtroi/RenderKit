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

    # RS-1514: PID checks are meaningful only when the lock positively identifies
    # the current machine and contains a usable positive PID. A missing/invalid
    # PID is not proof that a lock is alive; fall back to age-based ownership
    # uncertainty instead of keeping such a lock permanently active.
    $currentMachine = [System.Environment]::MachineName
    $isLocalMachine = -not [string]::IsNullOrWhiteSpace($lockMachine) -and
        $lockMachine.Equals(
            $currentMachine,
            [System.StringComparison]::OrdinalIgnoreCase
        )

    $lockProcessId = 0
    $hasUsableProcessId = $false
    if ($null -ne $lock.processId) {
        $parsedProcessId = 0
        if ([int]::TryParse([string]$lock.processId, [ref]$parsedProcessId) -and
            $parsedProcessId -gt 0) {
            $lockProcessId = $parsedProcessId
            $hasUsableProcessId = $true
        }
    }

    $isStale = $false

    if ($isLocalMachine -and $hasUsableProcessId) {
        if (-not (Get-Process -Id $lockProcessId -ErrorAction SilentlyContinue)) {
            $isStale = $true
        }
    }
    else {
        $lockAge = (Get-Date) - (
            Get-Item -LiteralPath $lockPath -ErrorAction Stop
        ).LastWriteTime
        $displayMachine = if ([string]::IsNullOrWhiteSpace($lockMachine)) {
            'unknown-machine'
        }
        else {
            $lockMachine
        }
        $ownershipReason = if ($isLocalMachine) {
            "local lock has no usable process id"
        }
        else {
            "lock process cannot be verified on this machine"
        }

        if ($lockAge -gt $StaleThreshold) {
            $isStale = $true
            Write-RenderKitLog `
                -Level Warning `
                -Message ("Lock from '{0}' is {1}h old and {2}. Treating as stale." -f
                    $displayMachine,
                    [int]$lockAge.TotalHours,
                    $ownershipReason)
        }
        else {
            Write-RenderKitLog `
                -Level Warning `
                -Message ("Lock from '{0}' is {1}h old and {2}. Keeping it active until the {3}h stale threshold." -f
                    $displayMachine,
                    [int]$lockAge.TotalHours,
                    $ownershipReason,
                    [int]$StaleThreshold.TotalHours)
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
