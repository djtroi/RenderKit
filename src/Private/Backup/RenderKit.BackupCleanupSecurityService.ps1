function Test-RenderKitBackupCleanupReparsePoint {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [System.IO.FileSystemInfo]$Item
    )

    if ($null -eq $Item) {
        return $false
    }
    return [bool](
        $Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint
    )
}

function Get-RenderKitBackupCleanupCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath
    )

    $rootPath = [System.IO.Path]::GetFullPath($ProjectPath)
    $root = Get-Item -LiteralPath $rootPath -Force -ErrorAction Stop
    if (-not ($root -is [System.IO.DirectoryInfo])) {
        throw "Backup cleanup root '$rootPath' is not a directory."
    }
    if (Test-RenderKitBackupCleanupReparsePoint -Item $root) {
        throw "Backup cleanup root '$rootPath' must not be a reparse point."
    }

    $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    $directories = New-Object System.Collections.Generic.List[System.IO.DirectoryInfo]
    $pending = New-Object System.Collections.Generic.Stack[System.IO.DirectoryInfo]
    $pending.Push($root)

    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        try {
            $children = @($directory.GetFileSystemInfos())
        }
        catch {
            Write-Verbose "Backup cleanup could not enumerate '$($directory.FullName)': $($_.Exception.Message)"
            continue
        }

        foreach ($child in $children) {
            if (Test-RenderKitBackupCleanupReparsePoint -Item $child) {
                continue
            }
            if ($child -is [System.IO.DirectoryInfo]) {
                $directories.Add($child)
                $pending.Push($child)
            }
            elseif ($child -is [System.IO.FileInfo]) {
                $files.Add($child)
            }
        }
    }

    return [PSCustomObject]@{
        RootPath = $rootPath
        Files = @($files.ToArray())
        Directories = @($directories.ToArray())
    }
}

function Test-RenderKitBackupCleanupTarget {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$TargetPath
    )

    $root = [System.IO.Path]::GetFullPath($ProjectPath).TrimEnd(
        [char[]]@(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
    )
    $target = [System.IO.Path]::GetFullPath($TargetPath)
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $prefix = $root + $separator
    $comparison = if ($env:OS -eq 'Windows_NT') {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }

    if (-not $target.StartsWith($prefix, $comparison)) {
        return $false
    }

    $relative = $target.Substring($prefix.Length)
    $current = $root
    foreach ($segment in @($relative -split '[\\/]+')) {
        if ([string]::IsNullOrWhiteSpace($segment)) {
            continue
        }
        $current = Join-Path -Path $current -ChildPath $segment
        $item = Get-Item `
            -LiteralPath $current `
            -Force `
            -ErrorAction SilentlyContinue
        if ($item -and (Test-RenderKitBackupCleanupReparsePoint -Item $item)) {
            return $false
        }
    }

    return $true
}

function Remove-RenderKitBackupCleanupDirectoryTree {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Internal helper called behind the public backup ShouldProcess/DryRun boundary.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$DirectoryPath
    )

    if (-not (Test-RenderKitBackupCleanupTarget `
            -ProjectPath $ProjectPath `
            -TargetPath $DirectoryPath)) {
        throw "Backup cleanup target '$DirectoryPath' is outside the safe project tree or crosses a reparse point."
    }

    $directory = Get-Item `
        -LiteralPath $DirectoryPath `
        -Force `
        -ErrorAction Stop
    if (-not ($directory -is [System.IO.DirectoryInfo]) -or
        (Test-RenderKitBackupCleanupReparsePoint -Item $directory)) {
        throw "Backup cleanup directory '$DirectoryPath' is not a safe directory target."
    }

    foreach ($child in @($directory.GetFileSystemInfos())) {
        if (Test-RenderKitBackupCleanupReparsePoint -Item $child) {
            # Never follow or remove an indirection during destructive cleanup.
            # Leaving the parent non-empty is safer than touching external data.
            continue
        }
        if ($child -is [System.IO.DirectoryInfo]) {
            Remove-RenderKitBackupCleanupDirectoryTree `
                -ProjectPath $ProjectPath `
                -DirectoryPath $child.FullName
            continue
        }
        if (-not (Test-RenderKitBackupCleanupTarget `
                -ProjectPath $ProjectPath `
                -TargetPath $child.FullName)) {
            throw "Backup cleanup file '$($child.FullName)' is outside the safe project tree."
        }
        [System.IO.File]::Delete($child.FullName)
    }

    [System.IO.Directory]::Delete($directory.FullName, $false)
}
