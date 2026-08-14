function Get-BackupLockPath {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    # Build each path segment separately. A backslash inside ChildPath is a
    # directory separator on Windows but a valid filename character on Unix,
    # which can place the lock outside the intended .renderkit directory.
    $metadataRoot = Join-Path -Path $ProjectRoot -ChildPath '.renderkit'
    return Join-Path -Path $metadataRoot -ChildPath 'backup.lock'
}
