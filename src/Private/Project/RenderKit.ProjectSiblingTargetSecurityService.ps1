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

function Test-RenderKitProjectControlItemLink {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][object]$Item
    )

    if (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        return $true
    }
    if ($Item.PSObject.Properties.Name -contains 'LinkType' -and
        -not [string]::IsNullOrWhiteSpace([string]$Item.LinkType)) {
        return $true
    }
    return $false
}

function Assert-RenderKitProjectControlPathSafe {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot
    )

    $rootPath = [System.IO.Path]::GetFullPath($ProjectRoot)
    $rootItem = Get-Item -LiteralPath $rootPath -Force -ErrorAction Stop
    if (-not $rootItem.PSIsContainer) {
        throw "Project root '$rootPath' is not a directory."
    }
    if (Test-RenderKitProjectControlItemLink -Item $rootItem) {
        throw "Project root '$rootPath' must not be a symbolic link, junction, or reparse point."
    }

    $controlPath = Join-Path -Path $rootPath -ChildPath '.renderkit'
    $controlItem = Get-Item -LiteralPath $controlPath -Force -ErrorAction Stop
    if (-not $controlItem.PSIsContainer) {
        throw "Project control path '$controlPath' is not a directory."
    }
    if (Test-RenderKitProjectControlItemLink -Item $controlItem) {
        throw "Project control path '$controlPath' must not be a symbolic link, junction, or reparse point."
    }

    $metadataPath = Join-Path -Path $controlPath -ChildPath 'project.json'
    $metadataItem = Get-Item -LiteralPath $metadataPath -Force -ErrorAction Stop
    if ($metadataItem.PSIsContainer) {
        throw "Project metadata path '$metadataPath' is not a file."
    }
    if (Test-RenderKitProjectControlItemLink -Item $metadataItem) {
        throw "Project metadata path '$metadataPath' must not be a symbolic link, hard link, or reparse point."
    }

    return [PSCustomObject]@{
        RootPath = $rootPath
        ControlPath = $controlPath
        MetadataPath = $metadataPath
    }
}
