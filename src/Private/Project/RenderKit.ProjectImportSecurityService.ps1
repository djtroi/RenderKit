function Resolve-RenderKitProjectImportTargetRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DestinationRoot,
        [Parameter(Mandatory)][string]$ProjectName
    )

    $normalizedName = $ProjectName.Trim()
    if ([string]::IsNullOrWhiteSpace($normalizedName)) {
        throw 'Project name must not be empty.'
    }
    if (
        $normalizedName -eq '.' -or
        $normalizedName -eq '..' -or
        $normalizedName.Contains('/') -or
        $normalizedName.Contains('\') -or
        [System.IO.Path]::IsPathRooted($normalizedName)
    ) {
        throw "Project name '$ProjectName' must be a single path component."
    }

    $invalidFileNameChars = [System.IO.Path]::GetInvalidFileNameChars()
    if ($normalizedName.IndexOfAny($invalidFileNameChars) -ge 0) {
        throw "Project name '$ProjectName' contains invalid filename characters."
    }

    $destinationFullPath = [System.IO.Path]::GetFullPath($DestinationRoot)
    $targetFullPath = [System.IO.Path]::GetFullPath(
        (Join-Path -Path $destinationFullPath -ChildPath $normalizedName)
    )
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $destinationPrefix = $destinationFullPath.TrimEnd(
        [char[]]@(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
    ) + $separator
    $isWindowsPlatform = $env:OS -eq 'Windows_NT'
    $comparison = if ($isWindowsPlatform) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }

    if (-not $targetFullPath.StartsWith($destinationPrefix, $comparison)) {
        throw "Project target '$targetFullPath' resolves outside destination root '$destinationFullPath'."
    }

    return $targetFullPath
}
