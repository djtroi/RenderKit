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
        # The following throw is the canonical PowerShell failure. Keep the
        # diagnostic log file-only so hosted callers do not receive a second,
        # non-terminating ErrorRecord for the same failure.
        Write-RenderKitLog `
            -Level Error `
            -Message "RenderKit metadata folder is missing for project '$ProjectRoot'." `
            -NoConsole
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

        Write-RenderKitLog `
            -Level Error `
            -Message "Backup lock already present for '$ProjectRoot' (PID $($state.Lock.processId) on $machine)." `
            -NoConsole
        throw "Backup already running (PID $($state.Lock.processId) on $machine)."
    }

    # Environment.MachineName/UserName are populated consistently across the
    # supported PowerShell platforms. COMPUTERNAME/USERNAME are Windows-centric
    # and can be empty on Unix, which makes shared-path lock ownership ambiguous.
    $machineName = [System.Environment]::MachineName
    $userName = [System.Environment]::UserName
    $ownerToken = [guid]::NewGuid().ToString()
    $lock = @{
        lockType        = "backup"
        lockedAt        = (Get-Date).ToString("o")
        ownerToken      = $ownerToken
        processId       = $PID
        machine         = $machineName
        maschine        = $machineName
        user            = $userName
        toolVersion     = $script:RenderKitModuleVersion
    }

    $lockJson = $lock | ConvertTo-Json -Depth 5 -ErrorAction Stop
    $encoding = New-Object System.Text.UTF8Encoding($false)
    $lockBytes = $encoding.GetBytes($lockJson)

    if ($state.IsStale -and (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
        Write-RenderKitLog `
            -Level Warning `
            -Message "Taking over stale backup lock at '$lockPath'."

        $staleStream = $null
        $reader = $null
        try {
            # Do not implement stale takeover as Remove-Item followed by
            # CreateNew. Two contenders can both observe the same stale file;
            # the slower one could otherwise delete the faster contender's
            # freshly created lock. Instead, exclusively open the observed file,
            # verify that its identity is unchanged, and replace its content
            # through the same handle.
            $staleStream = [System.IO.File]::Open(
                $lockPath,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None
            )
            $reader = [System.IO.StreamReader]::new(
                $staleStream,
                [System.Text.Encoding]::UTF8,
                $true,
                1024,
                $true
            )
            $currentText = $reader.ReadToEnd()
            $reader.Dispose()
            $reader = $null

            $currentLock = $currentText | ConvertFrom-Json -ErrorAction Stop
            $expectedToken = if ($state.Lock.PSObject.Properties.Name -contains 'ownerToken') {
                [string]$state.Lock.ownerToken
            }
            else {
                $null
            }
            $currentToken = if ($currentLock.PSObject.Properties.Name -contains 'ownerToken') {
                [string]$currentLock.ownerToken
            }
            else {
                $null
            }

            if (-not [string]::IsNullOrWhiteSpace($expectedToken)) {
                $sameObservedLock = $expectedToken.Equals(
                    $currentToken,
                    [System.StringComparison]::Ordinal
                )
            }
            else {
                # Legacy locks predate owner tokens. Compare their stable
                # identity fields so a newly replaced lock cannot be mistaken
                # for the stale snapshot that was inspected above.
                $expectedMachine = if ($state.Lock.PSObject.Properties.Name -contains 'machine') {
                    [string]$state.Lock.machine
                }
                elseif ($state.Lock.PSObject.Properties.Name -contains 'maschine') {
                    [string]$state.Lock.maschine
                }
                else {
                    $null
                }
                $currentMachine = if ($currentLock.PSObject.Properties.Name -contains 'machine') {
                    [string]$currentLock.machine
                }
                elseif ($currentLock.PSObject.Properties.Name -contains 'maschine') {
                    [string]$currentLock.maschine
                }
                else {
                    $null
                }
                $sameObservedLock = (
                    [string]$state.Lock.processId -eq [string]$currentLock.processId -and
                    [string]$state.Lock.lockedAt -eq [string]$currentLock.lockedAt -and
                    [string]$expectedMachine -eq [string]$currentMachine
                )
            }

            if (-not $sameObservedLock) {
                throw "Backup lock changed while stale takeover was in progress for '$ProjectRoot'."
            }

            $staleStream.SetLength(0)
            $staleStream.Position = 0
            $staleStream.Write($lockBytes, 0, $lockBytes.Length)
            $staleStream.Flush()
        }
        catch [System.IO.IOException] {
            throw "Backup lock changed or was acquired concurrently for '$ProjectRoot'."
        }
        finally {
            if ($reader) {
                $reader.Dispose()
            }
            if ($staleStream) {
                $staleStream.Dispose()
            }
        }

        return [PSCustomObject]@{
            ProjectRoot = $ProjectRoot
            LockPath    = $lockPath
            OwnerToken  = $ownerToken
            LockedAt    = $lock.lockedAt
        }
    }

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
