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
        Write-RenderKitLog -Level Error -Message "Backup lock already present for '$ProjectRoot' (PID $($state.Lock.processId) on $($state.Lock.maschine))."
        throw "Backup already runnin (PID $($state.Lock.processId) on $($state.Lock.maschine))"
    }

    $lock = @{
        lockType        = "backup"
        lockedAt        = (Get-Date).ToString("o")
        processId       = $PID 
        maschine        = $ENV:COMPUTERNAME
        user            = $ENV:USERNAME
        toolVersion     = $script:RenderKitModuleVersion
    }

    $lock |
        ConvertTo-Json |
        Set-Content -Path $lockPath -Encoding UTF8
}
