function Resolve-RenderKitProjectSiblingTarget {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param(
        [Parameter(Mandatory)][string]$ParentPath,
        [Parameter(Mandatory)][string]$ProjectName
    )

    $normalizedName = $ProjectName.Trim()
    if ([string]::IsNullOrWhiteSpace($normalizedName)) {
        throw 'Project target name must not be empty.'
    }
    if (
        $normalizedName -eq '.' -or
        $normalizedName -eq '..' -or
        $normalizedName.Contains('/') -or
        $normalizedName.Contains('\') -or
        [System.IO.Path]::IsPathRooted($normalizedName)
    ) {
        throw "Project target name '$ProjectName' must be a single path component."
    }

    $invalidFileNameChars = [System.IO.Path]::GetInvalidFileNameChars()
    if ($normalizedName.IndexOfAny($invalidFileNameChars) -ge 0) {
        throw "Project target name '$ProjectName' contains invalid filename characters."
    }

    if ($env:OS -eq 'Windows_NT') {
        if ($normalizedName.EndsWith(' ') -or $normalizedName.EndsWith('.')) {
            throw "Project target name '$ProjectName' must not end with a space or period on Windows."
        }
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($normalizedName)
        if ($baseName -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') {
            throw "Project target name '$ProjectName' is a reserved Windows device name."
        }
    }

    $parentFull = [System.IO.Path]::GetFullPath($ParentPath).TrimEnd(
        [char[]]@(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
    )
    $targetFull = [System.IO.Path]::GetFullPath(
        (Join-Path -Path $parentFull -ChildPath $normalizedName)
    )
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $prefix = $parentFull + $separator
    $comparison = if ($env:OS -eq 'Windows_NT') {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }

    if (-not $targetFull.StartsWith($prefix, $comparison)) {
        throw "Project target '$targetFull' resolves outside parent '$parentFull'."
    }

    return [PSCustomObject]@{
        Name = $normalizedName
        Path = $targetFull
        ParentPath = $parentFull
    }
}

function Resolve-RenderKitProjectCreationTarget {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param(
        [Parameter(Mandatory)][string]$ProjectName,
        [AllowNull()][string]$Path
    )

    $parentPath = $Path
    if ([string]::IsNullOrWhiteSpace($parentPath)) {
        $config = Get-RenderKitConfig
        $parentPath = [string]$config.DefaultProjectPath
        if ([string]::IsNullOrWhiteSpace($parentPath)) {
            throw "No default project path configured. Use 'Set-ProjectRoot' first."
        }
    }

    if (-not (Test-Path -LiteralPath $parentPath -PathType Container)) {
        throw "Target project parent does not exist or is not a directory: $parentPath"
    }

    return Resolve-RenderKitProjectSiblingTarget `
        -ParentPath $parentPath `
        -ProjectName $ProjectName
}
