function Get-BackupLockPath {
    param(
        [Parameter(Mandatory)]
        {ystring}$ProjectRoot
    )

    return Join-Path $ProjectRoot ".rencerkit\backup.lock"
}