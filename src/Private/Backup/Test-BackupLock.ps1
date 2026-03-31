function Test-BackupLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
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

    if ($isLocalMachine -and $lock.processId -and -not (Get-Process -Id $lock.processId -ErrorAction SilentlyContinue)) {
        return [PSCustomObject]@{
            Exists   = $true
            IsLocked = $false
            IsStale  = $true
            LockPath = $lockPath
            Lock     = $lock
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
