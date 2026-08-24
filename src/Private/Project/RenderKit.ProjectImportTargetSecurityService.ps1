function Assert-RenderKitProjectImportTargetPathSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TargetRoot,
        [Parameter(Mandatory)][string]$Path
    )

    $rootFull = [System.IO.Path]::GetFullPath($TargetRoot).TrimEnd(
        [char[]]@(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
    )
    $pathFull = [System.IO.Path]::GetFullPath($Path)
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $rootPrefix = $rootFull + $separator
    $comparison = if ($env:OS -eq 'Windows_NT') {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }

    if (-not $pathFull.Equals($rootFull, $comparison) -and
        -not $pathFull.StartsWith($rootPrefix, $comparison)) {
        throw "Import target '$pathFull' resolves outside project root '$rootFull'."
    }

    $pathsToCheck = New-Object System.Collections.Generic.List[string]
    $pathsToCheck.Add($rootFull)

    if (-not $pathFull.Equals($rootFull, $comparison)) {
        $relative = $pathFull.Substring($rootPrefix.Length)
        $current = $rootFull
        foreach ($component in @($relative -split '[\\/]+')) {
            if ([string]::IsNullOrWhiteSpace($component)) { continue }
            $current = Join-Path -Path $current -ChildPath $component
            $pathsToCheck.Add($current)
        }
    }

    foreach ($candidate in $pathsToCheck) {
        if (-not (Test-Path -LiteralPath $candidate)) { continue }
        $item = Get-Item -LiteralPath $candidate -Force -ErrorAction Stop
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Import target path '$candidate' is a symbolic link or reparse point."
        }
    }

    return $pathFull
}

function New-RenderKitProjectImportDirectorySafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TargetRoot,
        [Parameter(Mandatory)][string]$Path
    )

    $safePath = Assert-RenderKitProjectImportTargetPathSafe `
        -TargetRoot $TargetRoot `
        -Path $Path

    if (-not (Test-Path -LiteralPath $safePath -PathType Container)) {
        New-Item -ItemType Directory -Path $safePath -Force | Out-Null
    }

    Assert-RenderKitProjectImportTargetPathSafe `
        -TargetRoot $TargetRoot `
        -Path $safePath |
        Out-Null

    return $safePath
}
