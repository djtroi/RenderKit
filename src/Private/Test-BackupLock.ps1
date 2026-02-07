function Test-BackupLock {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    $lockPath = Get-BackupLockPath -ProjectRoot $ProjectRoot

    if (!(Test-Path $lockPath)) { return $False }

    try {
        $lock = Get-Content $lockPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Backup lock exists but is corrupted $lockPath"
    }

    #Stale lock detection

    if ($lock.processId -and -not (Get-Process -Id $lock.processId -ErrorAction SilentlyContinue)) {
        return @{
            IsLocked        = $False
            IsStale         = $True
            Lock            = $lock
        }
    }

    return @{
        IsLocked            = $True
        IsStale             = $False
        Lock                = $lock
    }
}
