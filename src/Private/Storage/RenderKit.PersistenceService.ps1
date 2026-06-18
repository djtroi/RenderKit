function Enter-RenderKitFileLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [ValidateRange(1, 300000)]
        [int]$TimeoutMilliseconds = 10000,

        [ValidateRange(10, 5000)]
        [int]$RetryMilliseconds = 100
    )

    $targetPath = [System.IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Path $targetPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-RenderKitStorageDirectory -Path $parent | Out-Null
    }

    $lockPath = "$targetPath.lock"
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $lastError = $null

    while ($stopwatch.ElapsedMilliseconds -lt $TimeoutMilliseconds) {
        try {
            $stream = [System.IO.File]::Open(
                $lockPath,
                [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None
            )

            return [PSCustomObject]@{
                TargetPath = $targetPath
                LockPath = $lockPath
                Stream = $stream
                AcquiredAtUtc = [DateTime]::UtcNow
            }
        }
        catch [System.IO.IOException] {
            $lastError = $_
            Start-Sleep -Milliseconds $RetryMilliseconds
        }
        catch [System.UnauthorizedAccessException] {
            throw "RenderKit cannot acquire file lock '$lockPath': $($_.Exception.Message)"
        }
    }

    $message = "Timed out after $TimeoutMilliseconds ms waiting for file lock '$lockPath'."
    if ($lastError) {
        $message = "$message $($lastError.Exception.Message)"
    }
    throw $message
}

function Exit-RenderKitFileLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$LockHandle
    )

    if ($LockHandle.Stream) {
        $LockHandle.Stream.Dispose()
    }
}

function Test-RenderKitJsonValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Value,

        [scriptblock]$Validator,

        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not $Validator) {
        return
    }

    $validationResult = & $Validator $Value
    if ($validationResult -eq $false) {
        throw "JSON validation failed for '$Path'."
    }
}

function Read-RenderKitJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [ValidateRange(1, 1073741824)]
        [long]$MaximumBytes = 10485760,

        [scriptblock]$Validator,

        [switch]$AllowMissing
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        if ($AllowMissing) {
            return $null
        }
        throw "JSON file not found: '$resolvedPath'."
    }

    $item = Get-Item -LiteralPath $resolvedPath -ErrorAction Stop
    if ($item.Length -gt $MaximumBytes) {
        throw "JSON file '$resolvedPath' exceeds the $MaximumBytes byte limit."
    }

    try {
        $value = Get-Content -LiteralPath $resolvedPath -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Invalid JSON in '$resolvedPath': $($_.Exception.Message)"
    }

    if ($null -eq $value) {
        throw "JSON file '$resolvedPath' contains a null root value."
    }

    Test-RenderKitJsonValue `
        -Value $value `
        -Validator $Validator `
        -Path $resolvedPath

    return $value
}

function Write-RenderKitJsonFileCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Path,

        [ValidateRange(1, 100)]
        [int]$Depth = 20,

        [scriptblock]$Validator,

        [switch]$SkipBackup
    )

    $targetPath = [System.IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Path $targetPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-RenderKitStorageDirectory -Path $parent | Out-Null
    }

    $temporaryPath = '{0}.tmp.{1}.{2}' -f (
        $targetPath,
        $PID,
        [guid]::NewGuid().ToString('N')
    )
    $backupPath = "$targetPath.bak"
    $encoding = New-Object System.Text.UTF8Encoding($false)

    try {
        $json = $Value | ConvertTo-Json -Depth $Depth -ErrorAction Stop
        $jsonBytes = $encoding.GetBytes($json)
        $temporaryStream = $null
        try {
            $temporaryStream = [System.IO.File]::Open(
                $temporaryPath,
                [System.IO.FileMode]::CreateNew,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::None
            )
            $temporaryStream.Write($jsonBytes, 0, $jsonBytes.Length)
            $temporaryStream.Flush($true)
        }
        finally {
            if ($temporaryStream) {
                $temporaryStream.Dispose()
            }
        }

        $validatedValue = Read-RenderKitJsonFile `
            -Path $temporaryPath `
            -Validator $Validator

        if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
            $currentValueIsValid = $true
            try {
                Read-RenderKitJsonFile `
                    -Path $targetPath `
                    -Validator $Validator |
                    Out-Null
            }
            catch {
                $currentValueIsValid = $false
            }

            if ($SkipBackup) {
                try {
                    [System.IO.File]::Replace(
                        $temporaryPath,
                        $targetPath,
                        $null,
                        $true
                    )
                }
                catch {
                    [System.IO.File]::Copy(
                        $temporaryPath,
                        $targetPath,
                        $true
                    )
                }
            }
            else {
                try {
                    $replacementBackupPath = if ($currentValueIsValid) {
                        $backupPath
                    }
                    else {
                        $null
                    }
                    [System.IO.File]::Replace(
                        $temporaryPath,
                        $targetPath,
                        $replacementBackupPath,
                        $true
                    )
                }
                catch {
                    if ($currentValueIsValid) {
                        $backupTemporaryPath = '{0}.tmp.{1}.{2}' -f (
                            $backupPath,
                            $PID,
                            [guid]::NewGuid().ToString('N')
                        )
                        try {
                            Copy-Item -LiteralPath $targetPath `
                                -Destination $backupTemporaryPath `
                                -Force `
                                -ErrorAction Stop
                            Move-Item -LiteralPath $backupTemporaryPath `
                                -Destination $backupPath `
                                -Force `
                                -ErrorAction Stop
                        }
                        finally {
                            if (Test-Path -LiteralPath $backupTemporaryPath) {
                                Remove-Item -LiteralPath $backupTemporaryPath `
                                    -Force `
                                    -ErrorAction SilentlyContinue
                            }
                        }
                    }

                    [System.IO.File]::Copy(
                        $temporaryPath,
                        $targetPath,
                        $true
                    )
                }
            }
        }
        else {
            Move-Item -LiteralPath $temporaryPath `
                -Destination $targetPath `
                -ErrorAction Stop
        }

        return $validatedValue
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath `
                -Force `
                -ErrorAction SilentlyContinue
        }
    }
}

function Write-RenderKitJsonFileAtomic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Path,

        [ValidateRange(1, 100)]
        [int]$Depth = 20,

        [scriptblock]$Validator,

        [ValidateRange(1, 300000)]
        [int]$LockTimeoutMilliseconds = 10000
    )

    $lockHandle = Enter-RenderKitFileLock `
        -Path $Path `
        -TimeoutMilliseconds $LockTimeoutMilliseconds
    try {
        return Write-RenderKitJsonFileCore `
            -Value $Value `
            -Path $Path `
            -Depth $Depth `
            -Validator $Validator
    }
    finally {
        Exit-RenderKitFileLock -LockHandle $lockHandle
    }
}

function Invoke-RenderKitJsonFileTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [object]$DefaultValue,

        [Parameter(Mandatory)]
        [scriptblock]$Update,

        [ValidateRange(1, 100)]
        [int]$Depth = 20,

        [scriptblock]$Validator,

        [ValidateRange(1, 300000)]
        [int]$LockTimeoutMilliseconds = 10000
    )

    $lockHandle = Enter-RenderKitFileLock `
        -Path $Path `
        -TimeoutMilliseconds $LockTimeoutMilliseconds
    try {
        $currentValue = Read-RenderKitJsonFile `
            -Path $Path `
            -Validator $Validator `
            -AllowMissing
        if ($null -eq $currentValue) {
            $currentValue = $DefaultValue
        }

        $updatedValue = & $Update $currentValue
        if ($null -eq $updatedValue) {
            throw "JSON transaction for '$Path' returned no value."
        }

        return Write-RenderKitJsonFileCore `
            -Value $updatedValue `
            -Path $Path `
            -Depth $Depth `
            -Validator $Validator
    }
    finally {
        Exit-RenderKitFileLock -LockHandle $lockHandle
    }
}

function Restore-RenderKitJsonFileBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [ValidateRange(1, 100)]
        [int]$Depth = 20,

        [scriptblock]$Validator,

        [ValidateRange(1, 300000)]
        [int]$LockTimeoutMilliseconds = 10000
    )

    $targetPath = [System.IO.Path]::GetFullPath($Path)
    $backupPath = "$targetPath.bak"
    $lockHandle = Enter-RenderKitFileLock `
        -Path $targetPath `
        -TimeoutMilliseconds $LockTimeoutMilliseconds
    try {
        $backupValue = Read-RenderKitJsonFile `
            -Path $backupPath `
            -Validator $Validator

        return Write-RenderKitJsonFileCore `
            -Value $backupValue `
            -Path $targetPath `
            -Depth $Depth `
            -Validator $Validator `
            -SkipBackup
    }
    finally {
        Exit-RenderKitFileLock -LockHandle $lockHandle
    }
}
