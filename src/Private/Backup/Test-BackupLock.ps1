function Test-BackupLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,
        [Parameter()]
        [TimeSpan]$StaleThreshold = (New-TimeSpan -Hourse 24)
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
        $lock = Get-Content $lockPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-RenderKitLog -Level Error -Message "Backup lock exists but is corrupted: '$lockPath'."
        throw "Backup lock exists but is corrupted $lockPath"
    }

    $lockMachine = $null
    if ($lock.PSObject.Properties.Name -contains "machine") {
        $lockMachine = [string]$lock.machine
    }
    elseif ($lock.PSObject.Properties.Name -contains "maschine") {
        $lockMachine = [string]$lock.maschine
    }

    # stale lock detection is only safe for local-machine locks
    $isLocalMachine = [string]::IsNullOrWhiteSpace($lockMachine) -or
        $lockMachine.Equals($env:COMPUTERNAME, [System.StringComparison]::OrdinalIgnoreCase)

        $isStale = $false

    if ($isLocalMachine) {
        if ($lock.processId -and -not (Get-Process -Id $lock.processId -ErrorAction SilentlyContinue)) {
            $isStale = $true
        }
    }
    else {
        $lockAge = (Get-Date) - (Get-Item $lockPath).LastWriteTime
            if ($lockAge -gt $StaleThreshold) {
                $isStale = $true
                Write-RenderKitLog -Level Warning -Message "Lock originates from machine '$lockMachine' and is $([int]$lockAge.TotalHours)h old. Treating as stale."
            }
            else {
                Write-RenderKitLog -Level Warning -Message "Lock originates from machine '$lockMachine'. Cannot verify remote process. Lock age: $([int]$lockAge.TotalHours).h (threshold: $([int]$StaleThreshold.TotalHours)h)."
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
