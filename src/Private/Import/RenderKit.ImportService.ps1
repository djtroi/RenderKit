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
