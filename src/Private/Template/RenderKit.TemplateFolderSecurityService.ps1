function Assert-RenderKitTemplateFolderName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -ne $Name.Trim()) {
        throw 'Template folder names must not be empty or have leading/trailing whitespace.'
    }
    if ($Name.Length -gt 255) {
        throw "Template folder name '$Name' exceeds 255 characters."
    }
    if (
        $Name -eq '.' -or
        $Name -eq '..' -or
        $Name.Contains('/') -or
        $Name.Contains('\') -or
        [System.IO.Path]::IsPathRooted($Name)
    ) {
        throw "Template folder name '$Name' must be a single path component."
    }

    # Templates are portable resources. Reject the Windows-invalid character
    # set on every platform so a template accepted on Unix cannot become an
    # unsafe or ambiguous path when the same resource is used on Windows.
    if ($Name -match '[<>:"/\\|?*\x00-\x1F]') {
        throw "Template folder name '$Name' contains non-portable filename characters."
    }
    if ($Name.EndsWith(' ') -or $Name.EndsWith('.')) {
        throw "Template folder name '$Name' must not end with a space or period."
    }
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Name)
    if ($baseName -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') {
        throw "Template folder name '$Name' is a reserved Windows device name."
    }

    return $Name
}

function Test-RenderKitTemplateFolderNodeInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Folder,
        [Parameter(Mandatory)][int]$Depth,
        [Parameter(Mandatory)][ref]$NodeCount,
        [Parameter(Mandatory)][int]$MaximumDepth,
        [Parameter(Mandatory)][int]$MaximumNodes
    )

    if ($Depth -gt $MaximumDepth) {
        throw "Template folder tree exceeds the maximum depth of $MaximumDepth."
    }
    if (-not ($Folder.PSObject.Properties.Name -contains 'Name')) {
        throw "Template folder node at depth $Depth is missing the 'Name' property."
    }
    $folderName = Assert-RenderKitTemplateFolderName -Name ([string]$Folder.Name)

    $NodeCount.Value++
    if ($NodeCount.Value -gt $MaximumNodes) {
        throw "Template folder tree exceeds the maximum node count of $MaximumNodes."
    }

    $children = if ($Folder.PSObject.Properties.Name -contains 'SubFolders') {
        @($Folder.SubFolders)
    }
    elseif ($Folder.PSObject.Properties.Name -contains 'Children') {
        @($Folder.Children)
    }
    else {
        throw "Template folder '$folderName' is missing a SubFolders/Children collection."
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($child in $children) {
        if ($null -eq $child -or -not ($child.PSObject.Properties.Name -contains 'Name')) {
            throw "Template folder '$folderName' contains a child without a Name property."
        }
        $childName = Assert-RenderKitTemplateFolderName -Name ([string]$child.Name)
        if (-not $seen.Add($childName)) {
            throw "Template folder '$folderName' contains duplicate or case-colliding child '$childName'."
        }
        Test-RenderKitTemplateFolderNodeInternal `
            -Folder $child `
            -Depth ($Depth + 1) `
            -NodeCount $NodeCount `
            -MaximumDepth $MaximumDepth `
            -MaximumNodes $MaximumNodes
    }
}

function Test-RenderKitTemplateFolderTree {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Folder = @(),
        [ValidateRange(1, 256)][int]$MaximumDepth = 64,
        [ValidateRange(1, 100000)][int]$MaximumNodes = 10000
    )

    $nodeCount = 0
    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($root in @($Folder)) {
        if ($null -eq $root -or -not ($root.PSObject.Properties.Name -contains 'Name')) {
            throw "Template root folder is missing the 'Name' property."
        }
        $rootName = Assert-RenderKitTemplateFolderName -Name ([string]$root.Name)
        if (-not $seen.Add($rootName)) {
            throw "Template contains duplicate or case-colliding root folder '$rootName'."
        }
        Test-RenderKitTemplateFolderNodeInternal `
            -Folder $root `
            -Depth 1 `
            -NodeCount ([ref]$nodeCount) `
            -MaximumDepth $MaximumDepth `
            -MaximumNodes $MaximumNodes
    }
}
