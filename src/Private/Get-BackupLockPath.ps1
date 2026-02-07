function Get-BackupLockPath {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    return Join-Path $ProjectRoot ".rencerkit\backup.lock"
}