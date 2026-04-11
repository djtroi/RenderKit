function New-RenderKitImportCriterion {
    [CmdletBinding()]
    param(
        [string[]]$FolderFilter,
        [Nullable[datetime]]$FromDate,
        [Nullable[datetime]]$ToDate,
        [string[]]$Wildcard
    )

    $normalizedFolderFilter = @(
        $FolderFilter |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { ([string]$_).Trim() } |
            Sort-Object -Unique
    )

    $normalizedWildcard = @(
        $Wildcard |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { ([string]$_).Trim() } |
            Sort-Object -Unique
    )

    return [PSCustomObject]@{
        FolderFilter = $normalizedFolderFilter
        FromDate     = $FromDate
        ToDate       = $ToDate
        Wildcard     = $normalizedWildcard
    }
}

function Merge-RenderKitImportCriterion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$BaseCriteria,
        [Parameter(Mandatory)]
        [object]$AdditionalCriteria
    )

    $folderFilter = @($BaseCriteria.FolderFilter + $AdditionalCriteria.FolderFilter | Sort-Object -Unique)
    $wildcard = @($BaseCriteria.Wildcard + $AdditionalCriteria.Wildcard | Sort-Object -Unique)

    $fromDate = $null
    if ($null -ne $BaseCriteria.FromDate -and $null -ne $AdditionalCriteria.FromDate) {
        $fromDate = if ($BaseCriteria.FromDate -gt $AdditionalCriteria.FromDate) { $BaseCriteria.FromDate } else { $AdditionalCriteria.FromDate }
    }
    elseif ($null -ne $BaseCriteria.FromDate) {
        $fromDate = $BaseCriteria.FromDate
    }
    elseif ($null -ne $AdditionalCriteria.FromDate) {
        $fromDate = $AdditionalCriteria.FromDate
    }

    $toDate = $null
    if ($null -ne $BaseCriteria.ToDate -and $null -ne $AdditionalCriteria.ToDate) {
        $toDate = if ($BaseCriteria.ToDate -lt $AdditionalCriteria.ToDate) { $BaseCriteria.ToDate } else { $AdditionalCriteria.ToDate }
    }
    elseif ($null -ne $BaseCriteria.ToDate) {
        $toDate = $BaseCriteria.ToDate
    }
    elseif ($null -ne $AdditionalCriteria.ToDate) {
        $toDate = $AdditionalCriteria.ToDate
    }

    return New-RenderKitImportCriterion `
        -FolderFilter $folderFilter `
        -FromDate $fromDate `
        -ToDate $toDate `
        -Wildcard $wildcard
}

function ConvertTo-RenderKitImportDrivePath {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [string]$DriveLetter
    )

    $normalizedDriveLetter = Resolve-RenderKitDriveLetter -DriveLetter $DriveLetter
    if ([string]::IsNullOrWhiteSpace($normalizedDriveLetter)) {
        Write-RenderKitLog -Level Error -Message "Drive '$DriveLetter' is invalid."
        throw "Drive '$DriveLetter' is invalid."
    }

    $path = "$normalizedDriveLetter\"
    if (-not (Test-Path -Path $path -PathType Container)) {
        Write-RenderKitLog -Level Error -Message "Drive '$path' is not available."
        throw "Drive '$path' is not available."
    }

    return $path
}

function Resolve-RenderKitImportSourcePath {
    [CmdletBinding()]
    param(
        [string]$SourcePath,
        [switch]$SelectSource,
        [switch]$IncludeFixed,
        [switch]$IncludeUnsupportedFileSystem
    )

    if (-not [string]::IsNullOrWhiteSpace($SourcePath)) {
        try {
            $resolvedPath = (Resolve-Path -Path $SourcePath -ErrorAction Stop).ProviderPath
        }
        catch {
            Write-RenderKitLog -Level Error -Message "Source path '$SourcePath' was not found."
            throw "Source path '$SourcePath' was not found."
        }

        if (-not (Test-Path -Path $resolvedPath -PathType Container)) {
            Write-RenderKitLog -Level Error -Message "Source path '$resolvedPath' is not a directory."
            throw "Source path '$resolvedPath' is not a directory."
        }

        return $resolvedPath
    }

    if ($SelectSource) {
        $selectedCandidate = Select-RenderKitDriveCandidate `
            -IncludeFixed:$IncludeFixed `
            -IncludeUnsupportedFileSystem:$IncludeUnsupportedFileSystem

        if (-not $selectedCandidate) {
            return $null
        }

        return ConvertTo-RenderKitImportDrivePath -DriveLetter $selectedCandidate.DriveLetter
    }

    $autoCandidate = Get-RenderKitDriveCandidate `
        -IncludeFixed:$IncludeFixed `
        -IncludeUnsupportedFileSystem:$IncludeUnsupportedFileSystem |
        Select-Object -First 1

    if (-not $autoCandidate) {
        return $null
    }

    Write-RenderKitLog -Level Info -Message "Auto-selected source drive '$($autoCandidate.DriveLetter)'."
    return ConvertTo-RenderKitImportDrivePath -DriveLetter $autoCandidate.DriveLetter
}

function Get-RenderKitImportFileCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath
    )

    $rootDirectory = [System.IO.DirectoryInfo]::new($SourcePath)
    if (-not $rootDirectory.Exists) {
        Write-RenderKitLog -Level Error -Message "Source path '$SourcePath' does not exist."
        throw "Source path '$SourcePath' does not exist."
    }

    $files = New-Object System.Collections.Generic.List[object]
    $pendingDirectories = New-Object "System.Collections.Generic.Stack[System.IO.DirectoryInfo]"
    $pendingDirectories.Push($rootDirectory)

    while ($pendingDirectories.Count -gt 0) {
        $currentDirectory = $pendingDirectories.Pop()

        try {
            foreach ($subDirectory in $currentDirectory.EnumerateDirectories()) {
                $pendingDirectories.Push($subDirectory)
            }
        }
        catch {
            Write-RenderKitLog -Level Debug -Message "Skipping directory '$($currentDirectory.FullName)': $_"
        }

        try {
            foreach ($file in $currentDirectory.EnumerateFiles()) {
                $relativePath = $file.FullName.Substring($rootDirectory.FullName.Length).TrimStart('\')
                $relativePath = $relativePath -replace '/', '\'

                $relativeDirectory = [System.IO.Path]::GetDirectoryName($relativePath)
                if ([string]::IsNullOrWhiteSpace($relativeDirectory)) {
                    $relativeDirectory = "."
                }

                $files.Add([PSCustomObject]@{
                        Name              = $file.Name
                        FullName          = $file.FullName
                        RelativePath      = $relativePath
                        RelativeDirectory = $relativeDirectory
                        Extension         = $file.Extension
                        LastWriteTime     = $file.LastWriteTime
                        Length            = [int64]$file.Length
                    })
            }
        }
        catch {
            Write-RenderKitLog -Level Debug -Message "Skipping files in '$($currentDirectory.FullName)': $_"
        }
    }

    return $files.ToArray()
}

function Test-RenderKitImportFolderMatch {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory)]
        [string]$RelativeDirectory,
        [Parameter(Mandatory)]
        [string[]]$FolderFilter
    )

    $normalizedDirectory = $RelativeDirectory.Replace('/', '\').Trim('\')

    if ($normalizedDirectory -eq ".") {
        $normalizedDirectory = ""
    }

    foreach ($folder in $FolderFilter) {
        $pattern = $folder.Replace('/', '\').Trim()
        if ([string]::IsNullOrWhiteSpace($pattern)) {
            continue
        }

        $pattern = $pattern.Trim('\')
        if ($normalizedDirectory -like $pattern) {
            return $true
        }

        if ($normalizedDirectory -like "$pattern\*") {
            return $true
        }

        if ($normalizedDirectory -like "*\$pattern") {
            return $true
        }

        if ($normalizedDirectory -like "*\$pattern\*") {
            return $true
        }
    }

    return $false
}

function Get-RenderKitImportFilteredFile {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Files,
        [Parameter(Mandatory)]
        [object]$Criteria
    )

    if (-not $Files -or $Files.Count -eq 0) {
        return @()
    }

    $filtered = foreach ($file in $Files) {
        if ($Criteria.FolderFilter.Count -gt 0) {
            $folderMatch = Test-RenderKitImportFolderMatch `
                -RelativeDirectory $file.RelativeDirectory `
                -FolderFilter $Criteria.FolderFilter

            if (-not $folderMatch) {
                continue
            }
        }

        if ($null -ne $Criteria.FromDate -and $file.LastWriteTime -lt $Criteria.FromDate) {
            continue
        }

        if ($null -ne $Criteria.ToDate -and $file.LastWriteTime -gt $Criteria.ToDate) {
            continue
        }

        if ($Criteria.Wildcard.Count -gt 0) {
            $wildcardMatch = $false
            foreach ($pattern in $Criteria.Wildcard) {
                if ($file.Name -like $pattern -or $file.RelativePath -like $pattern) {
                    $wildcardMatch = $true
                    break
                }
            }

            if (-not $wildcardMatch) {
                continue
            }
        }

        $file
    }

    return @($filtered)
}

function ConvertFrom-RenderKitImportListInput {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [string]$InputText
    )

    if ([string]::IsNullOrWhiteSpace($InputText)) {
        return @()
    }

    return @(
        $InputText.Split(',') |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
}

function Read-RenderKitImportYesNo {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,
        [bool]$Default = $true
    )

    $suffix = if ($Default) { "[Y/n]" } else { "[y/N]" }

    while ($true) {
        $inputValue = Read-Host "$Prompt $suffix"
        if ([string]::IsNullOrWhiteSpace($inputValue)) {
            return $Default
        }

        switch ($inputValue.Trim().ToUpperInvariant()) {
            "Y" { return $true }
            "YES" { return $true }
            "J" { return $true }
            "JA" { return $true }
            "N" { return $false }
            "NO" { return $false }
            "NEIN" { return $false }
            default {
                Write-Warning "Please answer with Y or N."
            }
        }
    }
}

function Show-RenderKitImportWizardStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,
        [Parameter(Mandatory)]
        [hashtable]$Data
    )

    Write-Information $Title -InformationAction Continue

    $rows = @()
    foreach ($key in $Data.Keys) {
        $value = $Data[$key]
        if ($value -is [bool]) {
            $value = if ($value) { "Yes" } else { "No" }
        }
        elseif ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
            $value = "-"
        }

        $rows += [PSCustomObject]@{
            Field = $key
            Value = $value
        }
    }

    $rows | Format-Table -AutoSize | Out-Host
}

function Read-RenderKitImportSelectionReviewAction {
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    while ($true) {
        $choice = Read-Host "Selection check: [Y] Continue, [E] Edit selection, [C] Cancel import (default Y)"
        if ([string]::IsNullOrWhiteSpace($choice)) {
            return "Continue"
        }

        switch ($choice.Trim().ToUpperInvariant()) {
            "Y" { return "Continue" }
            "YES" { return "Continue" }
            "J" { return "Continue" }
            "JA" { return "Continue" }
            "E" { return "Edit" }
            "EDIT" { return "Edit" }
            "C" { return "Cancel" }
            "CANCEL" { return "Cancel" }
            "N" { return "Cancel" }
            "NO" { return "Cancel" }
            default {
                Write-Warning "Unknown option '$choice'."
            }
        }
    }
}

function Read-RenderKitImportTransferModeInteractive {
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    while ($true) {
        $choice = Read-Host "Transfer mode: [R]eal transfer, [S]imulate transfer, [N]o transfer (default R)"
        if ([string]::IsNullOrWhiteSpace($choice)) {
            return "Real"
        }

        switch ($choice.Trim().ToUpperInvariant()) {
            "R" { return "Real" }
            "REAL" { return "Real" }
            "S" { return "Simulate" }
            "SIMULATE" { return "Simulate" }
            "W" { return "Simulate" }
            "WHATIF" { return "Simulate" }
            "N" { return "None" }
            "NO" { return "None" }
            "NONE" { return "None" }
            default {
                Write-Warning "Unknown option '$choice'."
            }
        }
    }
}

function Get-RenderKitImportProjectCandidate {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [string]$BasePath
    )

    $roots = @()
    if (-not [string]::IsNullOrWhiteSpace($BasePath)) {
        $roots += $BasePath
    }
    else {
        $config = Get-RenderKitConfig
        if ($config) {
            if (
                $config -is [hashtable] -and
                $config.ContainsKey("DefaultProjectPath") -and
                -not [string]::IsNullOrWhiteSpace([string]$config.DefaultProjectPath)
            ) {
                $roots += [string]$config.DefaultProjectPath
            }
            elseif (
                $config.PSObject.Properties.Name -contains "DefaultProjectPath" -and
                -not [string]::IsNullOrWhiteSpace([string]$config.DefaultProjectPath)
            ) {
                $roots += [string]$config.DefaultProjectPath
            }
        }
    }

    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($root in @($roots | Sort-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -Path $root -PathType Container)) {
            continue
        }

        foreach ($projectDir in @(Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue)) {
            $metadataPath = Join-Path $projectDir.FullName ".renderkit\project.json"
            if (-not (Test-Path -Path $metadataPath -PathType Leaf)) {
                continue
            }

            $metadata = $null
            try {
                $metadata = Get-Content -Path $metadataPath -Raw | ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                continue
            }

            if (-not $metadata -or [string]::IsNullOrWhiteSpace([string]$metadata.tool) -or $metadata.tool -ne "RenderKit") {
                continue
            }

            $templateName = $null
            if ($metadata.PSObject.Properties.Name -contains "template" -and $metadata.template) {
                if ($metadata.template.PSObject.Properties.Name -contains "name") {
                    $templateName = [string]$metadata.template.name
                }
            }

            $createdAt = $null
            if ($metadata.PSObject.Properties.Name -contains "project" -and $metadata.project) {
                if ($metadata.project.PSObject.Properties.Name -contains "createdAt") {
                    $createdAt = [string]$metadata.project.createdAt
                }
            }

            $projectName = $projectDir.Name
            if ($metadata.PSObject.Properties.Name -contains "project" -and $metadata.project) {
                if (
                    $metadata.project.PSObject.Properties.Name -contains "name" -and
                    -not [string]::IsNullOrWhiteSpace([string]$metadata.project.name)
                ) {
                    $projectName = [string]$metadata.project.name
                }
            }

            $candidates.Add([PSCustomObject]@{
                    Name       = $projectName
                    ProjectRoot = $projectDir.FullName
                    Template   = $templateName
                    CreatedAt  = $createdAt
                })
        }
    }

    return @($candidates.ToArray() | Sort-Object Name, ProjectRoot)
}

function Show-RenderKitImportProjectTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Projects
    )

    if (-not $Projects -or $Projects.Count -eq 0) {
        return
    }

    $rows = @()
    for ($i = 0; $i -lt $Projects.Count; $i++) {
        $rows += [PSCustomObject]@{
            Index    = $i
            Project  = $Projects[$i].Name
            Template = $Projects[$i].Template
            Path     = $Projects[$i].ProjectRoot
        }
    }

    $rows | Format-Table -AutoSize | Out-Host
}

function Read-RenderKitImportProjectRootInteractive {
    [CmdletBinding()]
    param(
        [string]$ProjectRoot
    )

    if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
        return Resolve-RenderKitImportProjectRoot -ProjectRoot $ProjectRoot
    }

    $projects = @(Get-RenderKitImportProjectCandidate)
    if ($projects.Count -gt 0) {
        Show-RenderKitImportProjectTable -Projects $projects
    }

    while ($true) {
        if ($projects.Count -gt 0) {
            $inputValue = Read-Host "Destination project: index, absolute path, or Enter for index 0 (Q to cancel)"
        }
        else {
            $inputValue = Read-Host "Destination project root path (Q to cancel)"
        }

        if ([string]::IsNullOrWhiteSpace($inputValue)) {
            if ($projects.Count -gt 0) {
                return $projects[0].ProjectRoot
            }
            continue
        }

        if ($inputValue.Trim().ToUpperInvariant() -eq "Q") {
            return $null
        }

        $index = -1
        if ($projects.Count -gt 0 -and [int]::TryParse($inputValue, [ref]$index)) {
            if ($index -ge 0 -and $index -lt $projects.Count) {
                return $projects[$index].ProjectRoot
            }

            Write-Warning "Index '$index' is out of range."
            continue
        }

        try {
            return Resolve-RenderKitImportProjectRoot -ProjectRoot $inputValue
        }
        catch {
            Write-Warning $_.Exception.Message
        }
    }
}

function Get-RenderKitImportChildDirectory {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        $directory = [System.IO.DirectoryInfo]::new($Path)
        if (-not $directory.Exists) {
            return @()
        }

        return @(
            $directory.EnumerateDirectories() |
                Sort-Object -Property Name
        )
    }
    catch {
        Write-RenderKitLog -Level Debug -Message "Could not enumerate subdirectories for '$Path': $($_.Exception.Message)"
        return @()
    }
}

function Get-RenderKitImportDirectoryTreeEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,
        [ValidateRange(1, 10)]
        [int]$MaxDepth = 2,
        [ValidateRange(10, 1000)]
        [int]$MaxEntries = 250
    )

    $entries = New-Object System.Collections.Generic.List[object]
    $pending = New-Object "System.Collections.Generic.Stack[object]"
    $rootChildren = @(Get-RenderKitImportChildDirectory -Path $RootPath)

    for ($i = $rootChildren.Count - 1; $i -ge 0; $i--) {
        $child = $rootChildren[$i]
        $pending.Push([PSCustomObject]@{
                FullPath     = $child.FullName
                RelativePath = $child.Name
                Name         = $child.Name
                Depth        = 0
            })
    }

    $isTruncated = $false
    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        $entries.Add([PSCustomObject]@{
                Index        = $entries.Count
                FullPath     = [string]$current.FullPath
                RelativePath = [string]$current.RelativePath
                Name         = [string]$current.Name
                Depth        = [int]$current.Depth
            })

        if ($entries.Count -ge $MaxEntries) {
            $isTruncated = $true
            break
        }

        if ($current.Depth -ge ($MaxDepth - 1)) {
            continue
        }

        $children = @(Get-RenderKitImportChildDirectory -Path $current.FullPath)
        for ($i = $children.Count - 1; $i -ge 0; $i--) {
            $child = $children[$i]
            $childRelativePath = [System.IO.Path]::Combine(
                [string]$current.RelativePath,
                $child.Name
            ) -replace '/', '\'

            $pending.Push([PSCustomObject]@{
                    FullPath     = $child.FullName
                    RelativePath = $childRelativePath
                    Name         = $child.Name
                    Depth        = [int]$current.Depth + 1
                })
        }
    }

    return [PSCustomObject]@{
        Entries     = $entries.ToArray()
        IsTruncated = $isTruncated
    }
}

function Show-RenderKitImportDirectoryTreeEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Entries,
        [bool]$IsTruncated = $false,
        [int]$MaxDepth = 2,
        [int]$MaxEntries = 250
    )

    Write-Information "Folder tree under '$RootPath' (depth $MaxDepth):" -InformationAction Continue
    if ($Entries.Count -eq 0) {
        Write-Information "No subfolders found under '$RootPath'." -InformationAction Continue
        return
    }

    $lines = foreach ($entry in $Entries) {
        $indent = "  " * [int]$entry.Depth
        "[{0}] {1}{2}" -f $entry.Index, $indent, $entry.Name
    }

    $lines | Out-Host

    if ($IsTruncated) {
        Write-Warning "Tree output was limited to $MaxEntries entries. Select a folder and continue browsing for more detail."
    }
}

function Read-RenderKitImportSubfolderSelectionMode {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [string]$SelectedPath
    )

    while ($true) {
        $choice = Read-Host "For '$SelectedPath': [S]elect deeper subfolder, use [A]ll, or [I]ndex list from direct subfolders (default A)"
        if ([string]::IsNullOrWhiteSpace($choice)) {
            return "All"
        }

        switch ($choice.Trim().ToUpperInvariant()) {
            "S" { return "Browse" }
            "SELECT" { return "Browse" }
            "A" { return "All" }
            "ALL" { return "All" }
            "I" { return "IndexList" }
            "INDEX" { return "IndexList" }
            default {
                Write-Warning "Unknown option '$choice'."
            }
        }
    }
}

function Read-RenderKitImportSubfolderIndexList {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory)]
        [string]$ParentPath
    )

    $children = @(Get-RenderKitImportChildDirectory -Path $ParentPath)
    if ($children.Count -eq 0) {
        Write-Warning "Folder '$ParentPath' has no direct subfolders."
        return $null
    }

    Write-Information "Direct subfolders in '$ParentPath':" -InformationAction Continue
    $lines = for ($i = 0; $i -lt $children.Count; $i++) {
        "[{0}] {1}" -f $i, $children[$i].Name
    }
    $lines | Out-Host

    while ($true) {
        $indexText = Read-Host "Subfolder index list (example: 0,2,4-6; Enter to cancel)"
        if ([string]::IsNullOrWhiteSpace($indexText)) {
            return $null
        }

        try {
            $indexes = ConvertTo-RenderKitImportIndexSelection `
                -InputText $indexText `
                -MaxIndex ($children.Count - 1)

            $selectedSubfolders = @(
                $indexes |
                    ForEach-Object { [System.Management.Automation.WildcardPattern]::Escape($children[$_].Name) } |
                    Sort-Object -Unique
            )

            if ($selectedSubfolders.Count -eq 0) {
                Write-Warning "No subfolders selected."
                continue
            }

            return $selectedSubfolders
        }
        catch {
            Write-Warning $_.Exception.Message
        }
    }
}

function Read-RenderKitImportSourcePathInteractive {
    [CmdletBinding()]
    param(
        [switch]$IncludeFixed,
        [switch]$IncludeUnsupportedFileSystem
    )

    $effectiveIncludeFixed = if ($PSBoundParameters.ContainsKey("IncludeFixed")) {
        [bool]$IncludeFixed
    }
    else {
        Read-RenderKitImportYesNo -Prompt "Include fixed drives in source search?" -Default $true
    }

    $effectiveIncludeUnsupported = if ($PSBoundParameters.ContainsKey("IncludeUnsupportedFileSystem")) {
        [bool]$IncludeUnsupportedFileSystem
    }
    else {
        Read-RenderKitImportYesNo -Prompt "Include unsupported file systems?" -Default $false
    }

    $selectedDrive = Select-RenderKitDriveCandidate `
        -IncludeFixed:$effectiveIncludeFixed `
        -IncludeUnsupportedFileSystem:$effectiveIncludeUnsupported

    if ($selectedDrive) {
        $driveRoot = ConvertTo-RenderKitImportDrivePath -DriveLetter $selectedDrive.DriveLetter
        $browseRoot = $driveRoot
        $treeMaxDepth = 2
        $treeMaxEntries = 250

        while ($true) {
            $tree = Get-RenderKitImportDirectoryTreeEntry `
                -RootPath $browseRoot `
                -MaxDepth $treeMaxDepth `
                -MaxEntries $treeMaxEntries

            Show-RenderKitImportDirectoryTreeEntry `
                -RootPath $browseRoot `
                -Entries $tree.Entries `
                -IsTruncated:[bool]$tree.IsTruncated `
                -MaxDepth $treeMaxDepth `
                -MaxEntries $treeMaxEntries

            $isAtDriveRoot = [string]::Equals(
                [string]$browseRoot.TrimEnd('\'),
                [string]$driveRoot.TrimEnd('\'),
                [System.StringComparison]::OrdinalIgnoreCase
            )

            $subPathPrompt = if ($isAtDriveRoot) {
                "Source subfolder on '$($selectedDrive.DriveLetter)' by index/path (Enter = drive root, Q = manual path)"
            }
            else {
                "Source subfolder in '$browseRoot' by index/path (Enter = use this folder, U = up, Q = manual path)"
            }

            $subPath = Read-Host $subPathPrompt
            if ([string]::IsNullOrWhiteSpace($subPath)) {
                return [PSCustomObject]@{
                    SourcePath                   = $browseRoot
                    FolderFilter                 = @()
                    IncludeFixed                 = $effectiveIncludeFixed
                    IncludeUnsupportedFileSystem = $effectiveIncludeUnsupported
                    SelectedDrive                = $selectedDrive
                }
            }

            $normalizedInput = $subPath.Trim()
            if ($normalizedInput.ToUpperInvariant() -eq "Q") {
                break
            }

            if ($normalizedInput.ToUpperInvariant() -eq "U") {
                if ($isAtDriveRoot) {
                    Write-Warning "Already at drive root '$driveRoot'."
                    continue
                }

                $parentPath = Split-Path -Path $browseRoot -Parent
                if ([string]::IsNullOrWhiteSpace($parentPath)) {
                    $browseRoot = $driveRoot
                }
                else {
                    $browseRoot = $parentPath
                }

                continue
            }

            $selectedTreeEntry = $null
            $selectedIndex = -1
            if ([int]::TryParse($normalizedInput, [ref]$selectedIndex)) {
                if ($selectedIndex -lt 0 -or $selectedIndex -ge $tree.Entries.Count) {
                    Write-Warning "Index '$selectedIndex' is out of range. Allowed: 0-$($tree.Entries.Count - 1)."
                    continue
                }

                $selectedTreeEntry = $tree.Entries[$selectedIndex]
                $selectedPath = [string]$selectedTreeEntry.FullPath
                $continueBrowse = $false

                while ($true) {
                    $subfolderMode = Read-RenderKitImportSubfolderSelectionMode -SelectedPath $selectedPath
                    switch ($subfolderMode) {
                        "Browse" {
                            $browseRoot = $selectedPath
                            $continueBrowse = $true
                            break
                        }
                        "All" {
                            return [PSCustomObject]@{
                                SourcePath                   = $selectedPath
                                FolderFilter                 = @()
                                IncludeFixed                 = $effectiveIncludeFixed
                                IncludeUnsupportedFileSystem = $effectiveIncludeUnsupported
                                SelectedDrive                = $selectedDrive
                            }
                        }
                        "IndexList" {
                            $selectedFolderFilter = Read-RenderKitImportSubfolderIndexList -ParentPath $selectedPath
                            if ($null -eq $selectedFolderFilter -or $selectedFolderFilter.Count -eq 0) {
                                Write-Warning "No subfolder index selection entered."
                                continue
                            }

                            return [PSCustomObject]@{
                                SourcePath                   = $selectedPath
                                FolderFilter                 = @($selectedFolderFilter)
                                IncludeFixed                 = $effectiveIncludeFixed
                                IncludeUnsupportedFileSystem = $effectiveIncludeUnsupported
                                SelectedDrive                = $selectedDrive
                            }
                        }
                    }

                    if ($continueBrowse) {
                        break
                    }
                }

                if ($continueBrowse) {
                    continue
                }
            }

            $candidatePath = if ([IO.Path]::IsPathRooted($subPath)) {
                $subPath
            }
            else {
                Join-Path $browseRoot $subPath
            }

            try {
                $resolvedPath = (Resolve-Path -Path $candidatePath -ErrorAction Stop).ProviderPath
            }
            catch {
                Write-Warning "Source path '$candidatePath' was not found."
                Write-RenderKitLog -Level Warning -Message "Source path '$candidatePath' was not found."
                continue
            }

            if (-not (Test-Path -Path $resolvedPath -PathType Container)) {
                Write-Warning "Source path '$resolvedPath' is not a directory."
                Write-RenderKitLog -Level Warning -Message "Source path '$resolvedPath' is not a directory."
                continue
            }

            return [PSCustomObject]@{
                SourcePath                   = $resolvedPath
                FolderFilter                 = @()
                IncludeFixed                 = $effectiveIncludeFixed
                IncludeUnsupportedFileSystem = $effectiveIncludeUnsupported
                SelectedDrive                = $selectedDrive
            }
        }
    }

    while ($true) {
        $manualPath = Read-Host "Absolute source folder path (Enter to cancel)"
        if ([string]::IsNullOrWhiteSpace($manualPath)) {
            return $null
        }

        try {
            $resolvedPath = (Resolve-Path -Path $manualPath -ErrorAction Stop).ProviderPath
        }
        catch {
            Write-Warning "Source path '$manualPath' was not found."
            Write-RenderKitLog -Level Warning -Message "Source path '$manualPath' was not found."
            continue
        }

        if (-not (Test-Path -Path $resolvedPath -PathType Container)) {
            Write-Warning "Source path '$resolvedPath' is not a directory."
            Write-RenderKitLog -Level Warning -Message "Source path '$resolvedPath' is not a directory."
            continue
        }

        return [PSCustomObject]@{
            SourcePath                   = $resolvedPath
            FolderFilter                 = @()
            IncludeFixed                 = $effectiveIncludeFixed
            IncludeUnsupportedFileSystem = $effectiveIncludeUnsupported
            SelectedDrive                = $null
        }
    }
}

function Read-RenderKitImportUnassignedHandlingInteractive {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [ValidateSet("Prompt", "ToSort", "Skip")]
        [string]$Default = "Prompt"
    )

    while ($true) {
        $choice = Read-Host "Unassigned files: [P]rompt, [T]O SORT, [S]kip (default $Default)"
        if ([string]::IsNullOrWhiteSpace($choice)) {
            return $Default
        }

        switch ($choice.Trim().ToUpperInvariant()) {
            "P" { return "Prompt" }
            "PROMPT" { return "Prompt" }
            "T" { return "ToSort" }
            "TO" { return "ToSort" }
            "TOSORT" { return "ToSort" }
            "S" { return "Skip" }
            "SKIP" { return "Skip" }
            default {
                Write-Warning "Unknown option '$choice'."
            }
        }
    }
}

function Start-RenderKitImportInteractiveSetup {
    [CmdletBinding()]
    param(
        [string]$ProjectRoot,
        [switch]$IncludeFixed,
        [switch]$IncludeUnsupportedFileSystem,
        [ValidateSet("Prompt", "ToSort", "Skip")]
        [string]$UnassignedHandling = "Prompt"
    )

    Write-Information "Starting interactive import wizard..." -InformationAction Continue
    Write-Information "Step 1/3 - Select destination project" -InformationAction Continue

    $resolvedProjectRoot = Read-RenderKitImportProjectRootInteractive -ProjectRoot $ProjectRoot
    if ([string]::IsNullOrWhiteSpace($resolvedProjectRoot)) {
        Write-Information "Import wizard cancelled (no project selected)." -InformationAction Continue
        return $null
    }

    Show-RenderKitImportWizardStatus `
        -Title "Current context" `
        -Data ([ordered]@{
            Step      = "1/3"
            Project   = $resolvedProjectRoot
        })

    Write-Information "Step 2/3 - Select source" -InformationAction Continue

    $sourcePromptParameters = @{}
    if ($PSBoundParameters.ContainsKey("IncludeFixed")) {
        $sourcePromptParameters.IncludeFixed = [bool]$IncludeFixed
    }
    if ($PSBoundParameters.ContainsKey("IncludeUnsupportedFileSystem")) {
        $sourcePromptParameters.IncludeUnsupportedFileSystem = [bool]$IncludeUnsupportedFileSystem
    }

    $sourceSelection = Read-RenderKitImportSourcePathInteractive @sourcePromptParameters
    if (-not $sourceSelection) {
        Write-Information "Import wizard cancelled (no source selected)." -InformationAction Continue
        return $null
    }

    Show-RenderKitImportWizardStatus `
        -Title "Current context" `
        -Data ([ordered]@{
            Step                         = "2/3"
            Project                      = $resolvedProjectRoot
            SourcePath                   = [string]$sourceSelection.SourcePath
            SourceFolderFilter           = if ($sourceSelection.FolderFilter.Count -gt 0) { $sourceSelection.FolderFilter -join ", " } else { "<none>" }
            IncludeFixed                 = [bool]$sourceSelection.IncludeFixed
            IncludeUnsupportedFileSystem = [bool]$sourceSelection.IncludeUnsupportedFileSystem
        })

    Write-Information "Step 3/3 - Configure scan and selection behavior" -InformationAction Continue

    $interactiveFilter = Read-RenderKitImportYesNo -Prompt "Add optional filters (folder/date/wildcard)?" -Default $false
    $autoSelectAll = Read-RenderKitImportYesNo -Prompt "Auto-select all matched files?" -Default $false
    $autoConfirm = Read-RenderKitImportYesNo -Prompt "Auto-confirm import after selection?" -Default $false
    $resolvedUnassignedHandling = Read-RenderKitImportUnassignedHandlingInteractive -Default $UnassignedHandling

    Show-RenderKitImportWizardStatus `
        -Title "Wizard summary before scan" `
        -Data ([ordered]@{
            Step                         = "3/3"
            Project                      = $resolvedProjectRoot
            SourcePath                   = [string]$sourceSelection.SourcePath
            SourceFolderFilter           = if ($sourceSelection.FolderFilter.Count -gt 0) { $sourceSelection.FolderFilter -join ", " } else { "<none>" }
            InteractiveFilter            = [bool]$interactiveFilter
            AutoSelectAll                = [bool]$autoSelectAll
            AutoConfirm                  = [bool]$autoConfirm
            UnassignedHandling           = $resolvedUnassignedHandling
            TransferMode                 = "Will be asked at the end"
        })

    return [PSCustomObject]@{
        ScanAndFilter               = $true
        SourcePath                  = [string]$sourceSelection.SourcePath
        FolderFilter                = @($sourceSelection.FolderFilter)
        IncludeFixed                = [bool]$sourceSelection.IncludeFixed
        IncludeUnsupportedFileSystem = [bool]$sourceSelection.IncludeUnsupportedFileSystem
        InteractiveFilter           = [bool]$interactiveFilter
        AutoSelectAll               = [bool]$autoSelectAll
        AutoConfirm                 = [bool]$autoConfirm
        ProjectRoot                 = $resolvedProjectRoot
        Classify                    = $true
        Transfer                    = $true
        UnassignedHandling          = $resolvedUnassignedHandling
    }
}

function Read-RenderKitImportDate {
    [CmdletBinding()]
    [OutputType([System.DateTime])]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt
    )

    while ($true) {
        $inputValue = Read-Host $Prompt
        if ([string]::IsNullOrWhiteSpace($inputValue)) {
            return $null
        }

        $parsedDate = [datetime]::MinValue
        if ([datetime]::TryParse($inputValue, [ref]$parsedDate)) {
            return $parsedDate
        }

        Write-RenderKitLog -Level Warning -Message "Invalid date '$inputValue'. Use a parseable date/time string."
    }
}

function Read-RenderKitImportAdditionalCriterion {
    [CmdletBinding()]
    param()

    $folderInput = Read-Host "Additional folder filter(s), comma separated (Enter to skip)"
    $fromDate = Read-RenderKitImportDate -Prompt "Additional from date (Enter to skip, example 2026-02-20 14:30)"
    $toDate = Read-RenderKitImportDate -Prompt "Additional to date (Enter to skip, example 2026-02-24 20:00)"
    $wildcardInput = Read-Host "Additional wildcard filter(s), comma separated (example *.mov,*.wav; Enter to skip)"

    $folderFilter = ConvertFrom-RenderKitImportListInput -InputText $folderInput
    $wildcard = ConvertFrom-RenderKitImportListInput -InputText $wildcardInput

    if (
        $folderFilter.Count -eq 0 -and
        $wildcard.Count -eq 0 -and
        $null -eq $fromDate -and
        $null -eq $toDate
    ) {
        return $null
    }

    return New-RenderKitImportCriterion `
        -FolderFilter $folderFilter `
        -FromDate $fromDate `
        -ToDate $toDate `
        -Wildcard $wildcard
}

function Get-RenderKitImportTotalByte {
    [CmdletBinding()]
    [OutputType([System.Int64])]
    param(
        [object[]]$Files
    )

    if (-not $Files -or $Files.Count -eq 0) {
        return [int64]0
    }

    $sum = ($Files | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) {
        return [int64]0
    }

    return [int64]$sum
}

function ConvertTo-RenderKitHumanSize {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [int64]$Bytes
    )

    if ($Bytes -lt 1KB) {
        return "$Bytes B"
    }

    if ($Bytes -lt 1MB) {
        return ("{0:N2} KB" -f ([double]$Bytes / 1KB))
    }

    if ($Bytes -lt 1GB) {
        return ("{0:N2} MB" -f ([double]$Bytes / 1MB))
    }

    return ("{0:N2} GB" -f ([double]$Bytes / 1GB))
}

function Show-RenderKitImportPreviewTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Files,
        [int]$PreviewCount = 30,
        [string]$Title = "Import Preview"
    )

    Write-RenderKitLog -Level Info -Message "$Title - $($Files.Count) file(s)"

    if ($Files.Count -eq 0) {
        Write-RenderKitLog -Level Warning -Message "No files matched the current filter set."
        return
    }

    if ($PreviewCount -lt 1) {
        $PreviewCount = 1
    }

    $rows = @()
    for ($i = 0; $i -lt $Files.Count; $i++) {
        $file = $Files[$i]
        $rows += [PSCustomObject]@{
            Index     = $i
            Name      = $file.Name
            Folder    = if ($file.RelativeDirectory -eq ".") { "<root>" } else { $file.RelativeDirectory }
            LastWrite = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            Size      = ConvertTo-RenderKitHumanSize -Bytes ([int64]$file.Length)
        }
    }

    $rows | Select-Object -First $PreviewCount | Format-Table -AutoSize | Out-Host

    if ($Files.Count -gt $PreviewCount) {
        Write-RenderKitLog -Level Info -Message "Showing first $PreviewCount of $($Files.Count) file(s)."

    $totalBytes = Get-RenderKitImportTotalByte -Files $Files
    $totalGB = [Math]::Round(([double]$totalBytes / 1GB), 3)
    Write-RenderKitLog -Level Info -Message  "Total size: $totalGB GB"
}
}
function ConvertTo-RenderKitImportIndexSelection {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory)]
        [string]$InputText,
        [Parameter(Mandatory)]
        [int]$MaxIndex
    )

    $tokens = @(
        $InputText.Split(',') |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    if ($tokens.Count -eq 0) {
        Write-RenderKitLog -Level Error -Message "No indexes were provided"
        throw "No indexes were provided."
    }

    $indexList = New-Object System.Collections.Generic.List[int]
    foreach ($token in $tokens) {
        if ($token -match '^\d+$') {
            $value = [int]$token
            if ($value -lt 0 -or $value -gt $MaxIndex) {
                Write-RenderKitLog -Level Error -Message "Index '$value' is out of range. Allowed: 0-$MaxIndex."
                throw "Index '$value' is out of range. Allowed: 0-$MaxIndex."
            }

            $indexList.Add($value)
            continue
        }

        if ($token -match '^(\d+)\s*-\s*(\d+)$') {
            $start = [int]$Matches[1]
            $end = [int]$Matches[2]
            if ($start -gt $end) {
                $tmp = $start
                $start = $end
                $end = $tmp
            }

            if ($start -lt 0 -or $end -gt $MaxIndex) {
                Write-RenderKitLog -Level Error -Message "Range '$token' is out of range. Allowed: 0-$MaxIndex."
                throw "Range '$token' is out of range. Allowed: 0-$MaxIndex."
            }

            for ($i = $start; $i -le $end; $i++) {
                $indexList.Add($i)
            }

            continue
        }
        Write-RenderKitLog -Level Error -Message "Invalid index token '$token'."
        throw "Invalid index token '$token'."
    }

    return @($indexList | Sort-Object -Unique)
}

function Select-RenderKitImportFileSubset {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Files,
        [switch]$AutoSelectAll
    )

    if (-not $Files -or $Files.Count -eq 0) {
        return @()
    }

    if ($AutoSelectAll) {
        return $Files
    }

    while ($true) {
        $mode = Read-Host "Select files to import: [A]ll, [I]ndex list, [N]one (default A)"
        if ([string]::IsNullOrWhiteSpace($mode)) {
            return $Files
        }

        switch ($mode.Trim().ToUpperInvariant()) {
            "A" { return $Files }
            "ALL" { return $Files }
            "J" { return $Files }
            "JA" { return $Files }
            "N" { return @() }
            "NO" { return @() }
            "I" {
                $indexInput = Read-Host "Enter indexes or ranges (example: 0,3,5-8)"
                if ([string]::IsNullOrWhiteSpace($indexInput)) {
                    Write-Warning "No index selection entered."
                    continue
                }

                $indexes = ConvertTo-RenderKitImportIndexSelection `
                    -InputText $indexInput `
                    -MaxIndex ($Files.Count - 1)

                $selected = New-Object System.Collections.Generic.List[object]
                foreach ($index in $indexes) {
                    $selected.Add($Files[$index])
                }

                return $selected.ToArray()
            }
            default {
                Write-RenderKitLog -Level Warning -Message "Invalid selection mode '$mode'."
            }
        }
    }
}

function Confirm-RenderKitImportSelection {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory)]
        [int]$FileCount,
        [Parameter(Mandatory)]
        [int64]$TotalBytes,
        [switch]$AutoConfirm
    )

    if ($AutoConfirm) {
        return $true
    }

    $sizeGB = [Math]::Round(([double]$TotalBytes / 1GB), 3)
    $answer = Read-Host "Confirm import of $FileCount file(s), total $sizeGB GB? [Y/N]"
    if ([string]::IsNullOrWhiteSpace($answer)) {
        return $false
    }

    switch ($answer.Trim().ToUpperInvariant()) {
        "Y" { return $true }
        "YES" { return $true }
        "J" { return $true }
        "JA" { return $true }
        default { return $false }
    }
}

function ConvertTo-RenderKitImportNormalizedExtension {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [string]$Extension
    )

    if ([string]::IsNullOrWhiteSpace($Extension)) {
        return ""
    }

    $normalized = $Extension.Trim().ToLowerInvariant()
    if ($normalized -eq ".") {
        return ""
    }

    if (-not $normalized.StartsWith(".")) {
        $normalized = ".$normalized"
    }

    return $normalized
}

function Resolve-RenderKitImportProjectRoot {
    [CmdletBinding()]
    param(
        [string]$ProjectRoot
    )

    if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
        try {
            $resolvedProjectRoot = (Resolve-Path -Path $ProjectRoot -ErrorAction Stop).ProviderPath
        }
        catch {
            Write-RenderKitLog -Level Error -Message "Project root '$ProjectRoot' was not found."
            throw "Project root '$ProjectRoot' was not found."
        }

        if (-not (Test-Path -Path $resolvedProjectRoot -PathType Container)) {
            Write-RenderKitLog -Level Error -Message "Project root '$resolvedProjectRoot' is not a directory."
            throw "Project root '$resolvedProjectRoot' is not a directory."
        }

        $metadataPath = Join-Path $resolvedProjectRoot ".renderkit\project.json"
        if (-not (Test-Path -Path $metadataPath -PathType Leaf)) {
            Write-RenderKitLog -Level Error -Message "Project metadata not found at '$metadataPath'."
            throw "Project metadata not found at '$metadataPath'."
        }

        return $resolvedProjectRoot
    }

    $current = (Get-Location).ProviderPath
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        $metadataPath = Join-Path $current ".renderkit\project.json"
        if (Test-Path -Path $metadataPath -PathType Leaf) {
            return $current
        }

        $parent = Split-Path -Path $current -Parent
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) {
            break
        }

        $current = $parent
    }

    Write-RenderKitLog -Level Error -Message "No RenderKit project root found. Use -ProjectRoot or run inside a RenderKit project."
    throw "No RenderKit project root found. Use -ProjectRoot or run inside a RenderKit project."
}

function Read-RenderKitImportProjectMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    $metadataPath = Join-Path $ProjectRoot ".renderkit\project.json"
    if (-not (Test-Path -Path $metadataPath -PathType Leaf)) {
        Write-RenderKitLog -Level Error -Message "Project metadata not found at '$metadataPath'."
        throw "Project metadata not found at '$metadataPath'."
    }

    try {
        return Get-Content -Path $metadataPath -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-RenderKitLog -Level Error -Message "Invalid JSON in project metadata '$metadataPath'."
        throw "Invalid JSON in project metadata '$metadataPath'."
    }
}

function Get-RenderKitImportTemplateFoldersRecursively {
    [CmdletBinding()]
    param(
        [object[]]$Folders,
        [string]$ParentPath = "",
        [System.Collections.Generic.List[object]]$Collector
    )

    if ($null -eq $Collector) {
        Write-RenderKitLog -Level Error -Message "Collector must not be null."
        throw "Collector must not be null."
    }

    if (-not $Folders -or $Folders.Count -eq 0) {
        return
    }

    foreach ($folder in @($Folders)) {
        if (-not $folder) {
            continue
        }

        $folderName = $null
        if ($folder.PSObject.Properties.Name -contains "Name") {
            $folderName = [string]$folder.Name
        }
        elseif ($folder.PSObject.Properties.Name -contains "FolderName") {
            $folderName = [string]$folder.FolderName
        }

        if ([string]::IsNullOrWhiteSpace($folderName)) {
            continue
        }

        $relativePath = if ([string]::IsNullOrWhiteSpace($ParentPath)) {
            $folderName
        }
        else {
            "$ParentPath\$folderName"
        }
        $relativePath = $relativePath -replace '/', '\'

        $mappingId = $null
        if ($folder.PSObject.Properties.Name -contains "MappingId") {
            $mappingId = [string]$folder.MappingId
        }
        elseif ($folder.PSObject.Properties.Name -contains "Mapping") {
            $mappingId = [string]$folder.Mapping
        }

        if (-not [string]::IsNullOrWhiteSpace($mappingId)) {
            $mappingId = [IO.Path]::GetFileNameWithoutExtension($mappingId.Trim())
        }
        else {
            $mappingId = $null
        }

        $Collector.Add([PSCustomObject]@{
                Name         = $folderName
                RelativePath = $relativePath
                MappingId    = $mappingId
            })

        $children = @()
        if ($folder.PSObject.Properties.Name -contains "SubFolders") {
            $children = @($folder.SubFolders)
        }
        elseif ($folder.PSObject.Properties.Name -contains "Children") {
            $children = @($folder.Children)
        }
        elseif ($folder.PSObject.Properties.Name -contains "Folders") {
            $children = @($folder.Folders)
        }

        if ($children.Count -gt 0) {
            Get-RenderKitImportTemplateFoldersRecursively `
                -Folders $children `
                -ParentPath $relativePath `
                -Collector $Collector
        }
    }
}

function Get-RenderKitImportTemplateFolderMap {
    [CmdletBinding()]
    param(
        [object[]]$Folders
    )

    $rows = New-Object System.Collections.Generic.List[object]
    Get-RenderKitImportTemplateFoldersRecursively `
        -Folders $Folders `
        -Collector $rows

    return $rows.ToArray()
}

function Get-RenderKitImportTemplateContext {
    [CmdletBinding()]
    param(
        [string]$ProjectRoot,
        [string]$TemplateName
    )

    $resolvedProjectRoot = Resolve-RenderKitImportProjectRoot -ProjectRoot $ProjectRoot
    $projectMetadata = Read-RenderKitImportProjectMetadata -ProjectRoot $resolvedProjectRoot

    $resolvedTemplateName = $TemplateName
    if ([string]::IsNullOrWhiteSpace($resolvedTemplateName)) {
        if ($projectMetadata.PSObject.Properties.Name -contains "template" -and $projectMetadata.template) {
            if ($projectMetadata.template.PSObject.Properties.Name -contains "name") {
                $resolvedTemplateName = [string]$projectMetadata.template.name
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($resolvedTemplateName)) {
        Write-RenderKitLog -Level Error -Message "Template name could not be resolved from project metadata. Use -TemplateName."
        throw "Template name could not be resolved from project metadata. Use -TemplateName."
    }

    $template = Get-ProjectTemplate -TemplateName $resolvedTemplateName
    $folderMap = @(Get-RenderKitImportTemplateFolderMap -Folders @($template.Folders))

    $destinationFolders = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    foreach ($row in $folderMap) {
        if ([string]::IsNullOrWhiteSpace($row.RelativePath)) {
            continue
        }

        if (-not $seen.ContainsKey($row.RelativePath)) {
            $seen[$row.RelativePath] = $true
            $destinationFolders.Add($row.RelativePath)
        }
    }

    return [PSCustomObject]@{
        ProjectRoot        = $resolvedProjectRoot
        ProjectMetadata    = $projectMetadata
        TemplateName       = $resolvedTemplateName
        TemplateVersion    = if ($template.PSObject.Properties.Name -contains "Version") { [string]$template.Version } else { $null }
        TemplateSource     = if ($template.PSObject.Properties.Name -contains "Source") { [string]$template.Source } else { $null }
        ProjectSchemaVersion = if ($projectMetadata.PSObject.Properties.Name -contains "schemaVersion") { [string]$projectMetadata.schemaVersion } else { $null }
        Template           = $template
        FolderMap          = $folderMap
        DestinationFolders = $destinationFolders.ToArray()
    }
}

function Read-RenderKitImportMappingFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MappingId
    )

    if ([string]::IsNullOrWhiteSpace($MappingId)) {
        return $null
    }

    $normalizedMappingId = [IO.Path]::GetFileNameWithoutExtension($MappingId.Trim())
    if ([string]::IsNullOrWhiteSpace($normalizedMappingId)) {
        return $null
    }

    $candidatePaths = New-Object System.Collections.Generic.List[string]
    $candidatePaths.Add((Get-RenderKitUserMappingPath -MappingId $normalizedMappingId))

    $fileName = Resolve-RenderKitMappingFileName -MappingId $normalizedMappingId
    if (-not [string]::IsNullOrWhiteSpace($fileName)) {
        $systemMappingPath = Get-RenderKitSystemMappingPath -MappingId $normalizedMappingId
        if (-not $candidatePaths.Contains($systemMappingPath)) {
            $candidatePaths.Add($systemMappingPath)
        }
    }

    foreach ($path in $candidatePaths) {
        if (-not (Test-Path -Path $path -PathType Leaf)) {
            continue
        }

        try {
            return Get-Content -Path $path -Raw | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            Write-RenderKitLog -Level Warning -Message "Invalid JSON in mapping file '$path'."
        }
    }

    return $null
}

function New-RenderKitImportExtensionLookup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$TemplateContext
    )

    $lookup = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $mappingCache = @{}

    $mappedFolders = @(
        $TemplateContext.FolderMap |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.MappingId) }
    )

    foreach ($mappedFolder in $mappedFolders) {
        $mappingId = [string]$mappedFolder.MappingId
        if ([string]::IsNullOrWhiteSpace($mappingId)) {
            continue
        }

        if (-not $mappingCache.ContainsKey($mappingId)) {
            $mappingCache[$mappingId] = Read-RenderKitImportMappingFile -MappingId $mappingId
        }

        $mapping = $mappingCache[$mappingId]
        if (-not $mapping) {
            Write-RenderKitLog -Level Warning -Message "Mapping '$mappingId' could not be resolved for folder '$($mappedFolder.RelativePath)'."
            continue
        }

        foreach ($type in @($mapping.Types)) {
            if (-not $type) {
                continue
            }

            $typeName = [string]$type.Name
            if ([string]::IsNullOrWhiteSpace($typeName)) {
                $typeName = "(unnamed)"
            }

            foreach ($extension in @($type.Extensions)) {
                $normalizedExtension = ConvertTo-RenderKitImportNormalizedExtension -Extension ([string]$extension)
                if ([string]::IsNullOrWhiteSpace($normalizedExtension)) {
                    continue
                }

                if (-not $lookup.ContainsKey($normalizedExtension)) {
                    $lookup.Add($normalizedExtension, (New-Object System.Collections.Generic.List[object]))
                }

                $entryExists = $false
                foreach ($entry in $lookup[$normalizedExtension]) {
                    if (
                        $entry.MappingId -eq $mappingId -and
                        $entry.TypeName -eq $typeName -and
                        $entry.RelativeDestination -eq $mappedFolder.RelativePath
                    ) {
                        $entryExists = $true
                        break
                    }
                }

                if ($entryExists) {
                    continue
                }

                $lookup[$normalizedExtension].Add([PSCustomObject]@{
                        MappingId           = $mappingId
                        TypeName            = $typeName
                        RelativeDestination = $mappedFolder.RelativePath
                        DestinationPath     = Join-Path $TemplateContext.ProjectRoot $mappedFolder.RelativePath
                    })
            }
        }
    }

    return [PSCustomObject]@{
        ExtensionLookup = $lookup
        DestinationFolders = @($TemplateContext.DestinationFolders)
    }
}

function Show-RenderKitImportDestinationFolderTable {
    [CmdletBinding()]
    param(
        [string[]]$DestinationFolders
    )

    if (-not $DestinationFolders -or $DestinationFolders.Count -eq 0) {
        Write-RenderKitLog -Level Warning -Message "Template has no destination folders."
        return
    }

    $rows = @()
    for ($i = 0; $i -lt $DestinationFolders.Count; $i++) {
        $rows += [PSCustomObject]@{
            Index  = $i
            Folder = $DestinationFolders[$i]
        }
    }

    $rows | Format-Table -AutoSize | Out-Host
}

function Read-RenderKitImportUnassignedAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ExtensionLabel,
        [Parameter(Mandatory)]
        [int]$FileCount,
        [string[]]$DestinationFolders,
        [ValidateSet("Prompt", "ToSort", "Skip")]
        [string]$HandlingMode = "Prompt"
    )

    if ($HandlingMode -eq "ToSort") {
        return [PSCustomObject]@{ Mode = "ToSort" }
    }

    if ($HandlingMode -eq "Skip") {
        return [PSCustomObject]@{ Mode = "Skip" }
    }

    while ($true) {
        $choice = Read-Host "Extension '$ExtensionLabel' ($FileCount file(s)): [I]ndex folder, [T]O SORT, [S]kip (default T)"
        if ([string]::IsNullOrWhiteSpace($choice)) {
            return [PSCustomObject]@{ Mode = "ToSort" }
        }

        switch ($choice.Trim().ToUpperInvariant()) {
            "I" {
                if (-not $DestinationFolders -or $DestinationFolders.Count -eq 0) {
                    Write-RenderKitLog -Level Warning -Message "No destination folders available. Choose TO SORT or Skip."
                    continue
                }

                $indexText = Read-Host "Destination folder index (0-$($DestinationFolders.Count - 1))"
                $index = -1
                if (-not [int]::TryParse($indexText, [ref]$index)) {
                    Write-RenderKitLog -Level Warning -Message "Invalid destination index '$indexText'."
                    continue
                }

                if ($index -lt 0 -or $index -ge $DestinationFolders.Count) {
                    Write-RenderKitLog -Level Warning -Message "Destination index '$index' out of range."
                    continue
                }

                return [PSCustomObject]@{
                    Mode                = "Assign"
                    RelativeDestination = $DestinationFolders[$index]
                }
            }
            "T" { return [PSCustomObject]@{ Mode = "ToSort" } }
            "TO" { return [PSCustomObject]@{ Mode = "ToSort" } }
            "S" { return [PSCustomObject]@{ Mode = "Skip" } }
            default {
                Write-RenderKitLog -Level Warning -Message "Invalid choice '$choice'."
            }
        }
    }
}

function Resolve-RenderKitImportUnassignedFile {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$ClassifiedFiles,
        [string[]]$DestinationFolders,
        [Parameter(Mandatory)]
        [string]$ProjectRoot,
        [ValidateSet("Prompt", "ToSort", "Skip")]
        [string]$HandlingMode = "Prompt",
        [string]$UnassignedFolderName = "TO SORT"
    )

    if ([string]::IsNullOrWhiteSpace($UnassignedFolderName)) {
        $UnassignedFolderName = "TO SORT"
    }

    $unassigned = @(
        $ClassifiedFiles |
            Where-Object { $_.Classification -eq "Unassigned" }
    )

    if ($unassigned.Count -eq 0) {
        return $ClassifiedFiles
    }

    $summaryRows = @(
        $unassigned |
            Group-Object NormalizedExtension |
            Sort-Object Name |
            ForEach-Object {
                [PSCustomObject]@{
                    Extension = if ([string]::IsNullOrWhiteSpace($_.Name)) { "<no extension>" } else { $_.Name }
                    Files     = $_.Count
                    Size      = ConvertTo-RenderKitHumanSize -Bytes ([int64](($_.Group | Measure-Object -Property Length -Sum).Sum))
                }
            }
    )

    Write-RenderKitLog -Level Info -Message "Unassigned file extensions detected: $($summaryRows.Count)"
    $summaryRows | Format-Table -AutoSize | Out-Host

    if ($HandlingMode -eq "Prompt") {
        Show-RenderKitImportDestinationFolderTable -DestinationFolders $DestinationFolders
    }

    foreach ($group in ($unassigned | Group-Object NormalizedExtension | Sort-Object Name)) {
        $extensionLabel = if ([string]::IsNullOrWhiteSpace($group.Name)) { "<no extension>" } else { $group.Name }

        $fileRows = @()
        $groupFiles = @($group.Group | Sort-Object LastWriteTime, Name)
        $previewLimit = 20
        $previewFiles = @($groupFiles | Select-Object -First $previewLimit)
        for ($i = 0; $i -lt $previewFiles.Count; $i++) {
            $item = $previewFiles[$i]
            $fileRows += [PSCustomObject]@{
                Index      = $i
                File       = $item.Name
                Folder     = if ([string]::IsNullOrWhiteSpace($item.RelativeDirectory) -or $item.RelativeDirectory -eq ".") { "<root>" } else { $item.RelativeDirectory }
                Size       = ConvertTo-RenderKitHumanSize -Bytes ([int64]$item.Length)
                Reason     = $item.UnassignedReason
            }
        }

        if ($fileRows.Count -gt 0) {
            Write-RenderKitLog -Level Info -Message "Unassigned preview for '$extensionLabel' ($($group.Count) file(s))"
            $fileRows | Format-Table -AutoSize | Out-Host
            if ($group.Count -gt $previewLimit) {
                Write-RenderKitLog -Level Info -Message "Showing first $previewLimit of $($group.Count) file(s) for '$extensionLabel'."
            }
        }

        $action = Read-RenderKitImportUnassignedAction `
            -ExtensionLabel $extensionLabel `
            -FileCount $group.Count `
            -DestinationFolders $DestinationFolders `
            -HandlingMode $HandlingMode

        foreach ($file in $group.Group) {
            switch ($action.Mode) {
                "Assign" {
                    $file.Classification = "Assigned"
                    $file.MappingId = "manual"
                    $file.TypeName = "manual"
                    $file.DestinationRelativePath = $action.RelativeDestination
                    $file.DestinationPath = Join-Path $ProjectRoot $action.RelativeDestination
                    $file.UnassignedReason = $null
                }
                "ToSort" {
                    $file.Classification = "ToSort"
                    $file.MappingId = $null
                    $file.TypeName = "unassigned"
                    $file.DestinationRelativePath = $UnassignedFolderName
                    $file.DestinationPath = Join-Path $ProjectRoot $UnassignedFolderName
                    $file.UnassignedReason = "Unassigned extension routed to '$UnassignedFolderName'."
                }
                default {
                    $file.Classification = "Skipped"
                    $file.MappingId = $null
                    $file.TypeName = $null
                    $file.DestinationRelativePath = $null
                    $file.DestinationPath = $null
                    $file.UnassignedReason = "Unassigned extension skipped."
                }
            }
        }
    }

    return $ClassifiedFiles
}

function Show-RenderKitImportClassificationPreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Files,
        [int]$PreviewCount = 30,
        [string]$Title = "Phase 3 classification preview"
    )

    Write-RenderKitLog -Level Info -Message "$Title - $($Files.Count) file(s)"

    if (-not $Files -or $Files.Count -eq 0) {
        Write-RenderKitLog -Level Warning -Message "No files available for classification preview."
        return
    }

    if ($PreviewCount -lt 1) {
        $PreviewCount = 1
    }

    $rows = @()
    for ($i = 0; $i -lt $Files.Count; $i++) {
        $file = $Files[$i]
        $rows += [PSCustomObject]@{
            Index          = $i
            Name           = $file.Name
            Extension      = if ([string]::IsNullOrWhiteSpace($file.NormalizedExtension)) { "<none>" } else { $file.NormalizedExtension }
            Classification = $file.Classification
            Destination    = if ([string]::IsNullOrWhiteSpace($file.DestinationRelativePath)) { "-" } else { $file.DestinationRelativePath }
        }
    }

    $rows | Select-Object -First $PreviewCount | Format-Table -AutoSize | Out-Host
    if ($Files.Count -gt $PreviewCount) {
        Write-RenderKitLog -Level Info -Message "Showing first $PreviewCount of $($Files.Count) file(s)."
    }
}

function Get-RenderKitImportFileClassification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Files,
        [string]$ProjectRoot,
        [string]$TemplateName,
        [ValidateSet("Prompt", "ToSort", "Skip")]
        [string]$UnassignedHandling = "Prompt",
        [string]$UnassignedFolderName = "TO SORT"
    )

    if (-not $Files -or $Files.Count -eq 0) {
        return [PSCustomObject]@{
            ProjectRoot      = $null
            TemplateName     = $TemplateName
            FileCount        = 0
            AssignedCount    = 0
            ToSortCount      = 0
            SkippedCount     = 0
            UnassignedCount  = 0
            AssignedBytes    = [int64]0
            ToSortBytes      = [int64]0
            SkippedBytes     = [int64]0
            UnassignedBytes  = [int64]0
            DestinationFolders = @()
            Files            = @()
        }
    }

    $templateContext = Get-RenderKitImportTemplateContext `
        -ProjectRoot $ProjectRoot `
        -TemplateName $TemplateName

    Write-RenderKitLog -Level Info -Message "Phase 3 context: project '$($templateContext.ProjectRoot)', template '$($templateContext.TemplateName)'."

    $lookupContext = New-RenderKitImportExtensionLookup -TemplateContext $templateContext
    if ($lookupContext.ExtensionLookup.Keys.Count -eq 0) {
        Write-RenderKitLog -Level Warning -Message "No extension mapping rules were found in template folder mappings."
    }

    $classified = New-Object System.Collections.Generic.List[object]
    foreach ($file in $Files) {
        $normalizedExtension = ConvertTo-RenderKitImportNormalizedExtension -Extension ([string]$file.Extension)
        $candidates = @()
        $candidateList = $null
        if (
            -not [string]::IsNullOrWhiteSpace($normalizedExtension) -and
            $lookupContext.ExtensionLookup.TryGetValue($normalizedExtension, [ref]$candidateList)
        ) {
            foreach ($candidateItem in $candidateList) {
                $candidates += $candidateItem
            }
        }

        $classification = "Unassigned"
        $reason = if ([string]::IsNullOrWhiteSpace($normalizedExtension)) {
            "File has no extension."
        }
        else {
            "No folder mapping found for extension '$normalizedExtension'."
        }

        $mappingId = $null
        $typeName = $null
        $destinationRelativePath = $null
        $destinationPath = $null

        if ($candidates.Count -eq 1) {
            $candidate = $candidates[0]
            $classification = "Assigned"
            $reason = $null
            $mappingId = $candidate.MappingId
            $typeName = $candidate.TypeName
            $destinationRelativePath = $candidate.RelativeDestination
            $destinationPath = $candidate.DestinationPath
        }
        elseif ($candidates.Count -gt 1) {
            $reason = "Ambiguous mapping for extension '$normalizedExtension'."
        }

        $classified.Add([PSCustomObject]@{
                Name                    = $file.Name
                FullName                = $file.FullName
                RelativePath            = $file.RelativePath
                RelativeDirectory       = $file.RelativeDirectory
                Extension               = $file.Extension
                NormalizedExtension     = $normalizedExtension
                LastWriteTime           = $file.LastWriteTime
                Length                  = [int64]$file.Length
                Classification          = $classification
                MappingId               = $mappingId
                TypeName                = $typeName
                DestinationRelativePath = $destinationRelativePath
                DestinationPath         = $destinationPath
                UnassignedReason        = $reason
            })
    }

    $resolvedClassified = @(
        Resolve-RenderKitImportUnassignedFile `
            -ClassifiedFiles $classified.ToArray() `
            -DestinationFolders $lookupContext.DestinationFolders `
            -ProjectRoot $templateContext.ProjectRoot `
            -HandlingMode $UnassignedHandling `
            -UnassignedFolderName $UnassignedFolderName
    )

    $assigned = @($resolvedClassified | Where-Object { $_.Classification -eq "Assigned" })
    $toSort = @($resolvedClassified | Where-Object { $_.Classification -eq "ToSort" })
    $skipped = @($resolvedClassified | Where-Object { $_.Classification -eq "Skipped" })
    $stillUnassigned = @($resolvedClassified | Where-Object { $_.Classification -eq "Unassigned" })

    return [PSCustomObject]@{
        ProjectRoot        = $templateContext.ProjectRoot
        TemplateName       = $templateContext.TemplateName
        TemplateVersion    = $templateContext.TemplateVersion
        TemplateSource     = $templateContext.TemplateSource
        ProjectSchemaVersion = $templateContext.ProjectSchemaVersion
        FileCount          = $resolvedClassified.Count
        AssignedCount      = $assigned.Count
        ToSortCount        = $toSort.Count
        SkippedCount       = $skipped.Count
        UnassignedCount    = $stillUnassigned.Count
        AssignedBytes      = Get-RenderKitImportTotalByte -Files $assigned
        ToSortBytes        = Get-RenderKitImportTotalByte -Files $toSort
        SkippedBytes       = Get-RenderKitImportTotalByte -Files $skipped
        UnassignedBytes    = Get-RenderKitImportTotalByte -Files $stillUnassigned
        DestinationFolders = @($lookupContext.DestinationFolders)
        Files              = $resolvedClassified
    }
}

function Get-RenderKitImportTransferCandidateFile {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$ClassifiedFiles
    )

    if (-not $ClassifiedFiles -or $ClassifiedFiles.Count -eq 0) {
        return @()
    }

    return @(
        $ClassifiedFiles |
            Where-Object {
                $_.Classification -in @("Assigned", "ToSort") -and
                -not [string]::IsNullOrWhiteSpace([string]$_.DestinationPath)
            }
    )
}

function Resolve-RenderKitImportUniqueFilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [System.Collections.Generic.HashSet[string]]$ReservedPaths
    )

    if ($null -eq $ReservedPaths) {
        Write-RenderKitLog -Level Error -Message "ReservedPaths must not be null."
        throw "ReservedPaths must not be null."
    }

    $directory = Split-Path -Path $Path -Parent
    $fileName = [IO.Path]::GetFileNameWithoutExtension($Path)
    $extension = [IO.Path]::GetExtension($Path)

    if ([string]::IsNullOrWhiteSpace($directory)) {
        Write-RenderKitLog -Level Error -Message "Destination path '$Path' has no parent directory."
        throw "Destination path '$Path' has no parent directory."
    }

    $candidate = $Path
    $counter = 1
    while ((Test-Path -Path $candidate -PathType Leaf) -or $ReservedPaths.Contains($candidate)) {
        $candidate = Join-Path $directory ("{0}_{1:D3}{2}" -f $fileName, $counter, $extension)
        $counter++
    }

    $null = $ReservedPaths.Add($candidate)
    return $candidate
}

function New-RenderKitImportTransferRunContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    $renderKitRoot = Join-Path $ProjectRoot ".renderkit"
    if (-not (Test-Path -Path $renderKitRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $renderKitRoot -Force | Out-Null
    }

    $tempRoot = Join-Path $renderKitRoot "import-temp"
    if (-not (Test-Path -Path $tempRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    }

    $runId = "import-{0}-{1}" -f (Get-Date).ToString("yyyyMMdd-HHmmss"), ([guid]::NewGuid().ToString("N").Substring(0, 8))
    $tempRunRoot = Join-Path $tempRoot $runId
    New-Item -ItemType Directory -Path $tempRunRoot -Force | Out-Null

    return [PSCustomObject]@{
        RunId       = $runId
        TempRoot    = $tempRoot
        TempRunRoot = $tempRunRoot
    }
}

function Get-RenderKitImportFileHashValue {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [ValidateSet("SHA256", "SHA1", "MD5")]
        [string]$Algorithm = "SHA256",
        [scriptblock]$ProgressCallback
    )

    $bufferSizeBytes = 4MB
    $buffer = New-Object byte[] $bufferSizeBytes
    $inputStream = $null
    $hashAlgorithm = $null
    $cryptoStream = $null
    $processedBytes = [int64]0
    $totalBytes = [int64]0
    $lastProgressAt = [datetime]::MinValue

    try {
        switch ($Algorithm) {
            "SHA256" { $hashAlgorithm = [System.Security.Cryptography.SHA256]::Create() }
            "SHA1" { $hashAlgorithm = [System.Security.Cryptography.SHA1]::Create() }
            "MD5" { $hashAlgorithm = [System.Security.Cryptography.MD5]::Create() }
        }

        $inputStream = New-Object System.IO.FileStream(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read,
            $bufferSizeBytes,
            [System.IO.FileOptions]::SequentialScan
        )

        $totalBytes = [int64]$inputStream.Length
        $cryptoStream = New-Object System.Security.Cryptography.CryptoStream(
            [System.IO.Stream]::Null,
            $hashAlgorithm,
            [System.Security.Cryptography.CryptoStreamMode]::Write
        )

        if ($ProgressCallback) {
            & $ProgressCallback $processedBytes $totalBytes
        }

        while (($readCount = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $cryptoStream.Write($buffer, 0, $readCount)
            $processedBytes += $readCount

            $now = Get-Date
            if (
                $ProgressCallback -and (
                    $processedBytes -ge $totalBytes -or
                    $lastProgressAt -eq [datetime]::MinValue -or
                    ($now - $lastProgressAt).TotalMilliseconds -ge 150
                )
            ) {
                & $ProgressCallback $processedBytes $totalBytes
                $lastProgressAt = $now
            }
        }

        $cryptoStream.FlushFinalBlock()
        return ([System.BitConverter]::ToString($hashAlgorithm.Hash)).Replace("-", "")
    }
    catch {
        Write-RenderKitLog -Level Error -Message "Could not calculate $Algorithm hash for '$Path': $($_.Exception.Message)"
        throw
    }
    finally {
        if ($cryptoStream) {
            $cryptoStream.Dispose()
        }

        if ($hashAlgorithm) {
            $hashAlgorithm.Dispose()
        }

        if ($inputStream) {
            $inputStream.Dispose()
        }
    }
}

function Copy-RenderKitImportFileToPath {
    [CmdletBinding()]
    [OutputType([System.Int64])]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,
        [Parameter(Mandatory)]
        [string]$DestinationPath,
        [scriptblock]$ProgressCallback
    )

    $bufferSizeBytes = 4MB
    $buffer = New-Object byte[] $bufferSizeBytes
    $sourceItem = Get-Item -LiteralPath $SourcePath -ErrorAction Stop
    $sourceStream = $null
    $destinationStream = $null
    $copiedBytes = [int64]0
    $totalBytes = [int64]$sourceItem.Length
    $lastProgressAt = [datetime]::MinValue

    try {
        $sourceStream = New-Object System.IO.FileStream(
            $sourceItem.FullName,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read,
            $bufferSizeBytes,
            [System.IO.FileOptions]::SequentialScan
        )

        $destinationStream = New-Object System.IO.FileStream(
            $DestinationPath,
            [System.IO.FileMode]::Create,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None,
            $bufferSizeBytes,
            [System.IO.FileOptions]::SequentialScan
        )

        if ($ProgressCallback) {
            & $ProgressCallback $copiedBytes $totalBytes
        }

        while (($readCount = $sourceStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $destinationStream.Write($buffer, 0, $readCount)
            $copiedBytes += $readCount

            $now = Get-Date
            if (
                $ProgressCallback -and (
                    $copiedBytes -ge $totalBytes -or
                    $lastProgressAt -eq [datetime]::MinValue -or
                    ($now - $lastProgressAt).TotalMilliseconds -ge 150
                )
            ) {
                & $ProgressCallback $copiedBytes $totalBytes
                $lastProgressAt = $now
            }
        }

        $destinationStream.Flush()
    }
    catch {
        if (Test-Path -LiteralPath $DestinationPath -PathType Leaf) {
            Remove-Item -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue
        }

        throw
    }
    finally {
        if ($destinationStream) {
            $destinationStream.Dispose()
        }

        if ($sourceStream) {
            $sourceStream.Dispose()
        }
    }

    try {
        [System.IO.File]::SetCreationTimeUtc($DestinationPath, $sourceItem.CreationTimeUtc)
        [System.IO.File]::SetLastWriteTimeUtc($DestinationPath, $sourceItem.LastWriteTimeUtc)
        [System.IO.File]::SetLastAccessTimeUtc($DestinationPath, $sourceItem.LastAccessTimeUtc)
    }
    catch {
        Write-RenderKitLog -Level Warning -Message "Could not preserve timestamps for '$DestinationPath': $($_.Exception.Message)"
    }

    return $copiedBytes
}

function Update-RenderKitImportTransferProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [datetime]$StartedAt,
        [Parameter(Mandatory)]
        [int]$CompletedCount,
        [Parameter(Mandatory)]
        [int]$TotalCount,
        [Parameter(Mandatory)]
        [int64]$ProcessedBytes,
        [Parameter(Mandatory)]
        [int64]$TotalBytes,
        [string]$CurrentOperation,
        [int64]$ProgressBytesCompleted = -1,
        [int64]$ProgressBytesTotal = -1,
        [string]$Stage,
        [int64]$CurrentFileProcessedBytes = -1,
        [int64]$CurrentFileTotalBytes = -1
    )

    if ($ProgressBytesCompleted -lt 0) {
        $ProgressBytesCompleted = $ProcessedBytes
    }

    if ($ProgressBytesTotal -lt 0) {
        $ProgressBytesTotal = $TotalBytes
    }

    $elapsedSeconds = ((Get-Date) - $StartedAt).TotalSeconds
    if ($elapsedSeconds -lt 0.001) {
        $elapsedSeconds = 0.001
    }

    $speedMBps = ([double]$ProgressBytesCompleted / 1MB) / $elapsedSeconds

    $percent = 0
    if ($ProgressBytesTotal -gt 0) {
        $percent = [int][Math]::Min(100, [Math]::Floor(([double]$ProgressBytesCompleted * 100.0) / [double]$ProgressBytesTotal))
    }
    elseif ($TotalCount -gt 0) {
        $percent = [int][Math]::Min(100, [Math]::Floor(([double]$CompletedCount * 100.0) / [double]$TotalCount))
    }

    $statusSegments = New-Object System.Collections.Generic.List[string]
    $statusSegments.Add(("{0}/{1} files" -f $CompletedCount, $TotalCount))
    $statusSegments.Add(("imported {0} / {1}" -f `
        (ConvertTo-RenderKitHumanSize -Bytes $ProcessedBytes), `
        (ConvertTo-RenderKitHumanSize -Bytes $TotalBytes)))

    if ($CurrentFileTotalBytes -ge 0 -and -not [string]::IsNullOrWhiteSpace($Stage)) {
        $currentFileStatus = "{0} {1} / {2}" -f `
            $Stage, `
            (ConvertTo-RenderKitHumanSize -Bytes ([Math]::Max([int64]0, $CurrentFileProcessedBytes))), `
            (ConvertTo-RenderKitHumanSize -Bytes $CurrentFileTotalBytes)
        $statusSegments.Add($currentFileStatus)
    }

    $statusSegments.Add(("{0:N2} MB/s" -f $speedMBps))
    $status = [string]::Join(" | ", $statusSegments.ToArray())

    Write-Progress `
        -Activity "Phase 4 - Transaction-Safe Transfer" `
        -Status $status `
        -CurrentOperation $CurrentOperation `
        -PercentComplete $percent
}

function Invoke-RenderKitImportTransactionSafeTransfer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$ClassifiedFiles,
        [Parameter(Mandatory)]
        [string]$ProjectRoot,
        [ValidateSet("SHA256", "SHA1", "MD5")]
        [string]$HashAlgorithm = "SHA256",
        [switch]$Simulate
    )

    $transferCandidates = @(Get-RenderKitImportTransferCandidateFile -ClassifiedFiles $ClassifiedFiles)
    $notTransferable = @(
        $ClassifiedFiles |
            Where-Object {
                $_.Classification -notin @("Assigned", "ToSort") -or
                [string]::IsNullOrWhiteSpace([string]$_.DestinationPath)
            }
    )

    $plannedBytes = Get-RenderKitImportTotalByte -Files $transferCandidates
    if ($transferCandidates.Count -eq 0) {
        return [PSCustomObject]@{
            ProjectRoot             = $ProjectRoot
            RunId                   = $null
            TempRunRoot             = $null
            Simulated               = [bool]$Simulate
            HashAlgorithm           = $HashAlgorithm
            PlannedFileCount        = 0
            NotTransferableFileCount = $notTransferable.Count
            ImportedFileCount       = 0
            SimulatedFileCount      = 0
            FailedFileCount         = 0
            PlannedBytes            = [int64]0
            ProcessedBytes          = [int64]0
            DurationSeconds         = [double]0
            AverageSpeedMBps        = [double]0
            StartedAt               = $null
            EndedAt                 = $null
            Transactions            = @()
        }
    }

    $startTime = Get-Date
    $processedBytes = [int64]0
    $progressTotalBytes = if ($Simulate) { [int64]$plannedBytes } else { [int64]($plannedBytes * 3) }
    $completedProgressBytes = [int64]0
    $importedCount = 0
    $simulatedCount = 0
    $failedCount = 0
    $completedCount = 0
    $transferTransactions = New-Object System.Collections.Generic.List[object]
    $reservedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $runId = $null
    $tempRunRoot = $null
    if (-not $Simulate) {
        $runContext = New-RenderKitImportTransferRunContext -ProjectRoot $ProjectRoot
        $runId = $runContext.RunId
        $tempRunRoot = $runContext.TempRunRoot
        Write-RenderKitLog -Level Info -Message "Phase 4 transaction run '$runId' started. Temp root: '$tempRunRoot'."
    }
    else {
        Write-RenderKitLog -Level Info -Message "Phase 4 transfer is running in WhatIf simulation mode."
    }

    try {
        for ($i = 0; $i -lt $transferCandidates.Count; $i++) {
            $file = $transferCandidates[$i]
            $fileStart = Get-Date
            $sourcePath = [string]$file.FullName
            $destinationDirectory = [string]$file.DestinationPath
            $destinationRelativePath = [string]$file.DestinationRelativePath
            $finalDestinationPath = $null
            $stagingPath = $null
            $sourceHash = $null
            $stagingHash = $null
            $errorMessage = $null
            $status = "Pending"
            $bytes = [int64]$file.Length
            $progressBytesForCurrentFile = if ($Simulate) { $bytes } else { [int64]($bytes * 3) }

            try {
                if ([string]::IsNullOrWhiteSpace($destinationDirectory)) {
                    Write-RenderKitLog -Level Error -Message "Destination path is empty for '$sourcePath'."
                    throw "Destination path is empty for '$sourcePath'."
                }

                $targetPath = Join-Path $destinationDirectory $file.Name
                $finalDestinationPath = Resolve-RenderKitImportUniqueFilePath `
                    -Path $targetPath `
                    -ReservedPaths $reservedPaths

                if ($Simulate) {
                    $status = "Simulated"
                    $simulatedCount++
                    $processedBytes += $bytes
                    Update-RenderKitImportTransferProgress `
                        -StartedAt $startTime `
                        -CompletedCount ($completedCount + 1) `
                        -TotalCount $transferCandidates.Count `
                        -ProcessedBytes $processedBytes `
                        -TotalBytes $plannedBytes `
                        -ProgressBytesCompleted ($completedProgressBytes + $progressBytesForCurrentFile) `
                        -ProgressBytesTotal $progressTotalBytes `
                        -Stage "simulate" `
                        -CurrentFileProcessedBytes $bytes `
                        -CurrentFileTotalBytes $bytes `
                        -CurrentOperation ("SIMULATE: {0} -> {1}" -f $file.Name, $destinationRelativePath)
                }
                else {
                    $stagingPath = Join-Path $tempRunRoot ("{0:D6}_{1}" -f ($i + 1), $file.Name)

                    if (-not (Test-Path -Path $destinationDirectory -PathType Container)) {
                        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
                    }

                    $copyProgressCallback = {
                        param([int64]$currentBytes, [int64]$currentTotalBytes)

                        Update-RenderKitImportTransferProgress `
                            -StartedAt $startTime `
                            -CompletedCount $completedCount `
                            -TotalCount $transferCandidates.Count `
                            -ProcessedBytes $processedBytes `
                            -TotalBytes $plannedBytes `
                            -ProgressBytesCompleted ($completedProgressBytes + $currentBytes) `
                            -ProgressBytesTotal $progressTotalBytes `
                            -Stage "copy" `
                            -CurrentFileProcessedBytes $currentBytes `
                            -CurrentFileTotalBytes $currentTotalBytes `
                            -CurrentOperation ("COPY: {0} -> {1}" -f $file.Name, $destinationRelativePath)
                    }

                    $sourceHashProgressCallback = {
                        param([int64]$currentBytes, [int64]$currentTotalBytes)

                        Update-RenderKitImportTransferProgress `
                            -StartedAt $startTime `
                            -CompletedCount $completedCount `
                            -TotalCount $transferCandidates.Count `
                            -ProcessedBytes $processedBytes `
                            -TotalBytes $plannedBytes `
                            -ProgressBytesCompleted ($completedProgressBytes + $bytes + $currentBytes) `
                            -ProgressBytesTotal $progressTotalBytes `
                            -Stage "hash source" `
                            -CurrentFileProcessedBytes $currentBytes `
                            -CurrentFileTotalBytes $currentTotalBytes `
                            -CurrentOperation ("VERIFY SOURCE: {0}" -f $file.Name)
                    }

                    $stagingHashProgressCallback = {
                        param([int64]$currentBytes, [int64]$currentTotalBytes)

                        Update-RenderKitImportTransferProgress `
                            -StartedAt $startTime `
                            -CompletedCount $completedCount `
                            -TotalCount $transferCandidates.Count `
                            -ProcessedBytes $processedBytes `
                            -TotalBytes $plannedBytes `
                            -ProgressBytesCompleted ($completedProgressBytes + (2 * $bytes) + $currentBytes) `
                            -ProgressBytesTotal $progressTotalBytes `
                            -Stage "hash staging" `
                            -CurrentFileProcessedBytes $currentBytes `
                            -CurrentFileTotalBytes $currentTotalBytes `
                            -CurrentOperation ("VERIFY STAGING: {0}" -f $file.Name)
                    }

                    Copy-RenderKitImportFileToPath `
                        -SourcePath $sourcePath `
                        -DestinationPath $stagingPath `
                        -ProgressCallback $copyProgressCallback | Out-Null
                    $sourceHash = Get-RenderKitImportFileHashValue `
                        -Path $sourcePath `
                        -Algorithm $HashAlgorithm `
                        -ProgressCallback $sourceHashProgressCallback
                    $stagingHash = Get-RenderKitImportFileHashValue `
                        -Path $stagingPath `
                        -Algorithm $HashAlgorithm `
                        -ProgressCallback $stagingHashProgressCallback

                    if ($sourceHash -ne $stagingHash) {
                        Write-RenderKitLog -Level Error -Message "Hash mismatch for '$sourcePath'. Source '$sourceHash', staging '$stagingHash'."
                        throw "Hash mismatch for '$sourcePath'. Source '$sourceHash', staging '$stagingHash'."
                    }

                    Move-Item -LiteralPath $stagingPath -Destination $finalDestinationPath -ErrorAction Stop

                    $status = "Imported"
                    $importedCount++
                    $processedBytes += $bytes

                    Update-RenderKitImportTransferProgress `
                        -StartedAt $startTime `
                        -CompletedCount ($completedCount + 1) `
                        -TotalCount $transferCandidates.Count `
                        -ProcessedBytes $processedBytes `
                        -TotalBytes $plannedBytes `
                        -ProgressBytesCompleted ($completedProgressBytes + $progressBytesForCurrentFile) `
                        -ProgressBytesTotal $progressTotalBytes `
                        -Stage "done" `
                        -CurrentFileProcessedBytes $bytes `
                        -CurrentFileTotalBytes $bytes `
                        -CurrentOperation ("TRANSFER: {0} -> {1}" -f $file.Name, $destinationRelativePath)
                }
            }
            catch {
                $status = "Failed"
                $failedCount++
                $errorMessage = $_.Exception.Message
                Write-RenderKitLog -Level Error -Message "Phase 4 transfer failed for '$sourcePath': $errorMessage" -NoConsole

                if (-not $Simulate -and -not [string]::IsNullOrWhiteSpace($stagingPath) -and (Test-Path -Path $stagingPath -PathType Leaf)) {
                    Remove-Item -Path $stagingPath -Force -ErrorAction SilentlyContinue
                }

                Update-RenderKitImportTransferProgress `
                    -StartedAt $startTime `
                    -CompletedCount ($completedCount + 1) `
                    -TotalCount $transferCandidates.Count `
                    -ProcessedBytes $processedBytes `
                    -TotalBytes $plannedBytes `
                    -ProgressBytesCompleted ($completedProgressBytes + $progressBytesForCurrentFile) `
                    -ProgressBytesTotal $progressTotalBytes `
                    -Stage "failed" `
                    -CurrentFileProcessedBytes ([int64]0) `
                    -CurrentFileTotalBytes $bytes `
                    -CurrentOperation ("FAILED: {0}" -f $file.Name)
            }
            finally {
                $completedProgressBytes += $progressBytesForCurrentFile
                $completedCount++
                $fileEnd = Get-Date
                $fileDurationSeconds = ($fileEnd - $fileStart).TotalSeconds
                if ($fileDurationSeconds -lt 0) {
                    $fileDurationSeconds = 0
                }

                $fileSpeedMBps = 0.0
                if ($fileDurationSeconds -gt 0) {
                    $fileSpeedMBps = ([double]$bytes / 1MB) / $fileDurationSeconds
                }

                $transferTransactions.Add([PSCustomObject]@{
                        Index                   = $i
                        Classification          = $file.Classification
                        MappingId               = $file.MappingId
                        TypeName                = $file.TypeName
                        SourcePath              = $sourcePath
                        DestinationRelativePath = $destinationRelativePath
                        DestinationPath         = $finalDestinationPath
                        StagingPath             = $stagingPath
                        HashAlgorithm           = $HashAlgorithm
                        SourceHash              = $sourceHash
                        StagingHash             = $stagingHash
                        Bytes                   = $bytes
                        Status                  = $status
                        StartedAt               = $fileStart
                        EndedAt                 = $fileEnd
                        DurationSeconds         = [Math]::Round($fileDurationSeconds, 3)
                        SpeedMBps               = [Math]::Round($fileSpeedMBps, 3)
                        Error                   = $errorMessage
                    })

                $logLevel = "Info"
                if ($status -eq "Failed") {
                    $logLevel = "Warning"
                }

                $destinationForLog = if ([string]::IsNullOrWhiteSpace($finalDestinationPath)) { "<none>" } else { $finalDestinationPath }
                Write-RenderKitLog -Level $logLevel -Message (
                    "Phase 4 tx {0}/{1}: {2} | '{3}' -> '{4}' | {5} | {6:N3}s" -f `
                        ($i + 1), `
                        $transferCandidates.Count, `
                        $status, `
                        $sourcePath, `
                        $destinationForLog, `
                        (ConvertTo-RenderKitHumanSize -Bytes $bytes), `
                        $fileDurationSeconds
                )
            }
        }
    }
    finally {
        Write-Progress -Activity "Phase 4 - Transaction-Safe Transfer" -Completed

        if (-not $Simulate -and -not [string]::IsNullOrWhiteSpace($tempRunRoot) -and (Test-Path -Path $tempRunRoot -PathType Container)) {
            Remove-Item -Path $tempRunRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $endTime = Get-Date
    $durationSeconds = ($endTime - $startTime).TotalSeconds
    if ($durationSeconds -lt 0) {
        $durationSeconds = 0
    }

    $averageSpeedMBps = 0.0
    if ($durationSeconds -gt 0) {
        $averageSpeedMBps = ([double]$processedBytes / 1MB) / $durationSeconds
    }

    Write-RenderKitLog -Level Info -Message (
        "Phase 4 transfer completed: planned={0}, imported={1}, simulated={2}, failed={3}, processed={4}, duration={5:N2}s, avgSpeed={6:N2} MB/s." -f `
            $transferCandidates.Count, `
            $importedCount, `
            $simulatedCount, `
            $failedCount, `
            (ConvertTo-RenderKitHumanSize -Bytes $processedBytes), `
            $durationSeconds, `
            $averageSpeedMBps
    )

    return [PSCustomObject]@{
        ProjectRoot              = $ProjectRoot
        RunId                    = $runId
        TempRunRoot              = $tempRunRoot
        Simulated                = [bool]$Simulate
        HashAlgorithm            = $HashAlgorithm
        PlannedFileCount         = $transferCandidates.Count
        NotTransferableFileCount = $notTransferable.Count
        ImportedFileCount        = $importedCount
        SimulatedFileCount       = $simulatedCount
        FailedFileCount          = $failedCount
        PlannedBytes             = $plannedBytes
        ProcessedBytes           = $processedBytes
        DurationSeconds          = [Math]::Round($durationSeconds, 3)
        AverageSpeedMBps         = [Math]::Round($averageSpeedMBps, 3)
        StartedAt                = $startTime
        EndedAt                  = $endTime
        Transactions             = $transferTransactions.ToArray()
    }
}

function Get-RenderKitImportTransferredBytesByStatus {
    [CmdletBinding()]
    [OutputType([System.Int64])]
    param(
        [object]$Transfer,
        [Parameter(Mandatory)]
        [string]$Status
    )

    if (-not $Transfer -or -not $Transfer.Transactions) {
        return [int64]0
    }

    $sum = (
        @($Transfer.Transactions | Where-Object { $_.Status -eq $Status }) |
            Measure-Object -Property Bytes -Sum
    ).Sum

    if ($null -eq $sum) {
        return [int64]0
    }

    return [int64]$sum
}

function New-RenderKitImportFinalReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [datetime]$ImportStartedAt,
        [Parameter(Mandatory)]
        [datetime]$ImportEndedAt,
        [string]$SourcePath,
        [int]$ScanFileCount,
        [int]$MatchedFileCount,
        [int]$SelectedFileCount,
        [int64]$SelectedTotalBytes,
        [object]$Classification,
        [object]$Transfer
    )

    $durationSeconds = ($ImportEndedAt - $ImportStartedAt).TotalSeconds
    if ($durationSeconds -lt 0) {
        $durationSeconds = 0
    }

    $importedFileCount = if ($Transfer) { [int]$Transfer.ImportedFileCount } else { 0 }
    $simulatedFileCount = if ($Transfer) { [int]$Transfer.SimulatedFileCount } else { 0 }
    $failedTransferFileCount = if ($Transfer) { [int]$Transfer.FailedFileCount } else { 0 }
    $processedBytes = if ($Transfer) { [int64]$Transfer.ProcessedBytes } else { [int64]0 }
    $averageSpeedMBps = if ($Transfer) { [double]$Transfer.AverageSpeedMBps } else { [double]0.0 }
    $importedBytes = Get-RenderKitImportTransferredBytesByStatus -Transfer $Transfer -Status "Imported"

    $manualAssignedCount = 0
    if ($Classification -and $Classification.Files) {
        $manualAssignedCount = @($Classification.Files | Where-Object { $_.MappingId -eq "manual" }).Count
    }

    $unassignedHandledCount = 0
    $unassignedUnhandledCount = 0
    if ($Classification) {
        $unassignedHandledCount = $manualAssignedCount + [int]$Classification.ToSortCount + [int]$Classification.SkippedCount
        $unassignedUnhandledCount = [int]$Classification.UnassignedCount
    }

    $classificationSourceCounts = [PSCustomObject]@{
        AssignedByMapping = if ($Classification) { [int]$Classification.AssignedCount - $manualAssignedCount } else { 0 }
        AssignedManual    = $manualAssignedCount
        ToSort            = if ($Classification) { [int]$Classification.ToSortCount } else { 0 }
        Skipped           = if ($Classification) { [int]$Classification.SkippedCount } else { 0 }
        UnassignedOpen    = if ($Classification) { [int]$Classification.UnassignedCount } else { 0 }
    }

    return [PSCustomObject]@{
        StartedAt                = $ImportStartedAt
        EndedAt                  = $ImportEndedAt
        DurationSeconds          = [Math]::Round($durationSeconds, 3)
        SourcePath               = $SourcePath
        SourceDrive              = [IO.Path]::GetPathRoot($SourcePath)
        ScanFileCount            = $ScanFileCount
        MatchedFileCount         = $MatchedFileCount
        SelectedFileCount        = $SelectedFileCount
        SelectedTotalBytes       = [int64]$SelectedTotalBytes
        SelectedTotalGB          = [Math]::Round(([double]$SelectedTotalBytes / 1GB), 3)
        ImportedFileCount        = $importedFileCount
        SimulatedFileCount       = $simulatedFileCount
        FailedTransferFileCount  = $failedTransferFileCount
        ImportedBytes            = $importedBytes
        ImportedGB               = [Math]::Round(([double]$importedBytes / 1GB), 3)
        ProcessedBytes           = $processedBytes
        ProcessedGB              = [Math]::Round(([double]$processedBytes / 1GB), 3)
        AverageCopySpeedMBps     = [Math]::Round($averageSpeedMBps, 3)
        UnassignedHandledCount   = $unassignedHandledCount
        UnassignedUnhandledCount = $unassignedUnhandledCount
        ClassificationBreakdown  = $classificationSourceCounts
    }
}

function Show-RenderKitImportFinalReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Report
    )

    Write-RenderKitLog -Level Info -Message "Phase 6 final report"

    $rows = @(
        [PSCustomObject]@{ Metric = "Source"; Value = $Report.SourcePath }
        [PSCustomObject]@{ Metric = "Imported Files"; Value = $Report.ImportedFileCount }
        [PSCustomObject]@{ Metric = "Imported Size"; Value = (ConvertTo-RenderKitHumanSize -Bytes ([int64]$Report.ImportedBytes)) }
        [PSCustomObject]@{ Metric = "Duration"; Value = ("{0:N2} s" -f [double]$Report.DurationSeconds) }
        [PSCustomObject]@{ Metric = "Average Copy Speed"; Value = ("{0:N2} MB/s" -f [double]$Report.AverageCopySpeedMBps) }
        [PSCustomObject]@{ Metric = "Unassigned handled"; Value = $Report.UnassignedHandledCount }
        [PSCustomObject]@{ Metric = "Unassigned unhandled"; Value = $Report.UnassignedUnhandledCount }
    )

    if ([int]$Report.SimulatedFileCount -gt 0) {
        $rows += [PSCustomObject]@{ Metric = "Simulated Files"; Value = $Report.SimulatedFileCount }
    }

    if ([int]$Report.FailedTransferFileCount -gt 0) {
        $rows += [PSCustomObject]@{ Metric = "Failed Transfers"; Value = $Report.FailedTransferFileCount }
    }

    $rows | Format-Table -AutoSize | Out-Host
}

function Write-RenderKitImportRevisionLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,
        [Parameter(Mandatory)]
        [datetime]$ImportStartedAt,
        [Parameter(Mandatory)]
        [datetime]$ImportEndedAt,
        [string]$SourcePath,
        [int]$ScanFileCount,
        [int]$MatchedFileCount,
        [int]$SelectedFileCount,
        [int64]$SelectedTotalBytes,
        [object]$Filters,
        [object]$Classification,
        [object]$Transfer,
        [object]$FinalReport
    )

    $renderKitRoot = Join-Path $ProjectRoot ".renderkit"
    if (-not (Test-Path -Path $renderKitRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $renderKitRoot -Force | Out-Null
    }

    $projectMetadata = $null
    try {
        $projectMetadata = Read-RenderKitImportProjectMetadata -ProjectRoot $ProjectRoot
    }
    catch {
        Write-RenderKitLog -Level Warning -Message "Phase 5: project metadata could not be read for revision log: $($_.Exception.Message)"
    }

    $templateName = $null
    $templateVersion = $null
    $templateSource = $null
    $projectSchemaVersion = $null

    if ($Classification) {
        $templateName = $Classification.TemplateName
        $templateVersion = $Classification.TemplateVersion
        $templateSource = $Classification.TemplateSource
        $projectSchemaVersion = $Classification.ProjectSchemaVersion
    }

    if (-not $templateName -and $projectMetadata -and $projectMetadata.template) {
        $templateName = [string]$projectMetadata.template.name
    }
    if (-not $templateSource -and $projectMetadata -and $projectMetadata.template) {
        $templateSource = [string]$projectMetadata.template.source
    }
    if (-not $projectSchemaVersion -and $projectMetadata) {
        $projectSchemaVersion = [string]$projectMetadata.schemaVersion
    }

    $importRunId = $null
    if ($Transfer -and -not [string]::IsNullOrWhiteSpace($Transfer.RunId)) {
        $importRunId = [string]$Transfer.RunId
    }
    else {
        $importRunId = "import-{0}-{1}" -f (Get-Date).ToString("yyyyMMdd-HHmmss"), ([guid]::NewGuid().ToString("N").Substring(0, 6))
    }

    $importedBytes = Get-RenderKitImportTransferredBytesByStatus -Transfer $Transfer -Status "Imported"
    $simulatedBytes = Get-RenderKitImportTransferredBytesByStatus -Transfer $Transfer -Status "Simulated"
    $failedBytes = Get-RenderKitImportTransferredBytesByStatus -Transfer $Transfer -Status "Failed"
    $sourceDrive = [IO.Path]::GetPathRoot($SourcePath)

    $logPath = Join-Path $renderKitRoot ("{0}.log" -f $importRunId)
    $durationSeconds = if ($FinalReport) {
        [double]$FinalReport.DurationSeconds
    }
    else {
        [Math]::Round((($ImportEndedAt - $ImportStartedAt).TotalSeconds), 3)
    }

    $filtersFolder = "-"
    $filtersWildcard = "-"
    $filtersFrom = "-"
    $filtersTo = "-"
    if ($Filters) {
        if ($Filters.PSObject.Properties.Name -contains "FolderFilter" -and $Filters.FolderFilter) {
            $filtersFolder = (@($Filters.FolderFilter) -join ", ")
            if ([string]::IsNullOrWhiteSpace($filtersFolder)) { $filtersFolder = "-" }
        }
        if ($Filters.PSObject.Properties.Name -contains "Wildcard" -and $Filters.Wildcard) {
            $filtersWildcard = (@($Filters.Wildcard) -join ", ")
            if ([string]::IsNullOrWhiteSpace($filtersWildcard)) { $filtersWildcard = "-" }
        }
        if ($Filters.PSObject.Properties.Name -contains "FromDate" -and $Filters.FromDate) {
            $filtersFrom = ([datetime]$Filters.FromDate).ToString("yyyy-MM-dd HH:mm:ss")
        }
        if ($Filters.PSObject.Properties.Name -contains "ToDate" -and $Filters.ToDate) {
            $filtersTo = ([datetime]$Filters.ToDate).ToString("yyyy-MM-dd HH:mm:ss")
        }
    }

    $metadataPath = if ($projectMetadata) { Join-Path $ProjectRoot ".renderkit\project.json" } else { "-" }
    $classifiedCount = if ($Classification) { [int]$Classification.FileCount } else { 0 }
    $assignedCount = if ($Classification) { [int]$Classification.AssignedCount } else { 0 }
    $toSortCount = if ($Classification) { [int]$Classification.ToSortCount } else { 0 }
    $skippedCount = if ($Classification) { [int]$Classification.SkippedCount } else { 0 }
    $unassignedOpen = if ($Classification) { [int]$Classification.UnassignedCount } else { 0 }
    $unassignedHandled = if ($FinalReport) { [int]$FinalReport.UnassignedHandledCount } else { 0 }
    $unassignedUnhandled = if ($FinalReport) { [int]$FinalReport.UnassignedUnhandledCount } else { 0 }
    $transferPlanned = if ($Transfer) { [int]$Transfer.PlannedFileCount } else { 0 }
    $transferImported = if ($Transfer) { [int]$Transfer.ImportedFileCount } else { 0 }
    $transferSimulated = if ($Transfer) { [int]$Transfer.SimulatedFileCount } else { 0 }
    $transferFailed = if ($Transfer) { [int]$Transfer.FailedFileCount } else { 0 }
    $processedBytes = if ($Transfer) { [int64]$Transfer.ProcessedBytes } else { [int64]0 }
    $hashAlgorithm = if ($Transfer -and $Transfer.HashAlgorithm) { [string]$Transfer.HashAlgorithm } else { "-" }
    $averageSpeedMBps = if ($Transfer) { [double]$Transfer.AverageSpeedMBps } else { 0 }
    $transferDurationSeconds = if ($Transfer) { [double]$Transfer.DurationSeconds } else { 0 }
    $transferSimulatedFlag = if ($Transfer) { [bool]$Transfer.Simulated } else { $false }
    $transactions = if ($Transfer -and $Transfer.Transactions) { @($Transfer.Transactions) } else { @() }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("RenderKit Import Revision Log")
    $lines.Add("RunId: $importRunId")
    $lines.Add(("GeneratedAt: {0}" -f (Get-Date).ToString("o")))
    $lines.Add("")

    $lines.Add("[Context]")
    $lines.Add(("Tool: RenderKit {0}" -f $script:RenderKitModuleVersion))
    $lines.Add(("User: {0}" -f $env:USERNAME))
    $lines.Add(("Machine: {0}" -f $env:COMPUTERNAME))
    $lines.Add(("ProjectRoot: {0}" -f $ProjectRoot))
    $lines.Add(("ProjectMetadata: {0}" -f $metadataPath))
    $lines.Add(("ProjectSchemaVersion: {0}" -f $(if ($projectSchemaVersion) { $projectSchemaVersion } else { "-" })))
    $lines.Add(("Template: {0}" -f $(if ($templateName) { $templateName } else { "-" })))
    $lines.Add(("TemplateSource: {0}" -f $(if ($templateSource) { $templateSource } else { "-" })))
    $lines.Add(("TemplateVersion: {0}" -f $(if ($templateVersion) { $templateVersion } else { "-" })))
    $lines.Add(("SourcePath: {0}" -f $SourcePath))
    $lines.Add(("SourceDrive: {0}" -f $(if ($sourceDrive) { $sourceDrive } else { "-" })))
    $lines.Add(("StartedAt: {0}" -f $ImportStartedAt.ToString("o")))
    $lines.Add(("EndedAt: {0}" -f $ImportEndedAt.ToString("o")))
    $lines.Add(("DurationSeconds: {0:N3}" -f [double]$durationSeconds))
    $lines.Add("")

    $lines.Add("[Filters]")
    $lines.Add(("Folders: {0}" -f $filtersFolder))
    $lines.Add(("Wildcard: {0}" -f $filtersWildcard))
    $lines.Add(("FromDate: {0}" -f $filtersFrom))
    $lines.Add(("ToDate: {0}" -f $filtersTo))
    $lines.Add("")

    $lines.Add("[Counts]")
    $lines.Add(("Scanned: {0}" -f $ScanFileCount))
    $lines.Add(("Matched: {0}" -f $MatchedFileCount))
    $lines.Add(("Selected: {0}" -f $SelectedFileCount))
    $lines.Add(("Classified: {0}" -f $classifiedCount))
    $lines.Add(("Assigned: {0}" -f $assignedCount))
    $lines.Add(("ToSort: {0}" -f $toSortCount))
    $lines.Add(("Skipped: {0}" -f $skippedCount))
    $lines.Add(("UnassignedOpen: {0}" -f $unassignedOpen))
    $lines.Add(("UnassignedHandled: {0}" -f $unassignedHandled))
    $lines.Add(("UnassignedUnhandled: {0}" -f $unassignedUnhandled))
    $lines.Add(("TransferPlanned: {0}" -f $transferPlanned))
    $lines.Add(("TransferImported: {0}" -f $transferImported))
    $lines.Add(("TransferSimulated: {0}" -f $transferSimulated))
    $lines.Add(("TransferFailed: {0}" -f $transferFailed))
    $lines.Add("")

    $lines.Add("[Bytes]")
    $lines.Add(("Selected: {0} ({1:N3} GB)" -f (ConvertTo-RenderKitHumanSize -Bytes ([int64]$SelectedTotalBytes)), ([double]$SelectedTotalBytes / 1GB)))
    $lines.Add(("Imported: {0} ({1:N3} GB)" -f (ConvertTo-RenderKitHumanSize -Bytes ([int64]$importedBytes)), ([double]$importedBytes / 1GB)))
    $lines.Add(("Simulated: {0} ({1:N3} GB)" -f (ConvertTo-RenderKitHumanSize -Bytes ([int64]$simulatedBytes)), ([double]$simulatedBytes / 1GB)))
    $lines.Add(("Failed: {0} ({1:N3} GB)" -f (ConvertTo-RenderKitHumanSize -Bytes ([int64]$failedBytes)), ([double]$failedBytes / 1GB)))
    $lines.Add(("Processed: {0} ({1:N3} GB)" -f (ConvertTo-RenderKitHumanSize -Bytes ([int64]$processedBytes)), ([double]$processedBytes / 1GB)))
    $lines.Add("")

    $lines.Add("[Transfer]")
    $lines.Add(("HashAlgorithm: {0}" -f $hashAlgorithm))
    $lines.Add(("TransferDurationSeconds: {0:N3}" -f [double]$transferDurationSeconds))
    $lines.Add(("AverageSpeedMBps: {0:N3}" -f [double]$averageSpeedMBps))
    $lines.Add(("SimulationMode: {0}" -f $(if ($transferSimulatedFlag) { "Yes" } else { "No" })))
    $lines.Add("")

    $lines.Add("[Transactions]")
    if ($transactions.Count -eq 0) {
        $lines.Add("No transfer transactions recorded.")
    }
    else {
        $lines.Add("Status | Size | Mapping | Destination | File | Error")
        foreach ($tx in $transactions) {
            $txStatus = if ($tx.Status) { [string]$tx.Status } else { "-" }
            $txSize = ConvertTo-RenderKitHumanSize -Bytes ([int64]$tx.Bytes)
            $txMapping = if ($tx.MappingId) { [string]$tx.MappingId } else { "-" }
            $txDestination = if ($tx.DestinationRelativePath) { [string]$tx.DestinationRelativePath } else { "-" }
            $txFile = if ($tx.SourcePath) { [IO.Path]::GetFileName([string]$tx.SourcePath) } else { "-" }
            $txError = if ($tx.Error) { [string]$tx.Error } else { "-" }

            $lines.Add(("{0} | {1} | {2} | {3} | {4} | {5}" -f $txStatus, $txSize, $txMapping, $txDestination, $txFile, $txError))
        }
    }

    Set-Content -Path $logPath -Value $lines -Encoding UTF8

    Write-RenderKitLog -Level Info -Message "Phase 5 revision log written: '$logPath'."
    return $logPath
}
