function New-RenderKitImportCriterion {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        "PSUseShouldProcessForStateChangingFunctions",
        "",
        Justification = "Function only creates an in-memory object and does not modify state"
    )]
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

    return Read-RenderKitImportBooleanMenu `
        -Title "Confirmation" `
        -Prompt $Prompt `
        -Default $Default `
        -Breadcrumb @("Import Media", "Prompt")
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

    return Read-RenderKitImportSelectionReviewActionMenu
}

function Read-RenderKitImportTransferModeInteractive {
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    return Read-RenderKitImportTransferModeMenu
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

    return Select-RenderKitImportProjectRootMenu
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

    return Select-RenderKitImportSourcePathMenu `
        -IncludeFixed:$IncludeFixed `
        -IncludeUnsupportedFileSystem:$IncludeUnsupportedFileSystem
}

function Read-RenderKitImportUnassignedHandlingInteractive {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [ValidateSet("Prompt", "ToSort", "Skip")]
        [string]$Default = "Prompt"
    )

    $selection = Select-RenderKitImportUnassignedHandlingMenu `
        -Default $Default `
        -AllowBack

    if ([string]::IsNullOrWhiteSpace($selection)) {
        return $Default
    }

    return $selection
}

function Start-RenderKitImportInteractiveSetup {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        "PSUseShouldProcessForStateChangingFunctions",
        "",
        Justification = "Function only creates an in-memory object and does not modify state"
    )]
    [CmdletBinding()]
    param(
        [string]$ProjectRoot,
        [switch]$IncludeFixed,
        [switch]$IncludeUnsupportedFileSystem,
        [ValidateSet("Prompt", "ToSort", "Skip")]
        [string]$UnassignedHandling = "Prompt"
    )

    $setupParameters = @{
        ProjectRoot = $ProjectRoot
        UnassignedHandling = $UnassignedHandling
    }

    if ($PSBoundParameters.ContainsKey('IncludeFixed')) {
        $setupParameters.IncludeFixed = $IncludeFixed
    }

    if ($PSBoundParameters.ContainsKey('IncludeUnsupportedFileSystem')) {
        $setupParameters.IncludeUnsupportedFileSystem = $IncludeUnsupportedFileSystem
    }

    return Start-RenderKitImportInteractiveSetupMenu @setupParameters
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

    return Read-RenderKitImportAdditionalCriterionMenu
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

    return Select-RenderKitImportFileSubsetMenu `
        -Files $Files `
        -AutoSelectAll:$AutoSelectAll
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

    return Confirm-RenderKitImportSelectionMenu `
        -FileCount $FileCount `
        -TotalBytes $TotalBytes `
        -AutoConfirm:$AutoConfirm
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
     Justification = 'Data counts a a singular noun')]
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        "PSUseShouldProcessForStateChangingFunctions",
        "",
        Justification = "internal function. The public function already has a DryRun feature")]
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

    return Read-RenderKitImportUnassignedActionMenu `
        -ExtensionLabel $ExtensionLabel `
        -FileCount $FileCount `
        -DestinationFolders $DestinationFolders `
        -HandlingMode $HandlingMode
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        "PSUseShouldProcessForStateChangingFunctions",
        "",
        Justification = "internal function. The public function already has a DryRun feature")]
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
        [ValidateRange(65536, 67108864)]
        [int]$BufferSizeBytes = 4MB,
        [scriptblock]$ProgressCallback
    )

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
    [OutputType([System.Object])]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,
        [Parameter(Mandatory)]
        [string]$DestinationPath,
        [ValidateSet("SHA256", "SHA1", "MD5")]
        [string]$HashAlgorithm = "SHA256",
        [ValidateRange(65536, 67108864)]
        [int]$BufferSizeBytes = 4MB,
        [scriptblock]$ProgressCallback
    )

    $buffer = New-Object byte[] $bufferSizeBytes
    $sourceItem = Get-Item -LiteralPath $SourcePath -ErrorAction Stop
    $sourceStream = $null
    $destinationStream = $null
    $sourceHashAlgorithm = $null
    $sourceHashStream = $null
    $copiedBytes = [int64]0
    $totalBytes = [int64]$sourceItem.Length
    $lastProgressAt = [datetime]::MinValue
    $copyStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $sourceHash = $null

    try {
        switch ($HashAlgorithm) {
            "SHA256" { $sourceHashAlgorithm = [System.Security.Cryptography.SHA256]::Create() }
            "SHA1" { $sourceHashAlgorithm = [System.Security.Cryptography.SHA1]::Create() }
            "MD5" { $sourceHashAlgorithm = [System.Security.Cryptography.MD5]::Create() }
        }

        $sourceHashStream = New-Object System.Security.Cryptography.CryptoStream(
            [System.IO.Stream]::Null,
            $sourceHashAlgorithm,
            [System.Security.Cryptography.CryptoStreamMode]::Write
        )

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
            $sourceHashStream.Write($buffer, 0, $readCount)
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

        $sourceHashStream.FlushFinalBlock()
        $destinationStream.Flush()
        $sourceHash = ([System.BitConverter]::ToString($sourceHashAlgorithm.Hash)).Replace("-", "")
        $copyStopwatch.Stop()
    }
    catch {
        $copyStopwatch.Stop()
        if (Test-Path -LiteralPath $DestinationPath -PathType Leaf) {
            Remove-Item -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue
        }

        throw
    }
    finally {
        if ($sourceHashStream) {
            $sourceHashStream.Dispose()
        }

        if ($sourceHashAlgorithm) {
            $sourceHashAlgorithm.Dispose()
        }

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

    return [PSCustomObject]@{
        BytesCopied    = $copiedBytes
        SourceHash     = $sourceHash
        HashAlgorithm  = $HashAlgorithm
        DurationSeconds = [double]$copyStopwatch.Elapsed.TotalSeconds
        CopyEngine     = "ManagedHashingStream"
    }
}

function Copy-RenderKitImportFileFastToPath {
    [CmdletBinding()]
    [OutputType([System.Object])]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,
        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    $sourceItem = Get-Item -LiteralPath $SourcePath -ErrorAction Stop
    $copyStopwatch = [Diagnostics.Stopwatch]::StartNew()

    try {
        [IO.File]::Copy($sourceItem.FullName, $DestinationPath, $false)
        $destinationItem = Get-Item -LiteralPath $DestinationPath -ErrorAction Stop
        if ([int64]$destinationItem.Length -ne [int64]$sourceItem.Length) {
            throw "Fast copy length mismatch for '$SourcePath'. Source '$($sourceItem.Length)', staging '$($destinationItem.Length)'."
        }
    }
    catch {
        if (Test-Path -LiteralPath $DestinationPath -PathType Leaf) {
            Remove-Item -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
    finally {
        $copyStopwatch.Stop()
    }

    return [PSCustomObject]@{
        BytesCopied     = [int64]$sourceItem.Length
        SourceHash      = $null
        HashAlgorithm   = $null
        DurationSeconds = [double]$copyStopwatch.Elapsed.TotalSeconds
        CopyEngine      = "NativeFileCopy"
    }
}

function Update-RenderKitImportTransferProgress {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        "PSUseShouldProcessForStateChangingFunctions",
        "",
        Justification = "internal function. The public function already has a DryRun feature")]
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

function Get-RenderKitImportTransferSchedulerConfiguration {
    [CmdletBinding()]
    param(
        [ValidateSet("Maximum", "Balanced", "Conservative")]
        [string]$TransferProfile = "Maximum",
        [ValidateRange(1, 1024)]
        [int]$SmallFileThresholdMB = 64,
        [ValidateRange(0, 32)]
        [int]$SmallFileConcurrency = 0,
        [ValidateRange(0, 16)]
        [int]$LargeFileConcurrency = 0,
        [ValidateRange(0, 16)]
        [int]$VerifyConcurrency = 0,
        [ValidateRange(1, 65536)]
        [int]$MaxInFlightMB = 512,
        [ValidateRange(1, 64)]
        [int]$TransferBufferSizeMB = 8
    )

    $processorCount = [Math]::Max(1, [Environment]::ProcessorCount)

    $effectiveSmallFileConcurrency = $SmallFileConcurrency
    if ($effectiveSmallFileConcurrency -eq 0) {
        $effectiveSmallFileConcurrency = switch ($TransferProfile) {
            "Maximum" { [Math]::Min(4, $processorCount) }
            "Balanced" { [Math]::Min(2, $processorCount) }
            default { 1 }
        }
    }

    $effectiveLargeFileConcurrency = $LargeFileConcurrency
    if ($effectiveLargeFileConcurrency -eq 0) {
        # Until storage-topology detection is added, one large stream is the
        # safest maximum-throughput default for same-device transfers.
        $effectiveLargeFileConcurrency = 1
    }

    $effectiveVerifyConcurrency = $VerifyConcurrency
    if ($effectiveVerifyConcurrency -eq 0) {
        $effectiveVerifyConcurrency = switch ($TransferProfile) {
            "Maximum" { [Math]::Min(4, $processorCount) }
            "Balanced" { [Math]::Min(2, $processorCount) }
            default { 1 }
        }
    }

    return [PSCustomObject]@{
        TransferProfile              = $TransferProfile
        SmallFileThresholdMB         = $SmallFileThresholdMB
        SmallFileThresholdBytes      = [int64]$SmallFileThresholdMB * 1MB
        RequestedSmallFileConcurrency = $SmallFileConcurrency
        SmallFileConcurrency         = [int]$effectiveSmallFileConcurrency
        RequestedLargeFileConcurrency = $LargeFileConcurrency
        LargeFileConcurrency         = [int]$effectiveLargeFileConcurrency
        RequestedVerifyConcurrency   = $VerifyConcurrency
        VerifyConcurrency            = [int]$effectiveVerifyConcurrency
        AdaptiveConcurrencyEnabled   = [bool](
            $TransferProfile -ne "Conservative" -and
            (
                $effectiveSmallFileConcurrency -gt 1 -or
                $effectiveLargeFileConcurrency -gt 1
            )
        )
        MaxInFlightMB                = $MaxInFlightMB
        MaxInFlightBytes             = [int64]$MaxInFlightMB * 1MB
        TransferBufferSizeMB         = $TransferBufferSizeMB
        TransferBufferSizeBytes      = [int]$TransferBufferSizeMB * 1MB
    }
}

function Get-RenderKitImportTransferAdmissionByte {
    [CmdletBinding()]
    [OutputType([System.Int64])]
    param(
        [Parameter(Mandatory)]
        [object]$WorkItem,
        [ValidateRange(65536, 67108864)]
        [int]$BufferSizeBytes = 8MB
    )

    if ([string]$WorkItem.TransferMethod -eq "SameVolumeMove") {
        return [int64]0
    }

    # The scheduler budget protects resident pipeline memory and I/O queue
    # pressure. Reserving the complete logical file size made every file above
    # MaxInFlightMB monopolize the pipeline until verification had finished.
    $estimatedWorkerBytes = [int64]$BufferSizeBytes * 3
    return [Math]::Min([int64]$WorkItem.Bytes, $estimatedWorkerBytes)
}

function Test-RenderKitImportSameVolume {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,
        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    if ($env:OS -ne "Windows_NT") {
        return $false
    }

    try {
        $sourceRoot = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($SourcePath))
        $destinationRoot = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($DestinationPath))
        return (
            -not [string]::IsNullOrWhiteSpace($sourceRoot) -and
            -not [string]::IsNullOrWhiteSpace($destinationRoot) -and
            [string]::Equals(
                $sourceRoot.TrimEnd("\", "/"),
                $destinationRoot.TrimEnd("\", "/"),
                [StringComparison]::OrdinalIgnoreCase
            )
        )
    }
    catch {
        return $false
    }
}

function Invoke-RenderKitImportCopyWorkItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$WorkItem,
        [ValidateSet("SHA256", "SHA1", "MD5")]
        [string]$HashAlgorithm = "SHA256",
        [ValidateRange(65536, 67108864)]
        [int]$BufferSizeBytes = 8MB
    )

    $startedAt = Get-Date
    $sourceHash = $null
    $errorMessage = $null
    $copiedBytes = [int64]0
    $durationSeconds = [double]0
    $status = "Copied"
    $sourceMovedToStaging = $false
    $rollbackStatus = "NotRequired"
    $rollbackError = $null
    $copyEngine = $null
    $verificationMode = if ($WorkItem.PSObject.Properties["VerificationMode"]) {
        [string]$WorkItem.VerificationMode
    }
    else {
        "Full"
    }

    try {
        if (-not [string]::IsNullOrWhiteSpace([string]$WorkItem.PreparationError)) {
            throw [string]$WorkItem.PreparationError
        }

        if ([string]$WorkItem.TransferMethod -eq "SameVolumeMove") {
            $moveStopwatch = [Diagnostics.Stopwatch]::StartNew()
            try {
                Move-Item `
                    -LiteralPath $WorkItem.SourcePath `
                    -Destination $WorkItem.StagingPath `
                    -ErrorAction Stop
                $sourceMovedToStaging = $true
                $copyEngine = "SameVolumeRename"
            }
            finally {
                $moveStopwatch.Stop()
                $durationSeconds = [double]$moveStopwatch.Elapsed.TotalSeconds
            }
        }
        elseif ($verificationMode -eq "Fast") {
            $copyResult = Copy-RenderKitImportFileFastToPath `
                -SourcePath $WorkItem.SourcePath `
                -DestinationPath $WorkItem.StagingPath

            $copiedBytes = [int64]$copyResult.BytesCopied
            $durationSeconds = [double]$copyResult.DurationSeconds
            $copyEngine = [string]$copyResult.CopyEngine
        }
        else {
            $copyResult = Copy-RenderKitImportFileToPath `
                -SourcePath $WorkItem.SourcePath `
                -DestinationPath $WorkItem.StagingPath `
                -HashAlgorithm $HashAlgorithm `
                -BufferSizeBytes $BufferSizeBytes

            $sourceHash = [string]$copyResult.SourceHash
            $copiedBytes = [int64]$copyResult.BytesCopied
            $durationSeconds = [double]$copyResult.DurationSeconds
            $copyEngine = [string]$copyResult.CopyEngine
        }
    }
    catch {
        $status = "Failed"
        $errorMessage = $_.Exception.Message

        if ([string]$WorkItem.TransferMethod -eq "SameVolumeMove") {
            if (
                (Test-Path -LiteralPath $WorkItem.StagingPath -PathType Leaf) -and
                -not (Test-Path -LiteralPath $WorkItem.SourcePath -PathType Leaf)
            ) {
                try {
                    Move-Item `
                        -LiteralPath $WorkItem.StagingPath `
                        -Destination $WorkItem.SourcePath `
                        -ErrorAction Stop
                    $rollbackStatus = "Succeeded"
                }
                catch {
                    $rollbackStatus = "Failed"
                    $rollbackError = $_.Exception.Message
                }
            }
        }
        elseif (
            -not [string]::IsNullOrWhiteSpace([string]$WorkItem.StagingPath) -and
            (Test-Path -LiteralPath $WorkItem.StagingPath -PathType Leaf)
        ) {
            Remove-Item -LiteralPath $WorkItem.StagingPath -Force -ErrorAction SilentlyContinue
        }
    }

    $endedAt = Get-Date
    if ($durationSeconds -le 0) {
        $durationSeconds = [Math]::Max([double]0, ($endedAt - $startedAt).TotalSeconds)
    }

    return [PSCustomObject]@{
        WorkItem             = $WorkItem
        Status               = $status
        SourceHash           = $sourceHash
        CopiedBytes          = $copiedBytes
        CopyDurationSeconds  = $durationSeconds
        StartedAt            = $startedAt
        CopyEndedAt          = $endedAt
        SourceMovedToStaging = $sourceMovedToStaging
        CopyEngine           = $copyEngine
        RollbackStatus       = $rollbackStatus
        RollbackError        = $rollbackError
        Error                = $errorMessage
    }
}

function Invoke-RenderKitImportVerifyWorkItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$CopyResult,
        [ValidateSet("SHA256", "SHA1", "MD5")]
        [string]$HashAlgorithm = "SHA256",
        [ValidateRange(65536, 67108864)]
        [int]$BufferSizeBytes = 8MB
    )

    $workItem = $CopyResult.WorkItem
    $file = $workItem.File
    $stagingHash = $null
    $verifiedBytes = [int64]0
    $verificationDurationSeconds = [double]0
    $status = [string]$CopyResult.Status
    $errorMessage = [string]$CopyResult.Error
    $rollbackStatus = [string]$CopyResult.RollbackStatus
    $rollbackError = [string]$CopyResult.RollbackError
    $endedAt = Get-Date
    $verificationMode = if ($workItem.PSObject.Properties["VerificationMode"]) {
        [string]$workItem.VerificationMode
    }
    else {
        "Full"
    }

    if ($status -eq "Copied") {
        try {
            if ([string]$workItem.TransferMethod -eq "SameVolumeMove") {
                $commitStopwatch = [Diagnostics.Stopwatch]::StartNew()
                try {
                    Move-Item `
                        -LiteralPath $workItem.StagingPath `
                        -Destination $workItem.FinalDestinationPath `
                        -ErrorAction Stop
                }
                finally {
                    $commitStopwatch.Stop()
                    $verificationDurationSeconds = [double]$commitStopwatch.Elapsed.TotalSeconds
                }
            }
            elseif ($verificationMode -eq "Fast") {
                $commitStopwatch = [Diagnostics.Stopwatch]::StartNew()
                try {
                    $stagingItem = Get-Item -LiteralPath $workItem.StagingPath -ErrorAction Stop
                    if ([int64]$stagingItem.Length -ne [int64]$workItem.Bytes) {
                        throw "Fast verification length mismatch for '$($workItem.SourcePath)'. Expected '$($workItem.Bytes)', staging '$($stagingItem.Length)'."
                    }

                    Move-Item `
                        -LiteralPath $workItem.StagingPath `
                        -Destination $workItem.FinalDestinationPath `
                        -ErrorAction Stop
                }
                finally {
                    $commitStopwatch.Stop()
                    $verificationDurationSeconds = [double]$commitStopwatch.Elapsed.TotalSeconds
                }
            }
            else {
                $verificationStopwatch = [Diagnostics.Stopwatch]::StartNew()
                try {
                    $stagingHash = Get-RenderKitImportFileHashValue `
                        -Path $workItem.StagingPath `
                        -Algorithm $HashAlgorithm `
                        -BufferSizeBytes $BufferSizeBytes
                    $verifiedBytes = [int64]$workItem.Bytes
                }
                finally {
                    $verificationStopwatch.Stop()
                    $verificationDurationSeconds = [double]$verificationStopwatch.Elapsed.TotalSeconds
                }

                if ([string]$CopyResult.SourceHash -ne $stagingHash) {
                    throw "Hash mismatch for '$($workItem.SourcePath)'. Source '$($CopyResult.SourceHash)', staging '$stagingHash'."
                }

                Move-Item `
                    -LiteralPath $workItem.StagingPath `
                    -Destination $workItem.FinalDestinationPath `
                    -ErrorAction Stop
            }

            $status = "Imported"
        }
        catch {
            $status = "Failed"
            $errorMessage = $_.Exception.Message

            if ([string]$workItem.TransferMethod -eq "SameVolumeMove") {
                if (
                    (Test-Path -LiteralPath $workItem.StagingPath -PathType Leaf) -and
                    -not (Test-Path -LiteralPath $workItem.SourcePath -PathType Leaf)
                ) {
                    try {
                        Move-Item `
                            -LiteralPath $workItem.StagingPath `
                            -Destination $workItem.SourcePath `
                            -ErrorAction Stop
                        $rollbackStatus = "Succeeded"
                    }
                    catch {
                        $rollbackStatus = "Failed"
                        $rollbackError = $_.Exception.Message
                    }
                }
            }
            elseif (Test-Path -LiteralPath $workItem.StagingPath -PathType Leaf) {
                Remove-Item -LiteralPath $workItem.StagingPath -Force -ErrorAction SilentlyContinue
            }
        }

        $endedAt = Get-Date
    }

    $durationSeconds = [Math]::Max(
        [double]0,
        ($endedAt - [datetime]$CopyResult.StartedAt).TotalSeconds
    )
    $copySpeedMBps = if ([double]$CopyResult.CopyDurationSeconds -gt 0) {
        ([double]$CopyResult.CopiedBytes / 1MB) / [double]$CopyResult.CopyDurationSeconds
    }
    else { [double]0 }
    $verificationSpeedMBps = if ($verificationDurationSeconds -gt 0) {
        ([double]$verifiedBytes / 1MB) / $verificationDurationSeconds
    }
    else { [double]0 }
    $speedMBps = if ($durationSeconds -gt 0) {
        ([double]$workItem.Bytes / 1MB) / $durationSeconds
    }
    else { [double]0 }

    return [PSCustomObject]@{
        Index                       = [int]$workItem.Index
        Classification              = $file.Classification
        MappingId                   = $file.MappingId
        TypeName                    = $file.TypeName
        SourcePath                  = [string]$workItem.SourcePath
        DestinationRelativePath     = [string]$workItem.DestinationRelativePath
        DestinationPath             = [string]$workItem.FinalDestinationPath
        StagingPath                 = [string]$workItem.StagingPath
        TransferMethod              = [string]$workItem.TransferMethod
        VerificationMode            = if ([string]$workItem.TransferMethod -eq "SameVolumeMove") { "RenameIdentity" } else { $verificationMode }
        HashAlgorithm               = if (
            [string]$workItem.TransferMethod -eq "SameVolumeMove" -or
            $verificationMode -eq "Fast"
        ) { $null } else { $HashAlgorithm }
        SourceHash                  = $CopyResult.SourceHash
        StagingHash                 = $stagingHash
        Bytes                       = [int64]$workItem.Bytes
        CopiedBytes                 = [int64]$CopyResult.CopiedBytes
        VerifiedBytes               = $verifiedBytes
        Status                      = $status
        StartedAt                   = [datetime]$CopyResult.StartedAt
        EndedAt                     = $endedAt
        CopyDurationSeconds         = [Math]::Round([double]$CopyResult.CopyDurationSeconds, 3)
        VerificationDurationSeconds = [Math]::Round($verificationDurationSeconds, 3)
        DurationSeconds             = [Math]::Round($durationSeconds, 3)
        CopySpeedMBps               = [Math]::Round($copySpeedMBps, 3)
        VerificationSpeedMBps       = [Math]::Round($verificationSpeedMBps, 3)
        SpeedMBps                   = [Math]::Round($speedMBps, 3)
        SourceMovedToStaging        = [bool]$CopyResult.SourceMovedToStaging
        CopyEngine                  = [string]$CopyResult.CopyEngine
        RollbackStatus              = $rollbackStatus
        RollbackError               = $rollbackError
        Error                       = $errorMessage
        SchedulerClass              = [string]$workItem.SchedulerClass
    }
}

function Invoke-RenderKitImportTransferWorkItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$WorkItem,
        [ValidateSet("SHA256", "SHA1", "MD5")]
        [string]$HashAlgorithm = "SHA256",
        [ValidateRange(65536, 67108864)]
        [int]$BufferSizeBytes = 8MB
    )

    $copyResult = Invoke-RenderKitImportCopyWorkItem `
        -WorkItem $WorkItem `
        -HashAlgorithm $HashAlgorithm `
        -BufferSizeBytes $BufferSizeBytes

    return Invoke-RenderKitImportVerifyWorkItem `
        -CopyResult $copyResult `
        -HashAlgorithm $HashAlgorithm `
        -BufferSizeBytes $BufferSizeBytes
}

function Invoke-RenderKitImportParallelTransferWorkItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$WorkItems,
        [ValidateRange(1, 32)]
        [int]$Concurrency,
        [ValidateRange(1, 16)]
        [int]$VerifyConcurrency = 1,
        [Parameter(Mandatory)]
        [int64]$MaxInFlightBytes,
        [ValidateSet("SHA256", "SHA1", "MD5")]
        [string]$HashAlgorithm = "SHA256",
        [ValidateRange(65536, 67108864)]
        [int]$BufferSizeBytes = 8MB,
        [Parameter(Mandatory)]
        [datetime]$StartedAt,
        [Parameter(Mandatory)]
        [int]$TotalFileCount,
        [Parameter(Mandatory)]
        [int64]$TotalProgressBytes,
        [int]$CompletedFileCount,
        [int64]$CompletedProgressBytes,
        [int64]$ProcessedBytes,
        [int64]$PlannedBytes,
        [string]$SchedulerClass = "small",
        [ValidateSet("Maximum", "Balanced", "Conservative")]
        [string]$TransferProfile = "Maximum",
        [bool]$AdaptiveConcurrencyEnabled = $true
    )

    if (-not $WorkItems -or $WorkItems.Count -eq 0) {
        return [PSCustomObject]@{
            Results                    = @()
            PeakConcurrency            = 0
            PeakCopyConcurrency        = 0
            PeakVerifyConcurrency      = 0
            PeakInFlightBytes          = [int64]0
            ConcurrencyAdjustments     = 0
        }
    }

    if ($WorkItems.Count -eq 1) {
        $result = Invoke-RenderKitImportTransferWorkItem `
            -WorkItem $WorkItems[0] `
            -HashAlgorithm $HashAlgorithm `
            -BufferSizeBytes $BufferSizeBytes
        return [PSCustomObject]@{
            Results                    = @($result)
            PeakConcurrency            = 1
            PeakCopyConcurrency        = 1
            PeakVerifyConcurrency      = 1
            PeakInFlightBytes          = Get-RenderKitImportTransferAdmissionByte `
                -WorkItem $WorkItems[0] `
                -BufferSizeBytes $BufferSizeBytes
            ConcurrencyAdjustments     = 0
        }
    }

    $functionDefinitions = @{}
    foreach ($functionName in @(
            "Get-RenderKitImportFileHashValue",
            "Copy-RenderKitImportFileToPath",
            "Copy-RenderKitImportFileFastToPath",
            "Invoke-RenderKitImportCopyWorkItem",
            "Invoke-RenderKitImportVerifyWorkItem"
        )) {
        $functionDefinitions[$functionName] = (
            Get-Command -Name $functionName -CommandType Function -ErrorAction Stop
        ).Definition
    }

    $logStub = @'
param(
    [string]$Level,
    [string]$Message,
    [switch]$NoConsole
)
'@
    $copySessionState = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $verifySessionState = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach ($functionName in $functionDefinitions.Keys) {
        $copySessionState.Commands.Add((
                New-Object Management.Automation.Runspaces.SessionStateFunctionEntry(
                    $functionName,
                    $functionDefinitions[$functionName]
                )
            ))
        $verifySessionState.Commands.Add((
                New-Object Management.Automation.Runspaces.SessionStateFunctionEntry(
                    $functionName,
                    $functionDefinitions[$functionName]
                )
            ))
    }
    $copySessionState.Commands.Add((
            New-Object Management.Automation.Runspaces.SessionStateFunctionEntry(
                "Write-RenderKitLog",
                $logStub
            )
        ))
    $verifySessionState.Commands.Add((
            New-Object Management.Automation.Runspaces.SessionStateFunctionEntry(
                "Write-RenderKitLog",
                $logStub
            )
        ))

    $copyPool = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(
        1,
        $Concurrency,
        $copySessionState,
        $host
    )
    $verifyPool = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(
        1,
        $VerifyConcurrency,
        $verifySessionState,
        $host
    )
    $copyPool.Open()
    $verifyPool.Open()

    $pendingCopy = New-Object System.Collections.Generic.Queue[object]
    foreach ($workItem in $WorkItems) {
        $pendingCopy.Enqueue($workItem)
    }
    $pendingVerify = New-Object System.Collections.Generic.Queue[object]
    $activeCopy = New-Object System.Collections.Generic.List[object]
    $activeVerify = New-Object System.Collections.Generic.List[object]
    $results = New-Object System.Collections.Generic.List[object]

    $copyWorkerScript = @'
param(
    $WorkItem,
    [string]$HashAlgorithm,
    [int]$BufferSizeBytes
)

Invoke-RenderKitImportCopyWorkItem `
    -WorkItem $WorkItem `
    -HashAlgorithm $HashAlgorithm `
    -BufferSizeBytes $BufferSizeBytes
'@
    $verifyWorkerScript = @'
param(
    $CopyResult,
    [string]$HashAlgorithm,
    [int]$BufferSizeBytes
)

Invoke-RenderKitImportVerifyWorkItem `
    -CopyResult $CopyResult `
    -HashAlgorithm $HashAlgorithm `
    -BufferSizeBytes $BufferSizeBytes
'@

    $inFlightBytes = [int64]0
    $peakInFlightBytes = [int64]0
    $peakCopyConcurrency = 0
    $peakVerifyConcurrency = 0
    $peakConcurrency = 0
    $parallelCompletedProgressBytes = [int64]0
    $parallelProcessedBytes = [int64]0
    $concurrencyAdjustments = 0
    $adaptiveEnabled = (
        $AdaptiveConcurrencyEnabled -and
        $TransferProfile -ne "Conservative" -and
        $Concurrency -gt 1
    )
    $currentCopyLimit = if ($adaptiveEnabled) {
        if ($TransferProfile -eq "Maximum") {
            [Math]::Min(2, $Concurrency)
        }
        else {
            1
        }
    }
    else {
        $Concurrency
    }
    $windowStartedAt = Get-Date
    $windowBytes = [int64]0
    $windowCompletions = 0
    $previousWindowRate = $null

    try {
        while (
            $pendingCopy.Count -gt 0 -or
            $activeCopy.Count -gt 0 -or
            $pendingVerify.Count -gt 0 -or
            $activeVerify.Count -gt 0
        ) {
            while (
                $pendingCopy.Count -gt 0 -and
                $activeCopy.Count -lt $currentCopyLimit
            ) {
                $nextItem = $pendingCopy.Peek()
                $admissionBytes = Get-RenderKitImportTransferAdmissionByte `
                    -WorkItem $nextItem `
                    -BufferSizeBytes $BufferSizeBytes
                if (
                    $inFlightBytes -gt 0 -and
                    ($inFlightBytes + $admissionBytes) -gt $MaxInFlightBytes
                ) {
                    break
                }

                $null = $pendingCopy.Dequeue()
                $worker = [Management.Automation.PowerShell]::Create()
                $worker.RunspacePool = $copyPool
                $null = $worker.AddScript($copyWorkerScript)
                $null = $worker.AddArgument($nextItem)
                $null = $worker.AddArgument($HashAlgorithm)
                $null = $worker.AddArgument($BufferSizeBytes)
                $asyncResult = $worker.BeginInvoke()
                $activeCopy.Add([PSCustomObject]@{
                        WorkItem       = $nextItem
                        AdmissionBytes = $admissionBytes
                        PowerShell     = $worker
                        AsyncResult    = $asyncResult
                    })
                $inFlightBytes += $admissionBytes
                $peakInFlightBytes = [Math]::Max($peakInFlightBytes, $inFlightBytes)
            }

            while (
                $pendingVerify.Count -gt 0 -and
                $activeVerify.Count -lt $VerifyConcurrency
            ) {
                $verifyItem = $pendingVerify.Dequeue()
                $worker = [Management.Automation.PowerShell]::Create()
                $worker.RunspacePool = $verifyPool
                $null = $worker.AddScript($verifyWorkerScript)
                $null = $worker.AddArgument($verifyItem.CopyResult)
                $null = $worker.AddArgument($HashAlgorithm)
                $null = $worker.AddArgument($BufferSizeBytes)
                $asyncResult = $worker.BeginInvoke()
                $activeVerify.Add([PSCustomObject]@{
                        WorkItem       = $verifyItem.CopyResult.WorkItem
                        CopyResult     = $verifyItem.CopyResult
                        AdmissionBytes = [int64]$verifyItem.AdmissionBytes
                        PowerShell     = $worker
                        AsyncResult    = $asyncResult
                    })
            }

            $peakCopyConcurrency = [Math]::Max($peakCopyConcurrency, $activeCopy.Count)
            $peakVerifyConcurrency = [Math]::Max($peakVerifyConcurrency, $activeVerify.Count)
            $peakConcurrency = [Math]::Max(
                $peakConcurrency,
                ($activeCopy.Count + $activeVerify.Count)
            )

            $completedAny = $false
            for ($i = $activeCopy.Count - 1; $i -ge 0; $i--) {
                $job = $activeCopy[$i]
                if (-not $job.AsyncResult.IsCompleted) {
                    continue
                }

                $completedAny = $true
                try {
                    $workerOutput = @($job.PowerShell.EndInvoke($job.AsyncResult))
                    if ($job.PowerShell.Streams.Error.Count -gt 0) {
                        throw [string]$job.PowerShell.Streams.Error[0]
                    }
                    if ($workerOutput.Count -eq 0) {
                        throw "Copy worker returned no result for '$($job.WorkItem.SourcePath)'."
                    }
                    $copyResult = $workerOutput[-1]
                }
                catch {
                    $now = Get-Date
                    $copyResult = [PSCustomObject]@{
                        WorkItem             = $job.WorkItem
                        Status               = "Failed"
                        SourceHash           = $null
                        CopiedBytes          = [int64]0
                        CopyDurationSeconds  = [double]0
                        StartedAt            = $now
                        CopyEndedAt          = $now
                        SourceMovedToStaging = $false
                        CopyEngine           = $null
                        RollbackStatus       = "NotRequired"
                        RollbackError        = $null
                        Error                = $_.Exception.Message
                    }
                }
                finally {
                    $job.PowerShell.Dispose()
                    $activeCopy.RemoveAt($i)
                }

                $parallelCompletedProgressBytes += [int64]$job.WorkItem.Bytes
                $windowBytes += [int64]$copyResult.CopiedBytes
                $windowCompletions++

                if ([string]$copyResult.Status -eq "Copied") {
                    $pendingVerify.Enqueue([PSCustomObject]@{
                            CopyResult     = $copyResult
                            AdmissionBytes = [int64]$job.AdmissionBytes
                        })
                }
                else {
                    $failedResult = Invoke-RenderKitImportVerifyWorkItem `
                        -CopyResult $copyResult `
                        -HashAlgorithm $HashAlgorithm `
                        -BufferSizeBytes $BufferSizeBytes
                    $results.Add($failedResult)
                    $inFlightBytes -= [int64]$job.AdmissionBytes
                    $parallelCompletedProgressBytes += [int64]$job.WorkItem.Bytes
                }

                if ($adaptiveEnabled -and $windowCompletions -ge 2) {
                    $windowElapsed = [Math]::Max(
                        [double]0.001,
                        ((Get-Date) - $windowStartedAt).TotalSeconds
                    )
                    $windowRate = [double]$windowBytes / $windowElapsed
                    $nextCopyLimit = $currentCopyLimit
                    if ($null -eq $previousWindowRate) {
                        if ($currentCopyLimit -lt $Concurrency) {
                            $nextCopyLimit++
                        }
                    }
                    elseif (
                        $windowRate -lt ([double]$previousWindowRate * 0.75) -and
                        $currentCopyLimit -gt 1
                    ) {
                        $nextCopyLimit--
                    }
                    elseif (
                        $windowRate -ge ([double]$previousWindowRate * 0.90) -and
                        $currentCopyLimit -lt $Concurrency
                    ) {
                        $nextCopyLimit++
                    }

                    if ($nextCopyLimit -ne $currentCopyLimit) {
                        $currentCopyLimit = $nextCopyLimit
                        $concurrencyAdjustments++
                    }
                    $previousWindowRate = $windowRate
                    $windowStartedAt = Get-Date
                    $windowBytes = [int64]0
                    $windowCompletions = 0
                }
            }

            for ($i = $activeVerify.Count - 1; $i -ge 0; $i--) {
                $job = $activeVerify[$i]
                if (-not $job.AsyncResult.IsCompleted) {
                    continue
                }

                $completedAny = $true
                try {
                    $workerOutput = @($job.PowerShell.EndInvoke($job.AsyncResult))
                    if ($job.PowerShell.Streams.Error.Count -gt 0) {
                        throw [string]$job.PowerShell.Streams.Error[0]
                    }
                    if ($workerOutput.Count -eq 0) {
                        throw "Verify worker returned no result for '$($job.WorkItem.SourcePath)'."
                    }
                    $workerResult = $workerOutput[-1]
                }
                catch {
                    $workerResult = Invoke-RenderKitImportVerifyWorkItem `
                        -CopyResult $job.CopyResult `
                        -HashAlgorithm $HashAlgorithm `
                        -BufferSizeBytes $BufferSizeBytes
                }
                finally {
                    $job.PowerShell.Dispose()
                    $activeVerify.RemoveAt($i)
                    $inFlightBytes -= [int64]$job.AdmissionBytes
                }

                $results.Add($workerResult)
                $parallelCompletedProgressBytes += [int64]$job.WorkItem.Bytes
                if ($workerResult.Status -eq "Imported") {
                    $parallelProcessedBytes += [int64]$workerResult.Bytes
                }
            }

            Update-RenderKitImportTransferProgress `
                -StartedAt $StartedAt `
                -CompletedCount ($CompletedFileCount + $results.Count) `
                -TotalCount $TotalFileCount `
                -ProcessedBytes ($ProcessedBytes + $parallelProcessedBytes) `
                -TotalBytes $PlannedBytes `
                -ProgressBytesCompleted ($CompletedProgressBytes + $parallelCompletedProgressBytes) `
                -ProgressBytesTotal $TotalProgressBytes `
                -Stage ("pipeline {0}" -f $SchedulerClass) `
                -CurrentFileProcessedBytes $inFlightBytes `
                -CurrentFileTotalBytes $peakInFlightBytes `
                -CurrentOperation (
                    "PIPELINE {0}: copy {1}/{2}, verify {3}/{4}, queued {5}" -f `
                        $SchedulerClass.ToUpperInvariant(), `
                        $activeCopy.Count, `
                        $currentCopyLimit, `
                        $activeVerify.Count, `
                        $VerifyConcurrency, `
                        ($pendingCopy.Count + $pendingVerify.Count)
                )

            if (
                -not $completedAny -and
                ($activeCopy.Count -gt 0 -or $activeVerify.Count -gt 0)
            ) {
                if ($activeVerify.Count -gt 0) {
                    $null = $activeVerify[0].AsyncResult.AsyncWaitHandle.WaitOne(50)
                }
                else {
                    $null = $activeCopy[0].AsyncResult.AsyncWaitHandle.WaitOne(50)
                }
            }
        }
    }
    finally {
        foreach ($job in @($activeCopy.ToArray()) + @($activeVerify.ToArray())) {
            try {
                $job.PowerShell.Stop()
            }
            catch {
                # Best-effort shutdown; disposal below still releases the worker.
            }
            finally {
                $job.PowerShell.Dispose()
            }
        }

        $copyPool.Close()
        $copyPool.Dispose()
        $verifyPool.Close()
        $verifyPool.Dispose()
    }

    return [PSCustomObject]@{
        Results                = @($results.ToArray() | Sort-Object -Property Index)
        PeakConcurrency        = $peakConcurrency
        PeakCopyConcurrency    = $peakCopyConcurrency
        PeakVerifyConcurrency  = $peakVerifyConcurrency
        PeakInFlightBytes      = $peakInFlightBytes
        ConcurrencyAdjustments = $concurrencyAdjustments
    }
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
        [ValidateSet("Fast", "Full")]
        [string]$VerificationMode = "Fast",
        [ValidateSet("Maximum", "Balanced", "Conservative")]
        [string]$TransferProfile = "Maximum",
        [ValidateRange(1, 1024)]
        [int]$SmallFileThresholdMB = 64,
        [ValidateRange(0, 32)]
        [int]$SmallFileConcurrency = 0,
        [ValidateRange(0, 16)]
        [int]$LargeFileConcurrency = 0,
        [ValidateRange(0, 16)]
        [int]$VerifyConcurrency = 0,
        [ValidateRange(1, 65536)]
        [int]$MaxInFlightMB = 512,
        [ValidateRange(1, 64)]
        [int]$TransferBufferSizeMB = 8,
        [ValidateSet("Keep", "Move")]
        [string]$SourceDisposition = "Keep",
        [switch]$Simulate
    )

    $schedulerConfiguration = Get-RenderKitImportTransferSchedulerConfiguration `
        -TransferProfile $TransferProfile `
        -SmallFileThresholdMB $SmallFileThresholdMB `
        -SmallFileConcurrency $SmallFileConcurrency `
        -LargeFileConcurrency $LargeFileConcurrency `
        -VerifyConcurrency $VerifyConcurrency `
        -MaxInFlightMB $MaxInFlightMB `
        -TransferBufferSizeMB $TransferBufferSizeMB

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
            HashAlgorithm           = if ($VerificationMode -eq "Full" -and $SourceDisposition -eq "Keep") { $HashAlgorithm } else { $null }
            RequestedHashAlgorithm  = $HashAlgorithm
            VerificationMode        = $VerificationMode
            TransferProfile         = $schedulerConfiguration.TransferProfile
            SmallFileThresholdMB    = $schedulerConfiguration.SmallFileThresholdMB
            SmallFileConcurrency    = $schedulerConfiguration.SmallFileConcurrency
            LargeFileConcurrency    = $schedulerConfiguration.LargeFileConcurrency
            VerifyConcurrency       = $schedulerConfiguration.VerifyConcurrency
            AdaptiveConcurrencyEnabled = $schedulerConfiguration.AdaptiveConcurrencyEnabled
            MaxInFlightMB           = $schedulerConfiguration.MaxInFlightMB
            TransferBufferSizeMB    = $schedulerConfiguration.TransferBufferSizeMB
            SourceDisposition       = $SourceDisposition
            SmallFileCount          = 0
            LargeFileCount          = 0
            ParallelizedFileCount   = 0
            PeakConcurrency         = 0
            PeakCopyConcurrency     = 0
            PeakVerifyConcurrency   = 0
            ConcurrencyAdjustments  = 0
            PeakInFlightBytes       = [int64]0
            SameVolumeMoveFileCount = 0
            FastCopyFileCount       = 0
            FullVerificationFileCount = 0
            RolledBackFileCount     = 0
            RollbackFailedFileCount = 0
            PlannedFileCount        = 0
            NotTransferableFileCount = $notTransferable.Count
            ImportedFileCount       = 0
            SimulatedFileCount      = 0
            FailedFileCount         = 0
            PlannedBytes            = [int64]0
            CopiedBytes             = [int64]0
            VerifiedBytes           = [int64]0
            ProcessedBytes          = [int64]0
            CopyDurationSeconds     = [double]0
            VerificationDurationSeconds = [double]0
            DurationSeconds         = [double]0
            CopyAverageSpeedMBps    = [double]0
            VerificationAverageSpeedMBps = [double]0
            EndToEndAverageSpeedMBps = [double]0
            AverageSpeedMBps        = [double]0
            StartedAt               = $null
            EndedAt                 = $null
            Transactions            = @()
        }
    }

    $startTime = Get-Date
    $processedBytes = [int64]0
    $copiedBytes = [int64]0
    $verifiedBytes = [int64]0
    $copyDurationSeconds = [double]0
    $verificationDurationSeconds = [double]0
    $progressTotalBytes = if ($Simulate) { [int64]$plannedBytes } else { [int64]($plannedBytes * 2) }
    $completedProgressBytes = [int64]0
    $importedCount = 0
    $simulatedCount = 0
    $failedCount = 0
    $completedCount = 0
    $transferTransactions = New-Object System.Collections.Generic.List[object]
    $reservedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $smallFileCount = @($transferCandidates | Where-Object {
        [int64]$_.Length -le [int64]$schedulerConfiguration.SmallFileThresholdBytes
    }).Count
    $largeFileCount = $transferCandidates.Count - $smallFileCount
    $parallelizedFileCount = 0
    $peakConcurrency = 1
    $peakCopyConcurrency = 1
    $peakVerifyConcurrency = 1
    $concurrencyAdjustments = 0
    $peakInFlightBytes = [int64]0
    $sameVolumeMoveFileCount = 0
    $fastCopyFileCount = 0
    $fullVerificationFileCount = 0
    $rolledBackFileCount = 0
    $rollbackFailedFileCount = 0

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
        $preparedWorkItems = New-Object System.Collections.Generic.List[object]
        for ($i = 0; $i -lt $transferCandidates.Count; $i++) {
        $file = $transferCandidates[$i]
        $sourcePath = [string]$file.FullName
        $destinationDirectory = [string]$file.DestinationPath
        $destinationRelativePath = [string]$file.DestinationRelativePath
        $finalDestinationPath = $null
        $stagingPath = $null
        $preparationError = $null
        $transferMethod = "Copy"

        try {
            if ([string]::IsNullOrWhiteSpace($destinationDirectory)) {
                throw "Destination path is empty for '$sourcePath'."
            }

            $targetPath = Join-Path $destinationDirectory $file.Name
            $finalDestinationPath = Resolve-RenderKitImportUniqueFilePath `
                -Path $targetPath `
                -ReservedPaths $reservedPaths

            if ($SourceDisposition -eq "Move") {
                if (-not (Test-RenderKitImportSameVolume `
                            -SourcePath $sourcePath `
                            -DestinationPath $finalDestinationPath)) {
                    throw "SourceDisposition Move requires source and destination on the same Windows volume: '$sourcePath' -> '$finalDestinationPath'."
                }

                $transferMethod = "SameVolumeMove"
            }

            if (-not $Simulate) {
                $stagingPath = Join-Path $tempRunRoot ("{0:D6}_{1}" -f ($i + 1), $file.Name)
                if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
                    New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
                }
            }
        }
        catch {
            $preparationError = $_.Exception.Message
        }

        $schedulerClass = if (
            [int64]$file.Length -le [int64]$schedulerConfiguration.SmallFileThresholdBytes
        ) {
            "Small"
        }
        else {
            "Large"
        }

        $preparedWorkItems.Add([PSCustomObject]@{
                Index                   = $i
                File                    = $file
                SourcePath              = $sourcePath
                DestinationDirectory    = $destinationDirectory
                DestinationRelativePath = $destinationRelativePath
                FinalDestinationPath    = $finalDestinationPath
                StagingPath             = $stagingPath
                Bytes                   = [int64]$file.Length
                SchedulerClass          = $schedulerClass
                TransferMethod          = $transferMethod
                VerificationMode        = $VerificationMode
                PreparationError        = $preparationError
            })
    }

    $parallelResultsByIndex = New-Object "System.Collections.Generic.Dictionary[int,object]"
    if (-not $Simulate) {
        $parallelCompletedFileCount = 0
        $parallelCompletedProgressBytes = [int64]0
        $parallelProcessedBytes = [int64]0

        $smallWorkItems = @($preparedWorkItems | Where-Object {
            $_.SchedulerClass -eq "Small" -and
            [string]::IsNullOrWhiteSpace([string]$_.PreparationError)
        })
        if (
            $schedulerConfiguration.TransferProfile -ne "Conservative" -and
            $smallWorkItems.Count -gt 1
        ) {
            $smallParallelResult = $null
            try {
                $smallParallelResult = Invoke-RenderKitImportParallelTransferWorkItem `
                    -WorkItems $smallWorkItems `
                    -Concurrency $schedulerConfiguration.SmallFileConcurrency `
                    -VerifyConcurrency $schedulerConfiguration.VerifyConcurrency `
                    -MaxInFlightBytes $schedulerConfiguration.MaxInFlightBytes `
                    -HashAlgorithm $HashAlgorithm `
                    -BufferSizeBytes $schedulerConfiguration.TransferBufferSizeBytes `
                    -StartedAt $startTime `
                    -TotalFileCount $transferCandidates.Count `
                    -TotalProgressBytes $progressTotalBytes `
                    -CompletedFileCount $parallelCompletedFileCount `
                    -CompletedProgressBytes $parallelCompletedProgressBytes `
                    -ProcessedBytes $parallelProcessedBytes `
                    -PlannedBytes $plannedBytes `
                    -SchedulerClass "small" `
                    -TransferProfile $schedulerConfiguration.TransferProfile `
                    -AdaptiveConcurrencyEnabled $schedulerConfiguration.AdaptiveConcurrencyEnabled
            }
            catch {
                Write-RenderKitLog `
                    -Level Warning `
                    -Message "Small-file parallel scheduler unavailable; continuing serially: $($_.Exception.Message)"
            }

            if ($null -ne $smallParallelResult) {
                foreach ($parallelResult in @($smallParallelResult.Results)) {
                    $parallelResultsByIndex[[int]$parallelResult.Index] = $parallelResult
                    $parallelCompletedFileCount++
                    $parallelCompletedProgressBytes += [int64]$parallelResult.Bytes * 2
                    if ($parallelResult.Status -eq "Imported") {
                        $parallelProcessedBytes += [int64]$parallelResult.Bytes
                    }
                }

                if ([int]$smallParallelResult.PeakConcurrency -gt 1) {
                    $parallelizedFileCount += $smallWorkItems.Count
                }
                $peakConcurrency = [Math]::Max($peakConcurrency, [int]$smallParallelResult.PeakConcurrency)
                $peakCopyConcurrency = [Math]::Max($peakCopyConcurrency, [int]$smallParallelResult.PeakCopyConcurrency)
                $peakVerifyConcurrency = [Math]::Max($peakVerifyConcurrency, [int]$smallParallelResult.PeakVerifyConcurrency)
                $concurrencyAdjustments += [int]$smallParallelResult.ConcurrencyAdjustments
                $peakInFlightBytes = [Math]::Max($peakInFlightBytes, [int64]$smallParallelResult.PeakInFlightBytes)
            }
        }

        $largeWorkItems = @($preparedWorkItems | Where-Object {
            $_.SchedulerClass -eq "Large" -and
            [string]::IsNullOrWhiteSpace([string]$_.PreparationError)
        })
        if (
            $schedulerConfiguration.TransferProfile -ne "Conservative" -and
            $largeWorkItems.Count -gt 1
        ) {
            $largeParallelResult = $null
            try {
                $largeParallelResult = Invoke-RenderKitImportParallelTransferWorkItem `
                    -WorkItems $largeWorkItems `
                    -Concurrency $schedulerConfiguration.LargeFileConcurrency `
                    -VerifyConcurrency $schedulerConfiguration.VerifyConcurrency `
                    -MaxInFlightBytes $schedulerConfiguration.MaxInFlightBytes `
                    -HashAlgorithm $HashAlgorithm `
                    -BufferSizeBytes $schedulerConfiguration.TransferBufferSizeBytes `
                    -StartedAt $startTime `
                    -TotalFileCount $transferCandidates.Count `
                    -TotalProgressBytes $progressTotalBytes `
                    -CompletedFileCount $parallelCompletedFileCount `
                    -CompletedProgressBytes $parallelCompletedProgressBytes `
                    -ProcessedBytes $parallelProcessedBytes `
                    -PlannedBytes $plannedBytes `
                    -SchedulerClass "large" `
                    -TransferProfile $schedulerConfiguration.TransferProfile `
                    -AdaptiveConcurrencyEnabled $schedulerConfiguration.AdaptiveConcurrencyEnabled
            }
            catch {
                Write-RenderKitLog `
                    -Level Warning `
                    -Message "Large-file parallel scheduler unavailable; continuing serially: $($_.Exception.Message)"
            }

            if ($null -ne $largeParallelResult) {
                foreach ($parallelResult in @($largeParallelResult.Results)) {
                    $parallelResultsByIndex[[int]$parallelResult.Index] = $parallelResult
                }

                if ([int]$largeParallelResult.PeakConcurrency -gt 1) {
                    $parallelizedFileCount += $largeWorkItems.Count
                }
                $peakConcurrency = [Math]::Max($peakConcurrency, [int]$largeParallelResult.PeakConcurrency)
                $peakCopyConcurrency = [Math]::Max($peakCopyConcurrency, [int]$largeParallelResult.PeakCopyConcurrency)
                $peakVerifyConcurrency = [Math]::Max($peakVerifyConcurrency, [int]$largeParallelResult.PeakVerifyConcurrency)
                $concurrencyAdjustments += [int]$largeParallelResult.ConcurrencyAdjustments
                $peakInFlightBytes = [Math]::Max($peakInFlightBytes, [int64]$largeParallelResult.PeakInFlightBytes)
            }
        }
    }

        foreach ($parallelTransaction in @($parallelResultsByIndex.Values | Sort-Object -Property Index)) {
            $transferTransactions.Add($parallelTransaction)
            $copiedBytes += [int64]$parallelTransaction.CopiedBytes
            $verifiedBytes += [int64]$parallelTransaction.VerifiedBytes
            $copyDurationSeconds += [double]$parallelTransaction.CopyDurationSeconds
            $verificationDurationSeconds += [double]$parallelTransaction.VerificationDurationSeconds
            if ($parallelTransaction.TransferMethod -eq "SameVolumeMove") {
                $sameVolumeMoveFileCount++
            }
            elseif ($parallelTransaction.VerificationMode -eq "Fast") {
                $fastCopyFileCount++
            }
            elseif ($parallelTransaction.VerificationMode -eq "Full") {
                $fullVerificationFileCount++
            }
            if ($parallelTransaction.RollbackStatus -eq "Succeeded") {
                $rolledBackFileCount++
            }
            elseif ($parallelTransaction.RollbackStatus -eq "Failed") {
                $rollbackFailedFileCount++
            }

            if ($parallelTransaction.Status -eq "Imported") {
                $importedCount++
                $processedBytes += [int64]$parallelTransaction.Bytes
            }
            else {
                $failedCount++
                Write-RenderKitLog `
                    -Level Error `
                    -Message "Phase 4 transfer failed for '$($parallelTransaction.SourcePath)': $($parallelTransaction.Error)" `
                    -NoConsole
            }

            $completedProgressBytes += [int64]$parallelTransaction.Bytes * 2
            $completedCount++
            $logLevel = if ($parallelTransaction.Status -eq "Failed") { "Warning" } else { "Info" }
            $destinationForLog = if (
                [string]::IsNullOrWhiteSpace([string]$parallelTransaction.DestinationPath)
            ) {
                "<none>"
            }
            else {
                [string]$parallelTransaction.DestinationPath
            }
            Write-RenderKitLog -Level $logLevel -Message (
                "Phase 4 tx {0}/{1}: {2} ({3} scheduler) | '{4}' -> '{5}' | {6} | {7:N3}s" -f `
                    ([int]$parallelTransaction.Index + 1), `
                    $transferCandidates.Count, `
                    $parallelTransaction.Status, `
                    $parallelTransaction.SchedulerClass, `
                    $parallelTransaction.SourcePath, `
                    $destinationForLog, `
                    (ConvertTo-RenderKitHumanSize -Bytes ([int64]$parallelTransaction.Bytes)), `
                    [double]$parallelTransaction.DurationSeconds
            )
        }

        for ($i = 0; $i -lt $preparedWorkItems.Count; $i++) {
            $workItem = $preparedWorkItems[$i]
            $file = $workItem.File
            $fileStart = Get-Date
            $sourcePath = [string]$workItem.SourcePath
            $destinationDirectory = [string]$workItem.DestinationDirectory
            $destinationRelativePath = [string]$workItem.DestinationRelativePath
            $finalDestinationPath = [string]$workItem.FinalDestinationPath
            $stagingPath = [string]$workItem.StagingPath
            $sourceHash = $null
            $stagingHash = $null
            $errorMessage = $null
            $status = "Pending"
            $bytes = [int64]$file.Length
            $fileCopiedBytes = [int64]0
            $fileVerifiedBytes = [int64]0
            $fileCopyDurationSeconds = [double]0
            $fileVerificationDurationSeconds = [double]0
            $transferMethod = [string]$workItem.TransferMethod
            $verificationMode = if ($transferMethod -eq "SameVolumeMove") {
                "RenameIdentity"
            }
            else {
                [string]$workItem.VerificationMode
            }
            $sourceMovedToStaging = $false
            $copyEngine = if ($Simulate) { "Simulated" } else { $null }
            $rollbackStatus = "NotRequired"
            $rollbackError = $null
            $progressBytesForCurrentFile = if ($Simulate) { $bytes } else { [int64]($bytes * 2) }

            $parallelTransaction = $null
            if ($parallelResultsByIndex.TryGetValue($i, [ref]$parallelTransaction)) {
                continue
            }

            if (-not $Simulate) {
                $serialInFlightBytes = Get-RenderKitImportTransferAdmissionByte `
                    -WorkItem $workItem `
                    -BufferSizeBytes $schedulerConfiguration.TransferBufferSizeBytes
                $peakInFlightBytes = [Math]::Max($peakInFlightBytes, $serialInFlightBytes)
            }

            try {
                if (-not [string]::IsNullOrWhiteSpace([string]$workItem.PreparationError)) {
                    Write-RenderKitLog -Level Error -Message ([string]$workItem.PreparationError)
                    throw [string]$workItem.PreparationError
                }

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
                    $serialResult = Invoke-RenderKitImportTransferWorkItem `
                        -WorkItem $workItem `
                        -HashAlgorithm $HashAlgorithm `
                        -BufferSizeBytes $schedulerConfiguration.TransferBufferSizeBytes

                    $sourceHash = $serialResult.SourceHash
                    $stagingHash = $serialResult.StagingHash
                    $fileCopiedBytes = [int64]$serialResult.CopiedBytes
                    $fileVerifiedBytes = [int64]$serialResult.VerifiedBytes
                    $fileCopyDurationSeconds = [double]$serialResult.CopyDurationSeconds
                    $fileVerificationDurationSeconds = [double]$serialResult.VerificationDurationSeconds
                    $sourceMovedToStaging = [bool]$serialResult.SourceMovedToStaging
                    $copyEngine = [string]$serialResult.CopyEngine
                    $rollbackStatus = [string]$serialResult.RollbackStatus
                    $rollbackError = [string]$serialResult.RollbackError
                    $copiedBytes += $fileCopiedBytes
                    $verifiedBytes += $fileVerifiedBytes
                    $copyDurationSeconds += $fileCopyDurationSeconds
                    $verificationDurationSeconds += $fileVerificationDurationSeconds
                    $status = [string]$serialResult.Status

                    if ($status -eq "Imported") {
                        $importedCount++
                        $processedBytes += $bytes
                    }
                    else {
                        throw [string]$serialResult.Error
                    }

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

                if (
                    -not $Simulate -and
                    $transferMethod -ne "SameVolumeMove" -and
                    -not [string]::IsNullOrWhiteSpace($stagingPath) -and
                    (Test-Path -Path $stagingPath -PathType Leaf)
                ) {
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

                $fileCopySpeedMBps = 0.0
                if ($fileCopyDurationSeconds -gt 0) {
                    $fileCopySpeedMBps = ([double]$fileCopiedBytes / 1MB) / $fileCopyDurationSeconds
                }

                $fileVerificationSpeedMBps = 0.0
                if ($fileVerificationDurationSeconds -gt 0) {
                    $fileVerificationSpeedMBps = ([double]$fileVerifiedBytes / 1MB) / $fileVerificationDurationSeconds
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
                        TransferMethod          = $transferMethod
                        VerificationMode        = $verificationMode
                        HashAlgorithm           = if (
                            $transferMethod -eq "SameVolumeMove" -or
                            $verificationMode -eq "Fast"
                        ) { $null } else { $HashAlgorithm }
                        SourceHash              = $sourceHash
                        StagingHash             = $stagingHash
                        Bytes                   = $bytes
                        CopiedBytes             = $fileCopiedBytes
                        VerifiedBytes           = $fileVerifiedBytes
                        Status                  = $status
                        StartedAt               = $fileStart
                        EndedAt                 = $fileEnd
                        CopyDurationSeconds     = [Math]::Round($fileCopyDurationSeconds, 3)
                        VerificationDurationSeconds = [Math]::Round($fileVerificationDurationSeconds, 3)
                        DurationSeconds         = [Math]::Round($fileDurationSeconds, 3)
                        CopySpeedMBps           = [Math]::Round($fileCopySpeedMBps, 3)
                        VerificationSpeedMBps   = [Math]::Round($fileVerificationSpeedMBps, 3)
                        SpeedMBps               = [Math]::Round($fileSpeedMBps, 3)
                        SourceMovedToStaging    = $sourceMovedToStaging
                        CopyEngine              = $copyEngine
                        RollbackStatus          = $rollbackStatus
                        RollbackError           = $rollbackError
                        Error                   = $errorMessage
                        SchedulerClass          = [string]$workItem.SchedulerClass
                    })

                if ($transferMethod -eq "SameVolumeMove") {
                    $sameVolumeMoveFileCount++
                }
                elseif ($verificationMode -eq "Fast") {
                    $fastCopyFileCount++
                }
                elseif ($verificationMode -eq "Full") {
                    $fullVerificationFileCount++
                }
                if ($rollbackStatus -eq "Succeeded") {
                    $rolledBackFileCount++
                }
                elseif ($rollbackStatus -eq "Failed") {
                    $rollbackFailedFileCount++
                }

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
            $unrestoredMoveFiles = @(
                $preparedWorkItems |
                    Where-Object {
                        $_.TransferMethod -eq "SameVolumeMove" -and
                        (Test-Path -LiteralPath $_.StagingPath -PathType Leaf) -and
                        -not (Test-Path -LiteralPath $_.SourcePath -PathType Leaf)
                    }
            )
            if ($unrestoredMoveFiles.Count -gt 0) {
                Write-RenderKitLog `
                    -Level Error `
                    -Message "Preserving transfer staging '$tempRunRoot' because $($unrestoredMoveFiles.Count) moved source file(s) could not be rolled back."
            }
            else {
                Remove-Item -Path $tempRunRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    $endTime = Get-Date
    $durationSeconds = ($endTime - $startTime).TotalSeconds
    if ($durationSeconds -lt 0) {
        $durationSeconds = 0
    }

    $copyAverageSpeedMBps = 0.0
    if ($copyDurationSeconds -gt 0) {
        $copyAverageSpeedMBps = ([double]$copiedBytes / 1MB) / $copyDurationSeconds
    }

    $verificationAverageSpeedMBps = 0.0
    if ($verificationDurationSeconds -gt 0) {
        $verificationAverageSpeedMBps = ([double]$verifiedBytes / 1MB) / $verificationDurationSeconds
    }

    $endToEndAverageSpeedMBps = 0.0
    if ($durationSeconds -gt 0) {
        $endToEndAverageSpeedMBps = ([double]$processedBytes / 1MB) / $durationSeconds
    }

    Write-RenderKitLog -Level Info -Message (
        "Phase 4 transfer completed: mode={0}, planned={1}, imported={2}, simulated={3}, failed={4}, processed={5}, duration={6:N2}s, copy={7:N2} MB/s, verify={8:N2} MB/s, endToEnd={9:N2} MB/s." -f `
            $VerificationMode, `
            $transferCandidates.Count, `
            $importedCount, `
            $simulatedCount, `
            $failedCount, `
            (ConvertTo-RenderKitHumanSize -Bytes $processedBytes), `
            $durationSeconds, `
            $copyAverageSpeedMBps, `
            $verificationAverageSpeedMBps, `
            $endToEndAverageSpeedMBps
    )

    return [PSCustomObject]@{
        ProjectRoot              = $ProjectRoot
        RunId                    = $runId
        TempRunRoot              = $tempRunRoot
        Simulated                = [bool]$Simulate
        HashAlgorithm            = if ($VerificationMode -eq "Full" -and $SourceDisposition -eq "Keep") { $HashAlgorithm } else { $null }
        RequestedHashAlgorithm   = $HashAlgorithm
        VerificationMode         = $VerificationMode
        TransferProfile          = $schedulerConfiguration.TransferProfile
        SmallFileThresholdMB     = $schedulerConfiguration.SmallFileThresholdMB
        SmallFileConcurrency     = $schedulerConfiguration.SmallFileConcurrency
        LargeFileConcurrency     = $schedulerConfiguration.LargeFileConcurrency
        VerifyConcurrency        = $schedulerConfiguration.VerifyConcurrency
        AdaptiveConcurrencyEnabled = $schedulerConfiguration.AdaptiveConcurrencyEnabled
        MaxInFlightMB            = $schedulerConfiguration.MaxInFlightMB
        TransferBufferSizeMB     = $schedulerConfiguration.TransferBufferSizeMB
        SourceDisposition        = $SourceDisposition
        SmallFileCount           = $smallFileCount
        LargeFileCount           = $largeFileCount
        ParallelizedFileCount    = $parallelizedFileCount
        PeakConcurrency          = $peakConcurrency
        PeakCopyConcurrency      = $peakCopyConcurrency
        PeakVerifyConcurrency    = $peakVerifyConcurrency
        ConcurrencyAdjustments   = $concurrencyAdjustments
        PeakInFlightBytes        = $peakInFlightBytes
        SameVolumeMoveFileCount  = $sameVolumeMoveFileCount
        FastCopyFileCount        = $fastCopyFileCount
        FullVerificationFileCount = $fullVerificationFileCount
        RolledBackFileCount      = $rolledBackFileCount
        RollbackFailedFileCount  = $rollbackFailedFileCount
        PlannedFileCount         = $transferCandidates.Count
        NotTransferableFileCount = $notTransferable.Count
        ImportedFileCount        = $importedCount
        SimulatedFileCount       = $simulatedCount
        FailedFileCount          = $failedCount
        PlannedBytes             = $plannedBytes
        CopiedBytes              = $copiedBytes
        VerifiedBytes            = $verifiedBytes
        ProcessedBytes           = $processedBytes
        CopyDurationSeconds      = [Math]::Round($copyDurationSeconds, 3)
        VerificationDurationSeconds = [Math]::Round($verificationDurationSeconds, 3)
        DurationSeconds          = [Math]::Round($durationSeconds, 3)
        CopyAverageSpeedMBps     = [Math]::Round($copyAverageSpeedMBps, 3)
        VerificationAverageSpeedMBps = [Math]::Round($verificationAverageSpeedMBps, 3)
        EndToEndAverageSpeedMBps = [Math]::Round($endToEndAverageSpeedMBps, 3)
        AverageSpeedMBps         = [Math]::Round($endToEndAverageSpeedMBps, 3)
        StartedAt                = $startTime
        EndedAt                  = $endTime
        Transactions             = @($transferTransactions.ToArray() | Sort-Object -Property Index)
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
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        "PSUseShouldProcessForStateChangingFunctions",
        "",
        Justification = "internal function. The public function already has a DryRun feature")]
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
    $copiedBytes = if ($Transfer) { [int64]$Transfer.CopiedBytes } else { [int64]0 }
    $verifiedBytes = if ($Transfer) { [int64]$Transfer.VerifiedBytes } else { [int64]0 }
    $copyDurationSeconds = if ($Transfer) { [double]$Transfer.CopyDurationSeconds } else { [double]0.0 }
    $verificationDurationSeconds = if ($Transfer) { [double]$Transfer.VerificationDurationSeconds } else { [double]0.0 }
    $copyAverageSpeedMBps = if ($Transfer) { [double]$Transfer.CopyAverageSpeedMBps } else { [double]0.0 }
    $verificationAverageSpeedMBps = if ($Transfer) { [double]$Transfer.VerificationAverageSpeedMBps } else { [double]0.0 }
    $endToEndAverageSpeedMBps = if ($Transfer) { [double]$Transfer.EndToEndAverageSpeedMBps } else { [double]0.0 }
    $verificationMode = if ($Transfer -and $Transfer.PSObject.Properties["VerificationMode"]) {
        [string]$Transfer.VerificationMode
    }
    else {
        "Fast"
    }
    $transferProfile = if ($Transfer) { [string]$Transfer.TransferProfile } else { "Maximum" }
    $smallFileCount = if ($Transfer) { [int]$Transfer.SmallFileCount } else { 0 }
    $largeFileCount = if ($Transfer) { [int]$Transfer.LargeFileCount } else { 0 }
    $parallelizedFileCount = if ($Transfer) { [int]$Transfer.ParallelizedFileCount } else { 0 }
    $peakConcurrency = if ($Transfer) { [int]$Transfer.PeakConcurrency } else { 0 }
    $peakCopyConcurrency = if ($Transfer) { [int]$Transfer.PeakCopyConcurrency } else { 0 }
    $peakVerifyConcurrency = if ($Transfer) { [int]$Transfer.PeakVerifyConcurrency } else { 0 }
    $concurrencyAdjustments = if ($Transfer) { [int]$Transfer.ConcurrencyAdjustments } else { 0 }
    $sourceDisposition = if ($Transfer) { [string]$Transfer.SourceDisposition } else { "Keep" }
    $sameVolumeMoveFileCount = if ($Transfer) { [int]$Transfer.SameVolumeMoveFileCount } else { 0 }
    $rolledBackFileCount = if ($Transfer) { [int]$Transfer.RolledBackFileCount } else { 0 }
    $rollbackFailedFileCount = if ($Transfer) { [int]$Transfer.RollbackFailedFileCount } else { 0 }
    $fastCopyFileCount = if ($Transfer -and $Transfer.PSObject.Properties["FastCopyFileCount"]) {
        [int]$Transfer.FastCopyFileCount
    }
    else { 0 }
    $fullVerificationFileCount = if ($Transfer -and $Transfer.PSObject.Properties["FullVerificationFileCount"]) {
        [int]$Transfer.FullVerificationFileCount
    }
    else { 0 }
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
        CopiedBytes              = $copiedBytes
        CopiedGB                 = [Math]::Round(([double]$copiedBytes / 1GB), 3)
        VerifiedBytes            = $verifiedBytes
        VerifiedGB               = [Math]::Round(([double]$verifiedBytes / 1GB), 3)
        ProcessedBytes           = $processedBytes
        ProcessedGB              = [Math]::Round(([double]$processedBytes / 1GB), 3)
        CopyDurationSeconds      = [Math]::Round($copyDurationSeconds, 3)
        VerificationDurationSeconds = [Math]::Round($verificationDurationSeconds, 3)
        AverageCopySpeedMBps     = [Math]::Round($copyAverageSpeedMBps, 3)
        AverageVerificationSpeedMBps = [Math]::Round($verificationAverageSpeedMBps, 3)
        AverageEndToEndSpeedMBps = [Math]::Round($endToEndAverageSpeedMBps, 3)
        VerificationMode         = $verificationMode
        TransferProfile          = $transferProfile
        SmallFileCount           = $smallFileCount
        LargeFileCount           = $largeFileCount
        ParallelizedFileCount    = $parallelizedFileCount
        PeakConcurrency          = $peakConcurrency
        PeakCopyConcurrency      = $peakCopyConcurrency
        PeakVerifyConcurrency    = $peakVerifyConcurrency
        ConcurrencyAdjustments   = $concurrencyAdjustments
        SourceDisposition        = $sourceDisposition
        SameVolumeMoveFileCount  = $sameVolumeMoveFileCount
        RolledBackFileCount      = $rolledBackFileCount
        RollbackFailedFileCount  = $rollbackFailedFileCount
        FastCopyFileCount        = $fastCopyFileCount
        FullVerificationFileCount = $fullVerificationFileCount
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
        [PSCustomObject]@{ Metric = "Average Verify Speed"; Value = ("{0:N2} MB/s" -f [double]$Report.AverageVerificationSpeedMBps) }
        [PSCustomObject]@{ Metric = "End-to-End Speed"; Value = ("{0:N2} MB/s" -f [double]$Report.AverageEndToEndSpeedMBps) }
        [PSCustomObject]@{ Metric = "Verification Mode"; Value = $Report.VerificationMode }
        [PSCustomObject]@{ Metric = "Transfer Profile"; Value = $Report.TransferProfile }
        [PSCustomObject]@{ Metric = "Small / Large Files"; Value = ("{0} / {1}" -f $Report.SmallFileCount, $Report.LargeFileCount) }
        [PSCustomObject]@{ Metric = "Parallelized Files"; Value = $Report.ParallelizedFileCount }
        [PSCustomObject]@{ Metric = "Peak Concurrency"; Value = $Report.PeakConcurrency }
        [PSCustomObject]@{ Metric = "Peak Copy / Verify"; Value = ("{0} / {1}" -f $Report.PeakCopyConcurrency, $Report.PeakVerifyConcurrency) }
        [PSCustomObject]@{ Metric = "Adaptive Adjustments"; Value = $Report.ConcurrencyAdjustments }
        [PSCustomObject]@{ Metric = "Source Disposition"; Value = $Report.SourceDisposition }
        [PSCustomObject]@{ Metric = "Move / Rollback / Failed"; Value = ("{0} / {1} / {2}" -f $Report.SameVolumeMoveFileCount, $Report.RolledBackFileCount, $Report.RollbackFailedFileCount) }
        [PSCustomObject]@{ Metric = "Fast / Full Files"; Value = ("{0} / {1}" -f $Report.FastCopyFileCount, $Report.FullVerificationFileCount) }
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
    $copiedBytes = if ($Transfer) { [int64]$Transfer.CopiedBytes } else { [int64]0 }
    $verifiedBytes = if ($Transfer) { [int64]$Transfer.VerifiedBytes } else { [int64]0 }
    $hashAlgorithm = if ($Transfer -and $Transfer.HashAlgorithm) { [string]$Transfer.HashAlgorithm } else { "-" }
    $verificationMode = if ($Transfer -and $Transfer.PSObject.Properties["VerificationMode"]) {
        [string]$Transfer.VerificationMode
    }
    else { "-" }
    $copyAverageSpeedMBps = if ($Transfer) { [double]$Transfer.CopyAverageSpeedMBps } else { 0 }
    $verificationAverageSpeedMBps = if ($Transfer) { [double]$Transfer.VerificationAverageSpeedMBps } else { 0 }
    $endToEndAverageSpeedMBps = if ($Transfer) { [double]$Transfer.EndToEndAverageSpeedMBps } else { 0 }
    $copyDurationSeconds = if ($Transfer) { [double]$Transfer.CopyDurationSeconds } else { 0 }
    $verificationDurationSeconds = if ($Transfer) { [double]$Transfer.VerificationDurationSeconds } else { 0 }
    $transferDurationSeconds = if ($Transfer) { [double]$Transfer.DurationSeconds } else { 0 }
    $transferSimulatedFlag = if ($Transfer) { [bool]$Transfer.Simulated } else { $false }
    $transferProfile = if ($Transfer) { [string]$Transfer.TransferProfile } else { "-" }
    $smallFileThresholdMB = if ($Transfer) { [int]$Transfer.SmallFileThresholdMB } else { 0 }
    $smallFileConcurrency = if ($Transfer) { [int]$Transfer.SmallFileConcurrency } else { 0 }
    $largeFileConcurrency = if ($Transfer) { [int]$Transfer.LargeFileConcurrency } else { 0 }
    $verifyConcurrency = if ($Transfer) { [int]$Transfer.VerifyConcurrency } else { 0 }
    $adaptiveConcurrencyEnabled = if ($Transfer) { [bool]$Transfer.AdaptiveConcurrencyEnabled } else { $false }
    $concurrencyAdjustments = if ($Transfer) { [int]$Transfer.ConcurrencyAdjustments } else { 0 }
    $maxInFlightMB = if ($Transfer) { [int]$Transfer.MaxInFlightMB } else { 0 }
    $transferBufferSizeMB = if ($Transfer) { [int]$Transfer.TransferBufferSizeMB } else { 0 }
    $sourceDisposition = if ($Transfer) { [string]$Transfer.SourceDisposition } else { "Keep" }
    $smallFileCount = if ($Transfer) { [int]$Transfer.SmallFileCount } else { 0 }
    $largeFileCount = if ($Transfer) { [int]$Transfer.LargeFileCount } else { 0 }
    $parallelizedFileCount = if ($Transfer) { [int]$Transfer.ParallelizedFileCount } else { 0 }
    $peakConcurrency = if ($Transfer) { [int]$Transfer.PeakConcurrency } else { 0 }
    $peakCopyConcurrency = if ($Transfer) { [int]$Transfer.PeakCopyConcurrency } else { 0 }
    $peakVerifyConcurrency = if ($Transfer) { [int]$Transfer.PeakVerifyConcurrency } else { 0 }
    $peakInFlightBytes = if ($Transfer) { [int64]$Transfer.PeakInFlightBytes } else { [int64]0 }
    $sameVolumeMoveFileCount = if ($Transfer) { [int]$Transfer.SameVolumeMoveFileCount } else { 0 }
    $rolledBackFileCount = if ($Transfer) { [int]$Transfer.RolledBackFileCount } else { 0 }
    $rollbackFailedFileCount = if ($Transfer) { [int]$Transfer.RollbackFailedFileCount } else { 0 }
    $fastCopyFileCount = if ($Transfer -and $Transfer.PSObject.Properties["FastCopyFileCount"]) {
        [int]$Transfer.FastCopyFileCount
    }
    else { 0 }
    $fullVerificationFileCount = if ($Transfer -and $Transfer.PSObject.Properties["FullVerificationFileCount"]) {
        [int]$Transfer.FullVerificationFileCount
    }
    else { 0 }
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
    $lines.Add(("CopiedToStaging: {0} ({1:N3} GB)" -f (ConvertTo-RenderKitHumanSize -Bytes ([int64]$copiedBytes)), ([double]$copiedBytes / 1GB)))
    $lines.Add(("VerifiedFromStaging: {0} ({1:N3} GB)" -f (ConvertTo-RenderKitHumanSize -Bytes ([int64]$verifiedBytes)), ([double]$verifiedBytes / 1GB)))
    $lines.Add(("Processed: {0} ({1:N3} GB)" -f (ConvertTo-RenderKitHumanSize -Bytes ([int64]$processedBytes)), ([double]$processedBytes / 1GB)))
    $lines.Add("")

    $lines.Add("[Transfer]")
    $lines.Add(("VerificationMode: {0}" -f $verificationMode))
    $lines.Add(("HashAlgorithm: {0}" -f $hashAlgorithm))
    $lines.Add(("TransferProfile: {0}" -f $transferProfile))
    $lines.Add(("SmallFileThresholdMB: {0}" -f $smallFileThresholdMB))
    $lines.Add(("SmallFileConcurrency: {0}" -f $smallFileConcurrency))
    $lines.Add(("LargeFileConcurrency: {0}" -f $largeFileConcurrency))
    $lines.Add(("VerifyConcurrency: {0}" -f $verifyConcurrency))
    $lines.Add(("AdaptiveConcurrencyEnabled: {0}" -f $adaptiveConcurrencyEnabled))
    $lines.Add(("ConcurrencyAdjustments: {0}" -f $concurrencyAdjustments))
    $lines.Add(("MaxInFlightMB: {0}" -f $maxInFlightMB))
    $lines.Add(("TransferBufferSizeMB: {0}" -f $transferBufferSizeMB))
    $lines.Add(("SourceDisposition: {0}" -f $sourceDisposition))
    $lines.Add(("SmallFileCount: {0}" -f $smallFileCount))
    $lines.Add(("LargeFileCount: {0}" -f $largeFileCount))
    $lines.Add(("ParallelizedFileCount: {0}" -f $parallelizedFileCount))
    $lines.Add(("PeakConcurrency: {0}" -f $peakConcurrency))
    $lines.Add(("PeakCopyConcurrency: {0}" -f $peakCopyConcurrency))
    $lines.Add(("PeakVerifyConcurrency: {0}" -f $peakVerifyConcurrency))
    $lines.Add(("PeakInFlightBytes: {0}" -f $peakInFlightBytes))
    $lines.Add(("SameVolumeMoveFileCount: {0}" -f $sameVolumeMoveFileCount))
    $lines.Add(("RolledBackFileCount: {0}" -f $rolledBackFileCount))
    $lines.Add(("RollbackFailedFileCount: {0}" -f $rollbackFailedFileCount))
    $lines.Add(("FastCopyFileCount: {0}" -f $fastCopyFileCount))
    $lines.Add(("FullVerificationFileCount: {0}" -f $fullVerificationFileCount))
    $lines.Add(("CopyDurationSeconds: {0:N3}" -f [double]$copyDurationSeconds))
    $lines.Add(("VerificationDurationSeconds: {0:N3}" -f [double]$verificationDurationSeconds))
    $lines.Add(("TransferDurationSeconds: {0:N3}" -f [double]$transferDurationSeconds))
    $lines.Add(("CopyAverageSpeedMBps: {0:N3}" -f [double]$copyAverageSpeedMBps))
    $lines.Add(("VerificationAverageSpeedMBps: {0:N3}" -f [double]$verificationAverageSpeedMBps))
    $lines.Add(("EndToEndAverageSpeedMBps: {0:N3}" -f [double]$endToEndAverageSpeedMBps))
    $lines.Add(("SimulationMode: {0}" -f $(if ($transferSimulatedFlag) { "Yes" } else { "No" })))
    $lines.Add("")

    $lines.Add("[Transactions]")
    if ($transactions.Count -eq 0) {
        $lines.Add("No transfer transactions recorded.")
    }
    else {
        $lines.Add("Status | Method | CopyEngine | Verification | Rollback | Size | Mapping | Destination | File | Error")
        foreach ($tx in $transactions) {
            $txStatus = if ($tx.Status) { [string]$tx.Status } else { "-" }
            $txMethod = if ($tx.TransferMethod) { [string]$tx.TransferMethod } else { "-" }
            $txCopyEngine = if ($tx.PSObject.Properties["CopyEngine"] -and $tx.CopyEngine) {
                [string]$tx.CopyEngine
            }
            else { "-" }
            $txVerification = if ($tx.VerificationMode) { [string]$tx.VerificationMode } else { "-" }
            $txRollback = if ($tx.RollbackStatus) { [string]$tx.RollbackStatus } else { "-" }
            $txSize = ConvertTo-RenderKitHumanSize -Bytes ([int64]$tx.Bytes)
            $txMapping = if ($tx.MappingId) { [string]$tx.MappingId } else { "-" }
            $txDestination = if ($tx.DestinationRelativePath) { [string]$tx.DestinationRelativePath } else { "-" }
            $txFile = if ($tx.SourcePath) { [IO.Path]::GetFileName([string]$tx.SourcePath) } else { "-" }
            $txError = if ($tx.RollbackError) {
                "{0}; rollback: {1}" -f [string]$tx.Error, [string]$tx.RollbackError
            }
            elseif ($tx.Error) {
                [string]$tx.Error
            }
            else {
                "-"
            }

            $lines.Add(("{0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9}" -f `
                        $txStatus, `
                        $txMethod, `
                        $txCopyEngine, `
                        $txVerification, `
                        $txRollback, `
                        $txSize, `
                        $txMapping, `
                        $txDestination, `
                        $txFile, `
                        $txError))
        }
    }

    Set-Content -Path $logPath -Value $lines -Encoding UTF8

    Write-RenderKitLog -Level Info -Message "Phase 5 revision log written: '$logPath'."
    return $logPath
}

function ConvertTo-RenderKitImportUserPath {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Path
    )

    if ($null -eq $Path) {
        return $Path
    }

    $trimmedPath = $Path.Trim()
    if ($trimmedPath.Length -ge 2) {
        $firstCharacter = $trimmedPath[0]
        $lastCharacter = $trimmedPath[$trimmedPath.Length -1]
        if (($firstCharacter -eq '"' -and $lastCharacter -eq '"') -or
            ($firstCharacter -eq "'" -and $lastCharacter -eq "'")) {
                return $trimmedPath.Substring(1, $trimmedPath.Length -2)
    }
}

return $trimmedPath
}

function Test-RenderKitImportArchivePath {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Path
    )

    if([string]::IsNullOrWhiteSpace($Path)) { return $false }

    $extension = [System.IO.Path]::GetExtension($Path)
    if ($extension -notin @('.rkit', '.rkitpkg')) { return $false }

    return (Test-Path -LiteralPath $Path -PathType Leaf)
}
