function Release-BackupLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    $lockPath = Get-BackupLockPath -ProjectRoot $ProjectRoot

    if (Test-Path $lockPath) {
        Remove-Item -Path $lockPath -Force 
    }
}