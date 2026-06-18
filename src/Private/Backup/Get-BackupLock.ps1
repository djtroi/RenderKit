function Get-BackupLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    Write-RenderKitLog -Level Debug -Message "Get-BackupLock started for '$ProjectRoot'."

    $lockPath = Get-BackupLockPath -ProjectRoot $ProjectRoot
    $lockDir = Split-Path $lockPath

    if (!(Test-Path $lockDir)){
        Write-RenderKitLog -Level Error -Message "RenderKit metadata folder is missing for project '$ProjectRoot'."
        throw "RenderKit folder missing - invalid RenderKit project"
    }

    $state = Test-BackupLock -ProjectRoot $ProjectRoot

    if ($state.IsLocked) {
        $machine = if ($state.Lock.PSObject.Properties.Name -contains "machine") {
            [string]$state.Lock.machine
        }
        elseif ($state.Lock.PSObject.Properties.Name -contains "maschine") {
            [string]$state.Lock.maschine
        }
        else {
            "unknown-machine"
        }

        Write-RenderKitLog -Level Error -Message "Backup lock already present for '$ProjectRoot' (PID $($state.Lock.processId) on $machine)."
        throw "Backup already running (PID $($state.Lock.processId) on $machine)."
    }

    if ($state.IsStale -and (Test-Path -Path $lockPath -PathType Leaf)) {
        Write-RenderKitLog -Level Warning -Message "Removing stale backup lock at '$lockPath'."
        Remove-Item -Path $lockPath -Force -ErrorAction Stop
    }

    $ownerToken = [guid]::NewGuid().ToString()
    $lock = @{
        lockType        = "backup"
        lockedAt        = (Get-Date).ToString("o")
        ownerToken      = $ownerToken
        processId       = $PID
        machine         = $ENV:COMPUTERNAME
        maschine        = $ENV:COMPUTERNAME
        user            = $ENV:USERNAME
        toolVersion     = $script:RenderKitModuleVersion
    }

    $lockJson = $lock | ConvertTo-Json -Depth 5 -ErrorAction Stop
    $encoding = New-Object System.Text.UTF8Encoding($false)
    $lockBytes = $encoding.GetBytes($lockJson)
    $lockStream = $null
    try {
        $lockStream = [System.IO.File]::Open(
            $lockPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        $lockStream.Write($lockBytes, 0, $lockBytes.Length)
        $lockStream.Flush()
    }
    catch [System.IO.IOException] {
        throw "Backup lock was acquired concurrently for '$ProjectRoot'."
    }
    finally {
        if ($lockStream) {
            $lockStream.Dispose()
        }
    }

    return [PSCustomObject]@{
        ProjectRoot = $ProjectRoot
        LockPath    = $lockPath
        OwnerToken  = $ownerToken
        LockedAt    = $lock.lockedAt
    }
}
