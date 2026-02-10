function Acquire-BackupLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    $lockPath = Get-BackupLockPath -ProjectRoot $ProjectRoot
    $lockDir = Split-Path $lockPath 

    if (!(Test-Path $lockDir)){
        throw "RenderKit folder missing - invalid RenderKit project"
    }

    $state = Test-BackupLock -ProjectRoot $ProjectRoot

    if ($state.IsLocked) {
        throw "Backup already runnin (PID $($state.Lock.processId) on $($state.Lock.maschine))"
    }

    $lock = @{
        lockType        = "backup"
        lockedAt        = (Get-Date).ToString("o")
        processId       = $PID 
        maschine        = $ENV:COMPUTERNAME
        user            = $ENV:USERNAME
        toolVersion     = $script:ModuleVersion
    }

    $lock |
        ConvertTo-Json |
        Set-Content -Path $lockPath -Encoding UTF8
}