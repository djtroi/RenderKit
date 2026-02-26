function New-RenderKitImportCriteria {
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

function Merge-RenderKitImportCriteria {
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

    return New-RenderKitImportCriteria `
        -FolderFilter $folderFilter `
        -FromDate $fromDate `
        -ToDate $toDate `
        -Wildcard $wildcard
}

function ConvertTo-RenderKitImportDrivePath {
    [CmdletBinding()]
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
            Write-RenderKitLog -Level Error -Message "Source path '$resolvePath' is not a directory."
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

function Get-RenderKitImportFilteredFiles {
    [CmdletBinding()]
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

function Read-RenderKitImportDate {
    [CmdletBinding()]
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

function Read-RenderKitImportAdditionalCriteria {
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

    return New-RenderKitImportCriteria `
        -FolderFilter $folderFilter `
        -FromDate $fromDate `
        -ToDate $toDate `
        -Wildcard $wildcard
}

function Get-RenderKitImportTotalBytes {
    [CmdletBinding()]
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

    $totalBytes = Get-RenderKitImportTotalBytes -Files $Files
    $totalGB = [Math]::Round(([double]$totalBytes / 1GB), 3)
    Write-RenderKitLog -Level Info -Message  "Total size: $totalGB GB"
}
}
function ConvertTo-RenderKitImportIndexSelection {
    [CmdletBinding()]
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
        if (-not $script:RenderKitModuleRoot) {
            $script:RenderKitModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        }

        $systemMappingPath = Join-Path (Join-Path $script:RenderKitModuleRoot "Resources/Mappings") $fileName
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

function Resolve-RenderKitImportUnassignedFiles {
    [CmdletBinding()]
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
        Resolve-RenderKitImportUnassignedFiles `
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
        AssignedBytes      = Get-RenderKitImportTotalBytes -Files $assigned
        ToSortBytes        = Get-RenderKitImportTotalBytes -Files $toSort
        SkippedBytes       = Get-RenderKitImportTotalBytes -Files $skipped
        UnassignedBytes    = Get-RenderKitImportTotalBytes -Files $stillUnassigned
        DestinationFolders = @($lookupContext.DestinationFolders)
        Files              = $resolvedClassified
    }
}

function Get-RenderKitImportTransferCandidateFiles {
    [CmdletBinding()]
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
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [ValidateSet("SHA256", "SHA1", "MD5")]
        [string]$Algorithm = "SHA256"
    )

    try {
        return [string](Get-FileHash -Path $Path -Algorithm $Algorithm -ErrorAction Stop).Hash
    }
    catch {
        Write-RenderKitLog -Level Error -Message "Could not calculate $Algorithm hash for '$Path': $($_.Exception.Message)"
        throw
    }
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
        [string]$CurrentOperation
    )

    $elapsedSeconds = ((Get-Date) - $StartedAt).TotalSeconds
    if ($elapsedSeconds -lt 0.001) {
        $elapsedSeconds = 0.001
    }

    $speedMBps = ([double]$ProcessedBytes / 1MB) / $elapsedSeconds

    $percent = 0
    if ($TotalBytes -gt 0) {
        $percent = [int][Math]::Min(100, [Math]::Floor(([double]$ProcessedBytes * 100.0) / [double]$TotalBytes))
    }
    elseif ($TotalCount -gt 0) {
        $percent = [int][Math]::Min(100, [Math]::Floor(([double]$CompletedCount * 100.0) / [double]$TotalCount))
    }

    $status = "{0}/{1} files | {2} / {3} | {4:N2} MB/s" -f `
        $CompletedCount, `
        $TotalCount, `
        (ConvertTo-RenderKitHumanSize -Bytes $ProcessedBytes), `
        (ConvertTo-RenderKitHumanSize -Bytes $TotalBytes), `
        $speedMBps

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

    $transferCandidates = @(Get-RenderKitImportTransferCandidateFiles -ClassifiedFiles $ClassifiedFiles)
    $notTransferable = @(
        $ClassifiedFiles |
            Where-Object {
                $_.Classification -notin @("Assigned", "ToSort") -or
                [string]::IsNullOrWhiteSpace([string]$_.DestinationPath)
            }
    )

    $plannedBytes = Get-RenderKitImportTotalBytes -Files $transferCandidates
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

            try {
                if ([string]::IsNullOrWhiteSpace($destinationDirectory)) {
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
                        -CurrentOperation ("SIMULATE: {0} -> {1}" -f $file.Name, $destinationRelativePath)
                }
                else {
                    $stagingPath = Join-Path $tempRunRoot ("{0:D6}_{1}" -f ($i + 1), $file.Name)

                    Copy-Item -LiteralPath $sourcePath -Destination $stagingPath -Force -ErrorAction Stop
                    $sourceHash = Get-RenderKitImportFileHashValue -Path $sourcePath -Algorithm $HashAlgorithm
                    $stagingHash = Get-RenderKitImportFileHashValue -Path $stagingPath -Algorithm $HashAlgorithm

                    if ($sourceHash -ne $stagingHash) {
                        throw "Hash mismatch for '$sourcePath'. Source '$sourceHash', staging '$stagingHash'."
                    }

                    if (-not (Test-Path -Path $destinationDirectory -PathType Container)) {
                        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
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
                    -CurrentOperation ("FAILED: {0}" -f $file.Name)
            }
            finally {
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

    $record = [ordered]@{
        tool = [ordered]@{
            name          = "RenderKit"
            moduleVersion = $script:RenderKitModuleVersion
        }
        import = [ordered]@{
            runId            = $importRunId
            startedAt        = $ImportStartedAt.ToString("o")
            endedAt          = $ImportEndedAt.ToString("o")
            durationSeconds  = if ($FinalReport) { $FinalReport.DurationSeconds } else { [Math]::Round((($ImportEndedAt - $ImportStartedAt).TotalSeconds), 3) }
            user             = $env:USERNAME
            machine          = $env:COMPUTERNAME
            sourcePath       = $SourcePath
            sourceDrive      = $sourceDrive
            filters          = $Filters
        }
        project = [ordered]@{
            rootPath         = $ProjectRoot
            schemaVersion    = $projectSchemaVersion
            metadataPath     = if ($projectMetadata) { Join-Path $ProjectRoot ".renderkit\project.json" } else { $null }
        }
        template = [ordered]@{
            name             = $templateName
            version          = $templateVersion
            source           = $templateSource
        }
        counts = [ordered]@{
            scanned              = $ScanFileCount
            matched              = $MatchedFileCount
            selected             = $SelectedFileCount
            classified           = if ($Classification) { $Classification.FileCount } else { 0 }
            assigned             = if ($Classification) { $Classification.AssignedCount } else { 0 }
            toSort               = if ($Classification) { $Classification.ToSortCount } else { 0 }
            skipped              = if ($Classification) { $Classification.SkippedCount } else { 0 }
            unassignedOpen       = if ($Classification) { $Classification.UnassignedCount } else { 0 }
            unassignedHandled    = if ($FinalReport) { $FinalReport.UnassignedHandledCount } else { 0 }
            unassignedUnhandled  = if ($FinalReport) { $FinalReport.UnassignedUnhandledCount } else { 0 }
            transferPlanned      = if ($Transfer) { $Transfer.PlannedFileCount } else { 0 }
            transferImported     = if ($Transfer) { $Transfer.ImportedFileCount } else { 0 }
            transferSimulated    = if ($Transfer) { $Transfer.SimulatedFileCount } else { 0 }
            transferFailed       = if ($Transfer) { $Transfer.FailedFileCount } else { 0 }
        }
        bytes = [ordered]@{
            selectedBytes        = [int64]$SelectedTotalBytes
            importedBytes        = [int64]$importedBytes
            simulatedBytes       = [int64]$simulatedBytes
            failedBytes          = [int64]$failedBytes
            processedBytes       = if ($Transfer) { [int64]$Transfer.ProcessedBytes } else { [int64]0 }
        }
        transfer = [ordered]@{
            hashAlgorithm        = if ($Transfer) { $Transfer.HashAlgorithm } else { $null }
            averageSpeedMBps     = if ($Transfer) { $Transfer.AverageSpeedMBps } else { 0 }
            durationSeconds      = if ($Transfer) { $Transfer.DurationSeconds } else { 0 }
            simulated            = if ($Transfer) { [bool]$Transfer.Simulated } else { $false }
        }
        finalReport = $FinalReport
        transactions = if ($Transfer) { $Transfer.Transactions } else { @() }
    }

    $logPath = Join-Path $renderKitRoot ("{0}.log" -f $importRunId)
    $record | ConvertTo-Json -Depth 30 | Set-Content -Path $logPath -Encoding UTF8

    Write-RenderKitLog -Level Info -Message "Phase 5 revision log written: '$logPath'."
    return $logPath
}
