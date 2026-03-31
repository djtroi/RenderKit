function Unlock-BackupLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,
        [string]$OwnerToken,
        [switch]$Force
    )

    $lockPath = Get-BackupLockPath -ProjectRoot $ProjectRoot

    if (-not (Test-Path -Path $lockPath -PathType Leaf)) {
        return $false
    }

    if ($Force) {
        Remove-Item -Path $lockPath -Force
        return $true
    }

    $lock = $null
    try {
        $lock = Get-Content -Path $lockPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Warning "Backup lock at '$lockPath' is unreadable. Use -Force to remove it."
        return $false
    }

    if (-not [string]::IsNullOrWhiteSpace($OwnerToken)) {
        $currentOwner = if ($lock.PSObject.Properties.Name -contains "ownerToken") {
            [string]$lock.ownerToken
        }
        else {
            ""
        }

        if ([string]::IsNullOrWhiteSpace($currentOwner) -or
            -not $currentOwner.Equals($OwnerToken, [System.StringComparison]::Ordinal)) {
            Write-Warning "Backup lock at '$lockPath' is owned by a different process. Unlock skipped."
            return $false
        }

        Remove-Item -Path $lockPath -Force
        return $true
    }

    if ($lock.PSObject.Properties.Name -contains "ownerToken" -and
        -not [string]::IsNullOrWhiteSpace([string]$lock.ownerToken)) {
        Write-Warning "Backup lock at '$lockPath' requires -OwnerToken for safe unlock."
        return $false
    }

    Remove-Item -Path $lockPath -Force
    return $true
}
