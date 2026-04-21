function ConvertTo-RenderKitInteractiveMenuText {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) {
        return "-"
    }

    if ($Value -is [bool]) {
        if ($Value) {
            return "Yes"
        }

        return "No"
    }

    if ($Value -is [datetime]) {
        return $Value.ToString("yyyy-MM-dd HH:mm:ss")
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $pairs = @()
        foreach ($key in $Value.Keys) {
            $pairs += ("{0}={1}" -f $key, (ConvertTo-RenderKitInteractiveMenuText -Value $Value[$key]))
        }

        if ($pairs.Count -gt 0) {
            return ($pairs -join "; ")
        }

        return "-"
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $items = @(
            $Value |
                ForEach-Object { [string]$_ } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )

        if ($items.Count -gt 0) {
            return ($items -join ", ")
        }

        return "<none>"
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return "-"
    }

    return $text.Trim()
}

function Get-RenderKitInteractiveMenuViewport {
    [CmdletBinding()]
    param()

    $width = 100
    $height = 30

    try {
        if ($host.UI -and $host.UI.RawUI) {
            $width = [Math]::Max([int]$host.UI.RawUI.WindowSize.Width, 80)
            $height = [Math]::Max([int]$host.UI.RawUI.WindowSize.Height, 24)
        }
    }
    catch {
        $width = 100
        $height = 30
    }

    return [PSCustomObject]@{
        Width  = $width
        Height = $height
    }
}

function Format-RenderKitInteractiveMenuLine {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [AllowEmptyString()]
        [string]$Text,
        [ValidateRange(1, 1000)]
        [int]$Width
    )

    $safeText = if ($null -eq $Text) { "" } else { $Text }
    $normalized = (($safeText) -replace "`r", " " -replace "`n", " ").Trim()
    if ($normalized.Length -gt $Width) {
        if ($Width -le 3) {
            return $normalized.Substring(0, $Width)
        }

        return $normalized.Substring(0, $Width - 3) + "..."
    }

    return $normalized.PadRight($Width)
}

function New-RenderKitInteractiveMenuOption {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,
        [Parameter(Mandatory)]
        [string]$Label,
        [string]$Description,
        $Value,
        [string]$HotKey,
        [bool]$IsDefault = $false,
        [bool]$IsEnabled = $true,
        [bool]$Selected = $false
    )

    $normalizedHotKey = $null
    if (-not [string]::IsNullOrWhiteSpace($HotKey)) {
        $normalizedHotKey = $HotKey.Substring(0, 1).ToUpperInvariant()
    }

    return [PSCustomObject]@{
        Key         = $Key
        Label       = $Label
        Description = $Description
        Value       = $Value
        HotKey      = $normalizedHotKey
        IsDefault   = [bool]$IsDefault
        IsEnabled   = [bool]$IsEnabled
        Selected    = [bool]$Selected
    }
}

function Get-RenderKitInteractiveMenuFirstEnabledIndex {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Options
    )

    for ($i = 0; $i -lt $Options.Count; $i++) {
        if ([bool]$Options[$i].IsEnabled) {
            return $i
        }
    }

    return -1
}

function Get-RenderKitInteractiveMenuLastEnabledIndex {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Options
    )

    for ($i = $Options.Count - 1; $i -ge 0; $i--) {
        if ([bool]$Options[$i].IsEnabled) {
            return $i
        }
    }

    return -1
}

function Find-RenderKitInteractiveMenuEnabledIndex {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Options,
        [int]$RequestedIndex,
        [bool]$SearchBackward = $false
    )

    if (-not $Options -or $Options.Count -eq 0) {
        return -1
    }

    if ($RequestedIndex -lt 0) {
        if ($SearchBackward) {
            return Get-RenderKitInteractiveMenuLastEnabledIndex -Options $Options
        }

        return Get-RenderKitInteractiveMenuFirstEnabledIndex -Options $Options
    }

    if ($RequestedIndex -ge $Options.Count) {
        if ($SearchBackward) {
            return Get-RenderKitInteractiveMenuLastEnabledIndex -Options $Options
        }

        return Get-RenderKitInteractiveMenuFirstEnabledIndex -Options $Options
    }

    if ([bool]$Options[$RequestedIndex].IsEnabled) {
        return $RequestedIndex
    }

    if ($SearchBackward) {
        for ($i = $RequestedIndex - 1; $i -ge 0; $i--) {
            if ([bool]$Options[$i].IsEnabled) {
                return $i
            }
        }

        for ($i = $RequestedIndex + 1; $i -lt $Options.Count; $i++) {
            if ([bool]$Options[$i].IsEnabled) {
                return $i
            }
        }
    }
    else {
        for ($i = $RequestedIndex + 1; $i -lt $Options.Count; $i++) {
            if ([bool]$Options[$i].IsEnabled) {
                return $i
            }
        }

        for ($i = $RequestedIndex - 1; $i -ge 0; $i--) {
            if ([bool]$Options[$i].IsEnabled) {
                return $i
            }
        }
    }

    return -1
}

function Write-RenderKitInteractiveMenuScreen {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,
        [string]$Subtitle,
        [string[]]$Breadcrumb,
        [hashtable]$Status,
        [string[]]$Info,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Options,
        [ValidateRange(-1, 100000)]
        [int]$SelectedIndex = 0,
        [switch]$AllowBack,
        [switch]$AllowCancel,
        [switch]$MultiSelect
    )

    $viewport = Get-RenderKitInteractiveMenuViewport
    $contentWidth = [Math]::Max(20, $viewport.Width - 4)

    $statusLines = @()
    if ($Status) {
        foreach ($key in $Status.Keys) {
            $statusLines += ("{0}: {1}" -f $key, (ConvertTo-RenderKitInteractiveMenuText -Value $Status[$key]))
        }
    }

    $infoLines = @($Info | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    $selectedDescriptionLines = @()
    if ($SelectedIndex -ge 0 -and $SelectedIndex -lt $Options.Count) {
        $selectedOption = $Options[$SelectedIndex]
        if (-not [string]::IsNullOrWhiteSpace([string]$selectedOption.Description)) {
            $selectedDescriptionLines = @(
                [string]$selectedOption.Description -split "(`r`n|`n|`r)" |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )
        }
    }

    $reservedLineCount = 8
    if (-not [string]::IsNullOrWhiteSpace($Subtitle)) { $reservedLineCount++ }
    if ($Breadcrumb -and $Breadcrumb.Count -gt 0) { $reservedLineCount++ }
    if ($statusLines.Count -gt 0) { $reservedLineCount += $statusLines.Count + 1 }
    if ($infoLines.Count -gt 0) { $reservedLineCount += $infoLines.Count + 1 }
    if ($selectedDescriptionLines.Count -gt 0) { $reservedLineCount += [Math]::Min($selectedDescriptionLines.Count, 4) + 1 }

    $pageSize = [Math]::Max(5, $viewport.Height - $reservedLineCount)
    if ($Options.Count -gt 0) {
        $pageSize = [Math]::Min($pageSize, $Options.Count)
    }

    $pageIndex = 0
    $pageCount = 1
    if ($Options.Count -gt 0 -and $pageSize -gt 0) {
        $pageIndex = [Math]::Floor($SelectedIndex / $pageSize)
        $pageCount = [Math]::Ceiling($Options.Count / [double]$pageSize)
    }

    $startIndex = if ($Options.Count -gt 0) { $pageIndex * $pageSize } else { 0 }
    $endIndex = if ($Options.Count -gt 0) {
        [Math]::Min(($startIndex + $pageSize - 1), ($Options.Count - 1))
    }
    else {
        -1
    }

    Clear-Host
    Write-Host ""
    Write-Host ("  " + (Format-RenderKitInteractiveMenuLine -Text $Title -Width $contentWidth))

    if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
        Write-Host ("  " + (Format-RenderKitInteractiveMenuLine -Text $Subtitle -Width $contentWidth))
    }

    if ($Breadcrumb -and $Breadcrumb.Count -gt 0) {
        $breadcrumbText = "Path: {0}" -f ($Breadcrumb -join " > ")
        Write-Host ("  " + (Format-RenderKitInteractiveMenuLine -Text $breadcrumbText -Width $contentWidth))
    }

    if ($statusLines.Count -gt 0) {
        Write-Host ""
        Write-Host "  Context"
        foreach ($line in $statusLines) {
            Write-Host ("  " + (Format-RenderKitInteractiveMenuLine -Text $line -Width $contentWidth))
        }
    }

    if ($infoLines.Count -gt 0) {
        Write-Host ""
        Write-Host "  Notes"
        foreach ($line in $infoLines) {
            Write-Host ("  " + (Format-RenderKitInteractiveMenuLine -Text $line -Width $contentWidth))
        }
    }

    Write-Host ""
    $actionHeader = if ($pageCount -gt 1) {
        "Actions (page {0}/{1})" -f ($pageIndex + 1), $pageCount
    }
    else {
        "Actions"
    }
    Write-Host ("  " + $actionHeader)

    if ($Options.Count -eq 0) {
        Write-Host ("  " + (Format-RenderKitInteractiveMenuLine -Text "No actions available." -Width $contentWidth)) -ForegroundColor DarkGray
    }
    else {
        for ($i = $startIndex; $i -le $endIndex; $i++) {
            $option = $Options[$i]
            $cursorPrefix = if ($i -eq $SelectedIndex) { ">" } else { " " }
            $selectionPrefix = if ($MultiSelect) {
                if ([bool]$option.Selected) { "[x] " } else { "[ ] " }
            }
            else {
                ""
            }

            $hotKeyText = if (-not [string]::IsNullOrWhiteSpace([string]$option.HotKey)) {
                "[{0}] " -f $option.HotKey
            }
            else {
                ""
            }

            $suffixText = if (-not [bool]$option.IsEnabled) { " (not available)" } else { "" }
            $lineText = "{0} {1}{2}{3}" -f $cursorPrefix, $selectionPrefix, $hotKeyText, $option.Label
            $lineText += $suffixText
            $formattedLine = "  " + (Format-RenderKitInteractiveMenuLine -Text $lineText -Width $contentWidth)

            if ($i -eq $SelectedIndex) {
                Write-Host $formattedLine -ForegroundColor Black -BackgroundColor Gray
            }
            elseif (-not [bool]$option.IsEnabled) {
                Write-Host $formattedLine -ForegroundColor DarkGray
            }
            else {
                Write-Host $formattedLine
            }
        }
    }

    if ($selectedDescriptionLines.Count -gt 0) {
        Write-Host ""
        Write-Host "  Details"
        foreach ($line in $selectedDescriptionLines | Select-Object -First 4) {
            Write-Host ("  " + (Format-RenderKitInteractiveMenuLine -Text $line -Width $contentWidth))
        }
    }

    Write-Host ""
    $controlSegments = @("[Up/Down] Move", "[Home/End] Jump", "[PageUp/PageDown] Page", "[Enter] Select")
    if ($MultiSelect) {
        $controlSegments += "[Space] Toggle"
        $controlSegments += "[Insert] All"
        $controlSegments += "[Delete] None"
    }

    if ($AllowBack) {
        $controlSegments += "[Esc] Back"
    }
    elseif ($AllowCancel) {
        $controlSegments += "[Esc] Cancel"
    }

    Write-Host ("  " + (Format-RenderKitInteractiveMenuLine -Text ("Controls: " + ($controlSegments -join " | ")) -Width $contentWidth))

    if ($MultiSelect) {
        $selectedCount = @($Options | Where-Object { [bool]$_.Selected }).Count
        Write-Host ("  " + (Format-RenderKitInteractiveMenuLine -Text ("Selected items: {0}" -f $selectedCount) -Width $contentWidth))
    }

    return [PSCustomObject]@{
        PageSize  = $pageSize
        PageIndex = $pageIndex
        PageCount = $pageCount
    }
}

function Invoke-RenderKitInteractiveMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,
        [string]$Subtitle,
        [string[]]$Breadcrumb,
        [hashtable]$Status,
        [string[]]$Info,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Options,
        [switch]$AllowBack,
        [switch]$AllowCancel,
        [switch]$MultiSelect,
        [switch]$AllowEmptySelection
    )

    if (-not $host.Name -or $host.Name -ne "ConsoleHost") {
        throw "Interactive menu service requires ConsoleHost."
    }

    $menuOptions = @($Options)
    $selectedIndex = Get-RenderKitInteractiveMenuFirstEnabledIndex -Options $menuOptions
    if ($selectedIndex -lt 0 -and $menuOptions.Count -gt 0) {
        $selectedIndex = 0
    }

    $defaultIndex = -1
    for ($i = 0; $i -lt $menuOptions.Count; $i++) {
        if ([bool]$menuOptions[$i].IsDefault -and [bool]$menuOptions[$i].IsEnabled) {
            $defaultIndex = $i
            break
        }
    }

    if ($defaultIndex -ge 0) {
        $selectedIndex = $defaultIndex
    }

    $cursorVisible = $true
    try {
        $cursorVisible = [System.Console]::CursorVisible
        [System.Console]::CursorVisible = $false

        while ($true) {
            $layout = Write-RenderKitInteractiveMenuScreen `
                -Title $Title `
                -Subtitle $Subtitle `
                -Breadcrumb $Breadcrumb `
                -Status $Status `
                -Info $Info `
                -Options $menuOptions `
                -SelectedIndex $selectedIndex `
                -AllowBack:$AllowBack `
                -AllowCancel:$AllowCancel `
                -MultiSelect:$MultiSelect

            $keyInfo = [System.Console]::ReadKey($true)
            switch ($keyInfo.Key) {
                "DownArrow" {
                    $nextIndex = Find-RenderKitInteractiveMenuEnabledIndex `
                        -Options $menuOptions `
                        -RequestedIndex ($selectedIndex + 1)
                    if ($nextIndex -ge 0) {
                        $selectedIndex = $nextIndex
                    }
                }
                "UpArrow" {
                    $previousIndex = Find-RenderKitInteractiveMenuEnabledIndex `
                        -Options $menuOptions `
                        -RequestedIndex ($selectedIndex - 1) `
                        -SearchBackward $true
                    if ($previousIndex -ge 0) {
                        $selectedIndex = $previousIndex
                    }
                }
                "Home" {
                    $firstIndex = Get-RenderKitInteractiveMenuFirstEnabledIndex -Options $menuOptions
                    if ($firstIndex -ge 0) {
                        $selectedIndex = $firstIndex
                    }
                }
                "End" {
                    $lastIndex = Get-RenderKitInteractiveMenuLastEnabledIndex -Options $menuOptions
                    if ($lastIndex -ge 0) {
                        $selectedIndex = $lastIndex
                    }
                }
                "PageDown" {
                    $targetIndex = [Math]::Min(($selectedIndex + $layout.PageSize), ($menuOptions.Count - 1))
                    $pageDownIndex = Find-RenderKitInteractiveMenuEnabledIndex `
                        -Options $menuOptions `
                        -RequestedIndex $targetIndex
                    if ($pageDownIndex -ge 0) {
                        $selectedIndex = $pageDownIndex
                    }
                }
                "PageUp" {
                    $targetIndex = [Math]::Max(($selectedIndex - $layout.PageSize), 0)
                    $pageUpIndex = Find-RenderKitInteractiveMenuEnabledIndex `
                        -Options $menuOptions `
                        -RequestedIndex $targetIndex `
                        -SearchBackward $true
                    if ($pageUpIndex -ge 0) {
                        $selectedIndex = $pageUpIndex
                    }
                }
                "Spacebar" {
                    if ($MultiSelect -and $selectedIndex -ge 0 -and [bool]$menuOptions[$selectedIndex].IsEnabled) {
                        $menuOptions[$selectedIndex].Selected = -not [bool]$menuOptions[$selectedIndex].Selected
                    }
                }
                "Insert" {
                    if ($MultiSelect) {
                        foreach ($option in $menuOptions) {
                            if ([bool]$option.IsEnabled) {
                                $option.Selected = $true
                            }
                        }
                    }
                }
                "Delete" {
                    if ($MultiSelect) {
                        foreach ($option in $menuOptions) {
                            $option.Selected = $false
                        }
                    }
                }
                "Enter" {
                    if ($MultiSelect) {
                        $selectedOptions = @($menuOptions | Where-Object { [bool]$_.Selected })
                        if ($selectedOptions.Count -eq 0 -and -not $AllowEmptySelection) {
                            continue
                        }

                        return [PSCustomObject]@{
                            Action          = "Select"
                            Option          = $null
                            SelectedOptions = $selectedOptions
                            SelectedValues  = @($selectedOptions | ForEach-Object { $_.Value })
                            SelectedIndex   = $selectedIndex
                        }
                    }

                    if ($selectedIndex -ge 0 -and $selectedIndex -lt $menuOptions.Count -and [bool]$menuOptions[$selectedIndex].IsEnabled) {
                        return [PSCustomObject]@{
                            Action          = "Select"
                            Option          = $menuOptions[$selectedIndex]
                            Value           = $menuOptions[$selectedIndex].Value
                            SelectedOptions = @($menuOptions[$selectedIndex])
                            SelectedValues  = @($menuOptions[$selectedIndex].Value)
                            SelectedIndex   = $selectedIndex
                        }
                    }
                }
                "Escape" {
                    if ($AllowBack) {
                        return [PSCustomObject]@{
                            Action          = "Back"
                            Option          = $null
                            SelectedOptions = @()
                            SelectedValues  = @()
                            SelectedIndex   = $selectedIndex
                        }
                    }

                    if ($AllowCancel) {
                        return [PSCustomObject]@{
                            Action          = "Cancel"
                            Option          = $null
                            SelectedOptions = @()
                            SelectedValues  = @()
                            SelectedIndex   = $selectedIndex
                        }
                    }
                }
                "Backspace" {
                    if ($AllowBack) {
                        return [PSCustomObject]@{
                            Action          = "Back"
                            Option          = $null
                            SelectedOptions = @()
                            SelectedValues  = @()
                            SelectedIndex   = $selectedIndex
                        }
                    }
                }
                default {
                    $pressedChar = [string]$keyInfo.KeyChar
                    if (-not [string]::IsNullOrWhiteSpace($pressedChar)) {
                        $hotKey = $pressedChar.Substring(0, 1).ToUpperInvariant()
                        $hotKeyMatch = @(
                            $menuOptions |
                                Where-Object {
                                    [bool]$_.IsEnabled -and
                                    -not [string]::IsNullOrWhiteSpace([string]$_.HotKey) -and
                                    [string]$_.HotKey -eq $hotKey
                                }
                        )

                        if ($hotKeyMatch.Count -gt 0) {
                            $match = $hotKeyMatch[0]
                            for ($i = 0; $i -lt $menuOptions.Count; $i++) {
                                if ($menuOptions[$i].Key -eq $match.Key) {
                                    $selectedIndex = $i
                                    break
                                }
                            }

                            if ($MultiSelect) {
                                $match.Selected = -not [bool]$match.Selected
                            }
                            else {
                                return [PSCustomObject]@{
                                    Action          = "Select"
                                    Option          = $match
                                    Value           = $match.Value
                                    SelectedOptions = @($match)
                                    SelectedValues  = @($match.Value)
                                    SelectedIndex   = $selectedIndex
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    finally {
        [System.Console]::CursorVisible = $cursorVisible
    }
}

function Read-RenderKitInteractiveMenuTextInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,
        [string]$Subtitle,
        [string[]]$Breadcrumb,
        [hashtable]$Status,
        [string[]]$Info,
        [Parameter(Mandatory)]
        [string]$Prompt,
        [string]$CurrentValue
    )

    $viewport = Get-RenderKitInteractiveMenuViewport
    $contentWidth = [Math]::Max(20, $viewport.Width - 4)

    Clear-Host
    Write-Host ""
    Write-Host ("  " + (Format-RenderKitInteractiveMenuLine -Text $Title -Width $contentWidth))

    if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
        Write-Host ("  " + (Format-RenderKitInteractiveMenuLine -Text $Subtitle -Width $contentWidth))
    }

    if ($Breadcrumb -and $Breadcrumb.Count -gt 0) {
        Write-Host ("  " + (Format-RenderKitInteractiveMenuLine -Text ("Path: {0}" -f ($Breadcrumb -join " > ")) -Width $contentWidth))
    }

    if ($Status) {
        Write-Host ""
        Write-Host "  Context"
        foreach ($key in $Status.Keys) {
            $line = "{0}: {1}" -f $key, (ConvertTo-RenderKitInteractiveMenuText -Value $Status[$key])
            Write-Host ("  " + (Format-RenderKitInteractiveMenuLine -Text $line -Width $contentWidth))
        }
    }

    Write-Host ""
    Write-Host "  Notes"
    foreach ($line in @($Info) + @("Press Enter on empty input to go back.")) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            Write-Host ("  " + (Format-RenderKitInteractiveMenuLine -Text $line -Width $contentWidth))
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
        Write-Host ""
        Write-Host ("  Current: " + (Format-RenderKitInteractiveMenuLine -Text $CurrentValue -Width ([Math]::Max(10, $contentWidth - 9))))
    }

    Write-Host ""
    $inputValue = Read-Host $Prompt
    if ([string]::IsNullOrWhiteSpace($inputValue)) {
        return [PSCustomObject]@{
            Action = "Back"
            Value  = $null
        }
    }

    return [PSCustomObject]@{
        Action = "Submit"
        Value  = $inputValue.Trim()
    }
}

function Select-RenderKitImportProjectRootMenu {
    [CmdletBinding()]
    param()

    $projects = @(Get-RenderKitImportProjectCandidate)
    $infoLines = @(
        "Choose a known project or enter an absolute project path manually.",
        "Esc returns to the previous menu without changing the current selection."
    )

    while ($true) {
        $options = New-Object System.Collections.Generic.List[object]
        for ($i = 0; $i -lt $projects.Count; $i++) {
            $project = $projects[$i]
            $description = "Template: {0} | Path: {1}" -f `
                (ConvertTo-RenderKitInteractiveMenuText -Value $project.Template), `
                (ConvertTo-RenderKitInteractiveMenuText -Value $project.ProjectRoot)

            $options.Add((New-RenderKitInteractiveMenuOption `
                    -Key ("project-{0}" -f $i) `
                    -Label ([string]$project.Name) `
                    -Description $description `
                    -Value $project.ProjectRoot `
                    -IsDefault:($i -eq 0)))
        }

        $options.Add((New-RenderKitInteractiveMenuOption `
                -Key "manual-path" `
                -Label "Enter project path manually" `
                -Description "Use a specific project root that is not in the detected list." `
                -HotKey "M"))
        $options.Add((New-RenderKitInteractiveMenuOption `
                -Key "refresh" `
                -Label "Refresh detected projects" `
                -Description "Scan the default project location again." `
                -HotKey "R"))

        $menuResult = Invoke-RenderKitInteractiveMenu `
            -Title "Import destination project" `
            -Subtitle "RenderKit import setup" `
            -Breadcrumb @("Import Media", "Setup", "Project") `
            -Status ([ordered]@{
                    DetectedProjects = $projects.Count
                }) `
            -Info $infoLines `
            -Options $options.ToArray() `
            -AllowBack

        if ($menuResult.Action -eq "Back") {
            return $null
        }

        switch ($menuResult.Option.Key) {
            "manual-path" {
                while ($true) {
                    $inputResult = Read-RenderKitInteractiveMenuTextInput `
                        -Title "Manual project path" `
                        -Subtitle "Enter an absolute RenderKit project root." `
                        -Breadcrumb @("Import Media", "Setup", "Project", "Manual Path") `
                        -Status ([ordered]@{
                                DetectedProjects = $projects.Count
                            }) `
                        -Info @(
                            "The path must point to an existing RenderKit project root."
                        ) `
                        -Prompt "Project root path" `
                        -CurrentValue $null

                    if ($inputResult.Action -eq "Back") {
                        break
                    }

                    try {
                        return Resolve-RenderKitImportProjectRoot -ProjectRoot $inputResult.Value
                    }
                    catch {
                        $projects = @(Get-RenderKitImportProjectCandidate)
                        $infoLines = @(
                            "Last input was invalid: $($_.Exception.Message)",
                            "Choose a known project or enter an absolute project path manually.",
                            "Esc returns to the previous menu without changing the current selection."
                        )
                    }
                }
            }
            "refresh" {
                $projects = @(Get-RenderKitImportProjectCandidate)
                $infoLines = @(
                    "Detected project list refreshed.",
                    "Choose a known project or enter an absolute project path manually.",
                    "Esc returns to the previous menu without changing the current selection."
                )
            }
            default {
                return [string]$menuResult.Option.Value
            }
        }
    }
}

function Select-RenderKitDriveCandidateMenu {
    [CmdletBinding()]
    [OutputType([System.Object])]
    param(
        [switch]$IncludeFixed,
        [switch]$IncludeUnsupportedFileSystem
    )

    $infoLines = @()
    while ($true) {
        $candidates = @(Get-RenderKitDriveCandidate `
            -IncludeFixed:$IncludeFixed `
            -IncludeUnsupportedFileSystem:$IncludeUnsupportedFileSystem `
            -DisableInteractiveFallback)

        if ($candidates.Count -eq 0) {
            $options = @(
                New-RenderKitInteractiveMenuOption `
                    -Key "refresh" `
                    -Label "Refresh drive scan" `
                    -Description "Scan again for removable and allowed source drives." `
                    -HotKey "R"
            )

            $result = Invoke-RenderKitInteractiveMenu `
                -Title "Source drive selection" `
                -Subtitle "No drive candidates detected" `
                -Breadcrumb @("Import Media", "Setup", "Source", "Drives") `
                -Status ([ordered]@{
                        IncludeFixed             = [bool]$IncludeFixed
                        IncludeUnsupportedFS     = [bool]$IncludeUnsupportedFileSystem
                        CandidateCount           = 0
                    }) `
                -Info (@(
                        "No matching drive candidates are available right now.",
                        "Refresh after reconnecting a source device."
                    ) + $infoLines) `
                -Options $options `
                -AllowBack

            if ($result.Action -eq "Back") {
                return $null
            }

            $infoLines = @("Drive scan refreshed.")
            continue
        }

        $driveOptions = New-Object System.Collections.Generic.List[object]
        for ($i = 0; $i -lt $candidates.Count; $i++) {
            $candidate = $candidates[$i]
            $volumeName = ConvertTo-RenderKitInteractiveMenuText -Value $candidate.VolumeName
            $description = "Drive: {0} | FileSystem: {1} | Score: {2} | Whitelisted: {3}" -f `
                (ConvertTo-RenderKitInteractiveMenuText -Value $candidate.DriveLetter), `
                (ConvertTo-RenderKitInteractiveMenuText -Value $candidate.FileSystem), `
                (ConvertTo-RenderKitInteractiveMenuText -Value $candidate.Score), `
                (ConvertTo-RenderKitInteractiveMenuText -Value ($candidate.IsWhitelistedVolumeName -or $candidate.IsWhitelistedSerialNumber))

            $driveOptions.Add((New-RenderKitInteractiveMenuOption `
                    -Key ("drive-{0}" -f $i) `
                    -Label ("{0} ({1})" -f $candidate.DriveLetter, $volumeName) `
                    -Description $description `
                    -Value $candidate `
                    -IsDefault:($i -eq 0)))
        }

        $driveOptions.Add((New-RenderKitInteractiveMenuOption `
                -Key "whitelist" `
                -Label "Whitelist a detected drive first" `
                -Description "Add a drive to the whitelist before selecting it as the source." `
                -HotKey "W"))
        $driveOptions.Add((New-RenderKitInteractiveMenuOption `
                -Key "refresh" `
                -Label "Refresh drive scan" `
                -Description "Scan again for available drive candidates." `
                -HotKey "R"))

        $selection = Invoke-RenderKitInteractiveMenu `
            -Title "Source drive selection" `
            -Subtitle "Choose the device that contains the source media." `
            -Breadcrumb @("Import Media", "Setup", "Source", "Drives") `
            -Status ([ordered]@{
                    IncludeFixed         = [bool]$IncludeFixed
                    IncludeUnsupportedFS = [bool]$IncludeUnsupportedFileSystem
                    CandidateCount       = $candidates.Count
                }) `
            -Info (@(
                    "Select a drive to continue browsing for the source folder.",
                    "Esc returns to the previous menu."
                ) + $infoLines) `
            -Options $driveOptions.ToArray() `
            -AllowBack

        if ($selection.Action -eq "Back") {
            return $null
        }

        switch ($selection.Option.Key) {
            "refresh" {
                $infoLines = @("Drive scan refreshed.")
                continue
            }
            "whitelist" {
                $target = Invoke-RenderKitInteractiveMenu `
                    -Title "Whitelist drive" `
                    -Subtitle "Choose which detected drive should be added to the whitelist." `
                    -Breadcrumb @("Import Media", "Setup", "Source", "Drives", "Whitelist") `
                    -Status ([ordered]@{
                            CandidateCount = $candidates.Count
                        }) `
                    -Info @(
                        "Esc returns to the previous drive list without changing the whitelist."
                    ) `
                    -Options ($driveOptions.ToArray() | Where-Object { $_.Key -like "drive-*" }) `
                    -AllowBack

                if ($target.Action -eq "Back") {
                    continue
                }

                $selectedDrive = $target.Option.Value
                Add-RenderKitDeviceWhitelistEntry -DriveLetter $selectedDrive.DriveLetter -Confirm:$false | Out-Null
                $useWhitelistedNow = Read-RenderKitImportBooleanMenu `
                    -Title "Drive whitelisted" `
                    -Prompt ("Use '{0}' as the source drive now?" -f $selectedDrive.DriveLetter) `
                    -Default $true `
                    -Breadcrumb @("Import Media", "Setup", "Source", "Drives", "Whitelist")

                if ($useWhitelistedNow) {
                    return $selectedDrive
                }

                $infoLines = @("Drive '{0}' was added to the whitelist." -f $selectedDrive.DriveLetter)
                continue
            }
            default {
                return $selection.Option.Value
            }
        }
    }
}

function Select-RenderKitImportFolderFilterMenu {
    [CmdletBinding()]
    [OutputType([System.String[]])]
    param(
        [Parameter(Mandatory)]
        [string]$ParentPath
    )

    $children = @(Get-RenderKitImportChildDirectory -Path $ParentPath)
    if ($children.Count -eq 0) {
        return $null
    }

    $options = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $children.Count; $i++) {
        $child = $children[$i]
        $options.Add((New-RenderKitInteractiveMenuOption `
                -Key ("child-{0}" -f $i) `
                -Label ([string]$child.Name) `
                -Description ([string]$child.FullName) `
                -Value $child.Name))
    }

    $result = Invoke-RenderKitInteractiveMenu `
        -Title "Direct subfolder filter" `
        -Subtitle "Choose one or more direct subfolders that should be imported." `
        -Breadcrumb @("Import Media", "Setup", "Source", "Folder Filter") `
        -Status ([ordered]@{
                ParentPath       = $ParentPath
                DirectSubfolders = $children.Count
            }) `
        -Info @(
            "Use Space to toggle folders, then Enter to confirm the filter.",
            "Esc returns without applying a subfolder filter."
        ) `
        -Options $options.ToArray() `
        -AllowBack `
        -MultiSelect

    if ($result.Action -eq "Back") {
        return $null
    }

    return @(
        $result.SelectedValues |
            ForEach-Object { [System.Management.Automation.WildcardPattern]::Escape([string]$_) } |
            Sort-Object -Unique
    )
}

function Select-RenderKitImportSourceFolderActionMenu {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [string]$SelectedPath
    )

    $children = @(Get-RenderKitImportChildDirectory -Path $SelectedPath)
    $menuResult = Invoke-RenderKitInteractiveMenu `
        -Title "Selected source folder" `
        -Subtitle "Choose how RenderKit should use this folder." `
        -Breadcrumb @("Import Media", "Setup", "Source", "Folder Action") `
        -Status ([ordered]@{
                SelectedPath     = $SelectedPath
                DirectSubfolders = $children.Count
            }) `
        -Info @(
            "Use the folder directly, browse deeper, or limit the import to selected direct subfolders."
        ) `
        -Options @(
            New-RenderKitInteractiveMenuOption `
                -Key "use-folder" `
                -Label "Use this folder as the source root" `
                -Description "Scan the selected folder and its content as the source root." `
                -HotKey "U",
            New-RenderKitInteractiveMenuOption `
                -Key "browse-deeper" `
                -Label "Browse deeper into this folder" `
                -Description "Open this folder and continue navigating its subfolders." `
                -HotKey "B",
            New-RenderKitInteractiveMenuOption `
                -Key "filter-direct-children" `
                -Label "Only import selected direct subfolders" `
                -Description "Choose one or more direct child folders as a filter for this source path." `
                -HotKey "F" `
                -IsEnabled:($children.Count -gt 0)
        ) `
        -AllowBack

    if ($menuResult.Action -eq "Back") {
        return $null
    }

    return [string]$menuResult.Option.Key
}

function Select-RenderKitImportSourceBrowserMenu {
    [CmdletBinding()]
    [OutputType([System.Object])]
    param(
        [Parameter(Mandatory)]
        [object]$SelectedDrive,
        [switch]$IncludeFixed,
        [switch]$IncludeUnsupportedFileSystem
    )

    $driveRoot = ConvertTo-RenderKitImportDrivePath -DriveLetter $SelectedDrive.DriveLetter
    $browseRoot = $driveRoot
    $infoLines = @()

    while ($true) {
        $children = @(Get-RenderKitImportChildDirectory -Path $browseRoot)
        $isAtDriveRoot = [string]::Equals(
            [string]$browseRoot.TrimEnd('\'),
            [string]$driveRoot.TrimEnd('\'),
            [System.StringComparison]::OrdinalIgnoreCase
        )

        $options = New-Object System.Collections.Generic.List[object]
        $options.Add((New-RenderKitInteractiveMenuOption `
                -Key "use-current" `
                -Label "Use current folder as source" `
                -Description "Select the currently visible folder as the source root." `
                -HotKey "U" `
                -IsDefault $true))
        $options.Add((New-RenderKitInteractiveMenuOption `
                -Key "enter-path" `
                -Label "Enter relative or absolute path" `
                -Description "Jump directly to a path or browse to it manually." `
                -HotKey "P"))
        $options.Add((New-RenderKitInteractiveMenuOption `
                -Key "go-up" `
                -Label "Go up one level" `
                -Description "Move to the parent folder." `
                -HotKey "G" `
                -IsEnabled:(-not $isAtDriveRoot)))

        for ($i = 0; $i -lt $children.Count; $i++) {
            $child = $children[$i]
            $options.Add((New-RenderKitInteractiveMenuOption `
                    -Key ("browse-{0}" -f $i) `
                    -Label ([string]$child.Name) `
                    -Description ([string]$child.FullName) `
                    -Value $child.FullName))
        }

        $menuResult = Invoke-RenderKitInteractiveMenu `
            -Title "Browse source folder" `
            -Subtitle "Choose where the import scan should begin." `
            -Breadcrumb @("Import Media", "Setup", "Source", ([string]$SelectedDrive.DriveLetter).TrimEnd('\')) `
            -Status ([ordered]@{
                    Drive              = $SelectedDrive.DriveLetter
                    CurrentFolder      = $browseRoot
                    DirectSubfolders   = $children.Count
                    IncludeFixed       = [bool]$IncludeFixed
                    IncludeUnsupported = [bool]$IncludeUnsupportedFileSystem
                }) `
            -Info (@(
                    "Select a subfolder to decide whether to browse deeper or use it directly.",
                    "Esc returns to drive selection."
                ) + $infoLines) `
            -Options $options.ToArray() `
            -AllowBack

        if ($menuResult.Action -eq "Back") {
            return $null
        }

        switch ($menuResult.Option.Key) {
            "use-current" {
                return [PSCustomObject]@{
                    SourcePath                   = $browseRoot
                    FolderFilter                 = @()
                    IncludeFixed                 = [bool]$IncludeFixed
                    IncludeUnsupportedFileSystem = [bool]$IncludeUnsupportedFileSystem
                    SelectedDrive                = $SelectedDrive
                }
            }
            "enter-path" {
                while ($true) {
                    $inputResult = Read-RenderKitInteractiveMenuTextInput `
                        -Title "Browse source folder" `
                        -Subtitle "Enter a relative path from the current folder or an absolute path." `
                        -Breadcrumb @("Import Media", "Setup", "Source", ([string]$SelectedDrive.DriveLetter).TrimEnd('\'), "Manual Path") `
                        -Status ([ordered]@{
                                CurrentFolder = $browseRoot
                            }) `
                        -Info @(
                            "Example relative path: DCIM\\100EOSR",
                            "Example absolute path: E:\\DCIM"
                        ) `
                        -Prompt "Path" `
                        -CurrentValue $null

                    if ($inputResult.Action -eq "Back") {
                        break
                    }

                    $candidatePath = if ([System.IO.Path]::IsPathRooted($inputResult.Value)) {
                        $inputResult.Value
                    }
                    else {
                        Join-Path $browseRoot $inputResult.Value
                    }

                    try {
                        $resolvedPath = (Resolve-Path -Path $candidatePath -ErrorAction Stop).ProviderPath
                    }
                    catch {
                        $infoLines = @("Path '{0}' was not found." -f $candidatePath)
                        continue
                    }

                    if (-not (Test-Path -Path $resolvedPath -PathType Container)) {
                        $infoLines = @("Path '{0}' is not a directory." -f $resolvedPath)
                        continue
                    }

                    $browseRoot = $resolvedPath
                    $infoLines = @("Moved to '{0}'." -f $browseRoot)
                    break
                }
            }
            "go-up" {
                $parentPath = Split-Path -Path $browseRoot -Parent
                if ([string]::IsNullOrWhiteSpace($parentPath)) {
                    $browseRoot = $driveRoot
                }
                else {
                    $browseRoot = $parentPath
                }
                $infoLines = @()
            }
            default {
                $selectedPath = [string]$menuResult.Option.Value
                $folderAction = Select-RenderKitImportSourceFolderActionMenu -SelectedPath $selectedPath
                if ([string]::IsNullOrWhiteSpace($folderAction)) {
                    $infoLines = @()
                    continue
                }

                switch ($folderAction) {
                    "use-folder" {
                        return [PSCustomObject]@{
                            SourcePath                   = $selectedPath
                            FolderFilter                 = @()
                            IncludeFixed                 = [bool]$IncludeFixed
                            IncludeUnsupportedFileSystem = [bool]$IncludeUnsupportedFileSystem
                            SelectedDrive                = $SelectedDrive
                        }
                    }
                    "browse-deeper" {
                        $browseRoot = $selectedPath
                        $infoLines = @("Browsing deeper in '{0}'." -f $selectedPath)
                    }
                    "filter-direct-children" {
                        $folderFilter = Select-RenderKitImportFolderFilterMenu -ParentPath $selectedPath
                        if ($null -eq $folderFilter -or $folderFilter.Count -eq 0) {
                            $infoLines = @("No direct subfolder filter was selected for '{0}'." -f $selectedPath)
                            continue
                        }

                        return [PSCustomObject]@{
                            SourcePath                   = $selectedPath
                            FolderFilter                 = @($folderFilter)
                            IncludeFixed                 = [bool]$IncludeFixed
                            IncludeUnsupportedFileSystem = [bool]$IncludeUnsupportedFileSystem
                            SelectedDrive                = $SelectedDrive
                        }
                    }
                }
            }
        }
    }
}

function Select-RenderKitImportSourcePathMenu {
    [CmdletBinding()]
    param(
        [switch]$IncludeFixed,
        [switch]$IncludeUnsupportedFileSystem
    )

    $effectiveIncludeFixed = if ($PSBoundParameters.ContainsKey("IncludeFixed")) {
        [bool]$IncludeFixed
    }
    else {
        $true
    }

    $effectiveIncludeUnsupported = if ($PSBoundParameters.ContainsKey("IncludeUnsupportedFileSystem")) {
        [bool]$IncludeUnsupportedFileSystem
    }
    else {
        $false
    }

    $infoLines = @()
    while ($true) {
        $menuResult = Invoke-RenderKitInteractiveMenu `
            -Title "Import source" `
            -Subtitle "Choose where the media scan should start." `
            -Breadcrumb @("Import Media", "Setup", "Source") `
            -Status ([ordered]@{
                    IncludeFixed         = $effectiveIncludeFixed
                    IncludeUnsupportedFS = $effectiveIncludeUnsupported
                }) `
            -Info (@(
                    "Pick a drive and browse folders, or jump directly to a manual path.",
                    "Esc returns to the previous setup menu."
                ) + $infoLines) `
            -Options @(
                New-RenderKitInteractiveMenuOption `
                    -Key "choose-drive" `
                    -Label "Choose source drive" `
                    -Description "Show matching drive candidates and browse the selected device." `
                    -HotKey "D" `
                    -IsDefault $true,
                New-RenderKitInteractiveMenuOption `
                    -Key "manual-path" `
                    -Label "Enter absolute source path manually" `
                    -Description "Use a specific folder path without choosing a drive first." `
                    -HotKey "M",
                New-RenderKitInteractiveMenuOption `
                    -Key "toggle-fixed" `
                    -Label ("Include fixed drives: {0}" -f (ConvertTo-RenderKitInteractiveMenuText -Value $effectiveIncludeFixed)) `
                    -Description "Toggle whether fixed disks should appear in the drive candidate list." `
                    -HotKey "F",
                New-RenderKitInteractiveMenuOption `
                    -Key "toggle-unsupported" `
                    -Label ("Include unsupported file systems: {0}" -f (ConvertTo-RenderKitInteractiveMenuText -Value $effectiveIncludeUnsupported)) `
                    -Description "Toggle whether drives with unsupported file systems should be listed." `
                    -HotKey "U"
            ) `
            -AllowBack

        if ($menuResult.Action -eq "Back") {
            return $null
        }

        switch ($menuResult.Option.Key) {
            "toggle-fixed" {
                $effectiveIncludeFixed = -not $effectiveIncludeFixed
                $infoLines = @("Include fixed drives is now '{0}'." -f (ConvertTo-RenderKitInteractiveMenuText -Value $effectiveIncludeFixed))
            }
            "toggle-unsupported" {
                $effectiveIncludeUnsupported = -not $effectiveIncludeUnsupported
                $infoLines = @("Include unsupported file systems is now '{0}'." -f (ConvertTo-RenderKitInteractiveMenuText -Value $effectiveIncludeUnsupported))
            }
            "manual-path" {
                while ($true) {
                    $inputResult = Read-RenderKitInteractiveMenuTextInput `
                        -Title "Manual source path" `
                        -Subtitle "Enter an absolute folder path that contains the source media." `
                        -Breadcrumb @("Import Media", "Setup", "Source", "Manual Path") `
                        -Status ([ordered]@{
                                IncludeFixed         = $effectiveIncludeFixed
                                IncludeUnsupportedFS = $effectiveIncludeUnsupported
                            }) `
                        -Info @(
                            "The path must exist and must be a directory."
                        ) `
                        -Prompt "Source folder path" `
                        -CurrentValue $null

                    if ($inputResult.Action -eq "Back") {
                        break
                    }

                    try {
                        $resolvedPath = (Resolve-Path -Path $inputResult.Value -ErrorAction Stop).ProviderPath
                    }
                    catch {
                        $infoLines = @("Source path '{0}' was not found." -f $inputResult.Value)
                        continue
                    }

                    if (-not (Test-Path -Path $resolvedPath -PathType Container)) {
                        $infoLines = @("Source path '{0}' is not a directory." -f $resolvedPath)
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
            "choose-drive" {
                $selectedDrive = Select-RenderKitDriveCandidateMenu `
                    -IncludeFixed:$effectiveIncludeFixed `
                    -IncludeUnsupportedFileSystem:$effectiveIncludeUnsupported

                if (-not $selectedDrive) {
                    $infoLines = @()
                    continue
                }

                $selectedSource = Select-RenderKitImportSourceBrowserMenu `
                    -SelectedDrive $selectedDrive `
                    -IncludeFixed:$effectiveIncludeFixed `
                    -IncludeUnsupportedFileSystem:$effectiveIncludeUnsupported

                if ($selectedSource) {
                    return $selectedSource
                }

                $infoLines = @("Drive selection kept, but no folder was chosen yet.")
            }
        }
    }
}

function Select-RenderKitImportUnassignedHandlingMenu {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [ValidateSet("Prompt", "ToSort", "Skip")]
        [string]$Default = "Prompt",
        [switch]$AllowBack
    )

    $result = Invoke-RenderKitInteractiveMenu `
        -Title "Unassigned file handling" `
        -Subtitle "Choose what should happen when RenderKit cannot map a file automatically." `
        -Breadcrumb @("Import Media", "Setup", "Unassigned Files") `
        -Status ([ordered]@{
                Default = $Default
            }) `
        -Info @(
            "Prompt lets you decide case by case during classification.",
            "TO SORT sends unassigned files to the fallback folder.",
            "Skip leaves unassigned files out of the import."
        ) `
        -Options @(
            New-RenderKitInteractiveMenuOption `
                -Key "Prompt" `
                -Label "Prompt during classification" `
                -Description "Ask interactively whenever an unassigned file type appears." `
                -HotKey "P" `
                -IsDefault:($Default -eq "Prompt"),
            New-RenderKitInteractiveMenuOption `
                -Key "ToSort" `
                -Label "Send to TO SORT" `
                -Description "Route unassigned files to the TO SORT folder automatically." `
                -HotKey "T" `
                -IsDefault:($Default -eq "ToSort"),
            New-RenderKitInteractiveMenuOption `
                -Key "Skip" `
                -Label "Skip unassigned files" `
                -Description "Do not classify or transfer files that cannot be mapped." `
                -HotKey "S" `
                -IsDefault:($Default -eq "Skip")
        ) `
        -AllowBack:$AllowBack

    if ($result.Action -eq "Back") {
        return $null
    }

    return [string]$result.Option.Key
}

function Start-RenderKitImportInteractiveSetupMenu {
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

    $resolvedProjectRoot = $null
    if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
        $resolvedProjectRoot = Resolve-RenderKitImportProjectRoot -ProjectRoot $ProjectRoot
    }

    $state = [ordered]@{
        ProjectRoot                 = $resolvedProjectRoot
        SourcePath                  = $null
        FolderFilter                = @()
        IncludeFixed                = if ($PSBoundParameters.ContainsKey("IncludeFixed")) { [bool]$IncludeFixed } else { $true }
        IncludeUnsupportedFileSystem = if ($PSBoundParameters.ContainsKey("IncludeUnsupportedFileSystem")) { [bool]$IncludeUnsupportedFileSystem } else { $false }
        InteractiveFilter           = $false
        AutoSelectAll               = $false
        AutoConfirm                 = $false
        UnassignedHandling          = $UnassignedHandling
        Classify                    = $true
        Transfer                    = $true
    }

    $infoLines = @(
        "This setup menu keeps the current import context visible at all times.",
        "Open an item to change it. Esc cancels the whole wizard."
    )

    while ($true) {
        $canStartImport = `
            (-not [string]::IsNullOrWhiteSpace([string]$state.ProjectRoot)) -and `
            (-not [string]::IsNullOrWhiteSpace([string]$state.SourcePath))

        $transferLabel = if ($state.Classify) {
            "Ask about transfer after classification: {0}" -f (ConvertTo-RenderKitInteractiveMenuText -Value $state.Transfer)
        }
        else {
            "Ask about transfer after classification: No"
        }

        $menuResult = Invoke-RenderKitInteractiveMenu `
            -Title "Import-Media setup" `
            -Subtitle "Configure the import before scanning the source." `
            -Breadcrumb @("Import Media", "Setup") `
            -Status ([ordered]@{
                    ProjectRoot                  = $state.ProjectRoot
                    SourcePath                   = $state.SourcePath
                    SourceFolderFilter           = if ($state.FolderFilter.Count -gt 0) { $state.FolderFilter } else { "<none>" }
                    IncludeFixed                 = $state.IncludeFixed
                    IncludeUnsupportedFileSystem = $state.IncludeUnsupportedFileSystem
                    InteractiveFilter            = $state.InteractiveFilter
                    AutoSelectAll                = $state.AutoSelectAll
                    AutoConfirm                  = $state.AutoConfirm
                    Classify                     = $state.Classify
                    AskForTransfer               = if ($state.Classify) { $state.Transfer } else { $false }
                    UnassignedHandling           = $state.UnassignedHandling
                }) `
            -Info $infoLines `
            -Options @(
                New-RenderKitInteractiveMenuOption `
                    -Key "project" `
                    -Label "Choose destination project" `
                    -Description "Select the RenderKit project that will receive the import." `
                    -HotKey "P" `
                    -IsDefault:([string]::IsNullOrWhiteSpace([string]$state.ProjectRoot)),
                New-RenderKitInteractiveMenuOption `
                    -Key "source" `
                    -Label "Choose source folder" `
                    -Description "Select the source drive and folder that should be scanned." `
                    -HotKey "S",
                New-RenderKitInteractiveMenuOption `
                    -Key "interactive-filter" `
                    -Label ("Configure additional filters after scan: {0}" -f (ConvertTo-RenderKitInteractiveMenuText -Value $state.InteractiveFilter)) `
                    -Description "When enabled, a dedicated filter menu appears after the scan and before file selection." `
                    -HotKey "F",
                New-RenderKitInteractiveMenuOption `
                    -Key "auto-select" `
                    -Label ("Auto-select all matched files: {0}" -f (ConvertTo-RenderKitInteractiveMenuText -Value $state.AutoSelectAll)) `
                    -Description "Skip the manual file subset menu and keep all matched files selected." `
                    -HotKey "A",
                New-RenderKitInteractiveMenuOption `
                    -Key "auto-confirm" `
                    -Label ("Auto-confirm import after selection: {0}" -f (ConvertTo-RenderKitInteractiveMenuText -Value $state.AutoConfirm)) `
                    -Description "Skip the final confirmation prompt before classification/import." `
                    -HotKey "C",
                New-RenderKitInteractiveMenuOption `
                    -Key "unassigned" `
                    -Label ("Unassigned files: {0}" -f $state.UnassignedHandling) `
                    -Description "Define what should happen when a file type has no mapping." `
                    -HotKey "U",
                New-RenderKitInteractiveMenuOption `
                    -Key "classify" `
                    -Label ("Run classification phase: {0}" -f (ConvertTo-RenderKitInteractiveMenuText -Value $state.Classify)) `
                    -Description "Classification assigns files to RenderKit destination folders before transfer." `
                    -HotKey "L",
                New-RenderKitInteractiveMenuOption `
                    -Key "transfer" `
                    -Label $transferLabel `
                    -Description "If enabled, RenderKit will ask whether the final transfer should be real or simulated." `
                    -HotKey "T" `
                    -IsEnabled:$state.Classify,
                New-RenderKitInteractiveMenuOption `
                    -Key "start" `
                    -Label "Start import with this setup" `
                    -Description "Begin scanning the source with the currently visible settings." `
                    -HotKey "I" `
                    -IsEnabled:$canStartImport
            ) `
            -AllowCancel

        if ($menuResult.Action -eq "Cancel") {
            return $null
        }

        switch ($menuResult.Option.Key) {
            "project" {
                $selectedProject = Select-RenderKitImportProjectRootMenu
                if (-not [string]::IsNullOrWhiteSpace($selectedProject)) {
                    $state.ProjectRoot = $selectedProject
                    $infoLines = @("Destination project updated.")
                }
                else {
                    $infoLines = @("Destination project unchanged.")
                }
            }
            "source" {
                $sourceSelection = Select-RenderKitImportSourcePathMenu `
                    -IncludeFixed:$state.IncludeFixed `
                    -IncludeUnsupportedFileSystem:$state.IncludeUnsupportedFileSystem

                if ($sourceSelection) {
                    $state.SourcePath = [string]$sourceSelection.SourcePath
                    $state.FolderFilter = @($sourceSelection.FolderFilter)
                    $state.IncludeFixed = [bool]$sourceSelection.IncludeFixed
                    $state.IncludeUnsupportedFileSystem = [bool]$sourceSelection.IncludeUnsupportedFileSystem
                    $infoLines = @("Source folder updated.")
                }
                else {
                    $infoLines = @("Source folder unchanged.")
                }
            }
            "interactive-filter" {
                $state.InteractiveFilter = -not $state.InteractiveFilter
                $infoLines = @("Additional post-scan filter menu is now '{0}'." -f (ConvertTo-RenderKitInteractiveMenuText -Value $state.InteractiveFilter))
            }
            "auto-select" {
                $state.AutoSelectAll = -not $state.AutoSelectAll
                $infoLines = @("Auto-select all matched files is now '{0}'." -f (ConvertTo-RenderKitInteractiveMenuText -Value $state.AutoSelectAll))
            }
            "auto-confirm" {
                $state.AutoConfirm = -not $state.AutoConfirm
                $infoLines = @("Auto-confirm import is now '{0}'." -f (ConvertTo-RenderKitInteractiveMenuText -Value $state.AutoConfirm))
            }
            "unassigned" {
                $selection = Select-RenderKitImportUnassignedHandlingMenu `
                    -Default $state.UnassignedHandling `
                    -AllowBack
                if (-not [string]::IsNullOrWhiteSpace($selection)) {
                    $state.UnassignedHandling = $selection
                    $infoLines = @("Unassigned file handling updated.")
                }
                else {
                    $infoLines = @("Unassigned file handling unchanged.")
                }
            }
            "classify" {
                $state.Classify = -not $state.Classify
                if (-not $state.Classify) {
                    $state.Transfer = $false
                }
                $infoLines = @("Classification phase is now '{0}'." -f (ConvertTo-RenderKitInteractiveMenuText -Value $state.Classify))
            }
            "transfer" {
                if ($state.Classify) {
                    $state.Transfer = -not $state.Transfer
                    $infoLines = @("Transfer prompt after classification is now '{0}'." -f (ConvertTo-RenderKitInteractiveMenuText -Value $state.Transfer))
                }
            }
            "start" {
                return [PSCustomObject]@{
                    ScanAndFilter                = $true
                    SourcePath                   = $state.SourcePath
                    FolderFilter                 = @($state.FolderFilter)
                    IncludeFixed                 = [bool]$state.IncludeFixed
                    IncludeUnsupportedFileSystem = [bool]$state.IncludeUnsupportedFileSystem
                    InteractiveFilter            = [bool]$state.InteractiveFilter
                    AutoSelectAll                = [bool]$state.AutoSelectAll
                    AutoConfirm                  = [bool]$state.AutoConfirm
                    ProjectRoot                  = $state.ProjectRoot
                    Classify                     = [bool]$state.Classify
                    Transfer                     = if ($state.Classify) { [bool]$state.Transfer } else { $false }
                    UnassignedHandling           = $state.UnassignedHandling
                }
            }
        }
    }
}

function Read-RenderKitImportAdditionalCriterionMenu {
    [CmdletBinding()]
    param()

    $state = [ordered]@{
        FolderFilter = @()
        FromDate     = $null
        ToDate       = $null
        Wildcard     = @()
    }

    $infoLines = @(
        "Use this menu to refine the scan result before selecting files.",
        "Leave everything empty and press Esc to skip additional criteria."
    )

    while ($true) {
        $hasCriteria = `
            ($state.FolderFilter.Count -gt 0) -or `
            ($state.Wildcard.Count -gt 0) -or `
            ($null -ne $state.FromDate) -or `
            ($null -ne $state.ToDate)

        $menuResult = Invoke-RenderKitInteractiveMenu `
            -Title "Additional import filters" `
            -Subtitle "Optional criteria applied after the initial source scan." `
            -Breadcrumb @("Import Media", "Scan", "Additional Filters") `
            -Status ([ordered]@{
                    FolderFilter = if ($state.FolderFilter.Count -gt 0) { $state.FolderFilter } else { "<none>" }
                    FromDate     = $state.FromDate
                    ToDate       = $state.ToDate
                    Wildcard     = if ($state.Wildcard.Count -gt 0) { $state.Wildcard } else { "<none>" }
                }) `
            -Info $infoLines `
            -Options @(
                New-RenderKitInteractiveMenuOption `
                    -Key "folder-filter" `
                    -Label "Edit folder filter list" `
                    -Description "Comma-separated folder names or folder wildcards." `
                    -HotKey "F",
                New-RenderKitInteractiveMenuOption `
                    -Key "clear-folder-filter" `
                    -Label "Clear folder filter list" `
                    -Description "Remove all additional folder filters." `
                    -HotKey "C" `
                    -IsEnabled:($state.FolderFilter.Count -gt 0),
                New-RenderKitInteractiveMenuOption `
                    -Key "from-date" `
                    -Label "Set from date" `
                    -Description "Keep only files on or after this timestamp." `
                    -HotKey "O",
                New-RenderKitInteractiveMenuOption `
                    -Key "clear-from-date" `
                    -Label "Clear from date" `
                    -Description "Remove the lower timestamp bound." `
                    -IsEnabled:($null -ne $state.FromDate),
                New-RenderKitInteractiveMenuOption `
                    -Key "to-date" `
                    -Label "Set to date" `
                    -Description "Keep only files on or before this timestamp." `
                    -HotKey "T",
                New-RenderKitInteractiveMenuOption `
                    -Key "clear-to-date" `
                    -Label "Clear to date" `
                    -Description "Remove the upper timestamp bound." `
                    -IsEnabled:($null -ne $state.ToDate),
                New-RenderKitInteractiveMenuOption `
                    -Key "wildcard" `
                    -Label "Edit wildcard list" `
                    -Description "Comma-separated file wildcards such as *.mov, *.wav." `
                    -HotKey "W",
                New-RenderKitInteractiveMenuOption `
                    -Key "clear-wildcard" `
                    -Label "Clear wildcard list" `
                    -Description "Remove all wildcard restrictions." `
                    -IsEnabled:($state.Wildcard.Count -gt 0),
                New-RenderKitInteractiveMenuOption `
                    -Key "apply" `
                    -Label "Apply these criteria" `
                    -Description "Continue with the currently visible criteria." `
                    -HotKey "A" `
                    -IsDefault:$hasCriteria
            ) `
            -AllowBack

        if ($menuResult.Action -eq "Back") {
            return $null
        }

        switch ($menuResult.Option.Key) {
            "folder-filter" {
                $inputResult = Read-RenderKitInteractiveMenuTextInput `
                    -Title "Folder filter list" `
                    -Subtitle "Enter a comma-separated list of folder names or folder wildcards." `
                    -Breadcrumb @("Import Media", "Scan", "Additional Filters", "Folder Filter") `
                    -Status ([ordered]@{
                            CurrentValue = if ($state.FolderFilter.Count -gt 0) { $state.FolderFilter -join ", " } else { "<none>" }
                        }) `
                    -Info @(
                        "Example: 100EOSR,101EOSR,Audio"
                    ) `
                    -Prompt "Folder filter list" `
                    -CurrentValue ($state.FolderFilter -join ", ")

                if ($inputResult.Action -eq "Submit") {
                    $state.FolderFilter = @(ConvertFrom-RenderKitImportListInput -InputText $inputResult.Value)
                }
            }
            "clear-folder-filter" {
                $state.FolderFilter = @()
            }
            "from-date" {
                while ($true) {
                    $inputResult = Read-RenderKitInteractiveMenuTextInput `
                        -Title "From date" `
                        -Subtitle "Enter a parseable date/time value." `
                        -Breadcrumb @("Import Media", "Scan", "Additional Filters", "From Date") `
                        -Status ([ordered]@{
                                CurrentValue = $state.FromDate
                            }) `
                        -Info @(
                            "Example: 2026-02-20 14:30"
                        ) `
                        -Prompt "From date" `
                        -CurrentValue (ConvertTo-RenderKitInteractiveMenuText -Value $state.FromDate)

                    if ($inputResult.Action -eq "Back") {
                        break
                    }

                    $parsedDate = [datetime]::MinValue
                    if ([datetime]::TryParse($inputResult.Value, [ref]$parsedDate)) {
                        $state.FromDate = $parsedDate
                        break
                    }

                    $infoLines = @(
                        "Invalid from date '{0}'. Use a parseable date/time value." -f $inputResult.Value,
                        "Leave everything empty and press Esc to skip additional criteria."
                    )
                }
            }
            "clear-from-date" {
                $state.FromDate = $null
            }
            "to-date" {
                while ($true) {
                    $inputResult = Read-RenderKitInteractiveMenuTextInput `
                        -Title "To date" `
                        -Subtitle "Enter a parseable date/time value." `
                        -Breadcrumb @("Import Media", "Scan", "Additional Filters", "To Date") `
                        -Status ([ordered]@{
                                CurrentValue = $state.ToDate
                            }) `
                        -Info @(
                            "Example: 2026-02-24 20:00"
                        ) `
                        -Prompt "To date" `
                        -CurrentValue (ConvertTo-RenderKitInteractiveMenuText -Value $state.ToDate)

                    if ($inputResult.Action -eq "Back") {
                        break
                    }

                    $parsedDate = [datetime]::MinValue
                    if ([datetime]::TryParse($inputResult.Value, [ref]$parsedDate)) {
                        $state.ToDate = $parsedDate
                        break
                    }

                    $infoLines = @(
                        "Invalid to date '{0}'. Use a parseable date/time value." -f $inputResult.Value,
                        "Leave everything empty and press Esc to skip additional criteria."
                    )
                }
            }
            "clear-to-date" {
                $state.ToDate = $null
            }
            "wildcard" {
                $inputResult = Read-RenderKitInteractiveMenuTextInput `
                    -Title "Wildcard list" `
                    -Subtitle "Enter a comma-separated list of file wildcards." `
                    -Breadcrumb @("Import Media", "Scan", "Additional Filters", "Wildcard") `
                    -Status ([ordered]@{
                            CurrentValue = if ($state.Wildcard.Count -gt 0) { $state.Wildcard -join ", " } else { "<none>" }
                        }) `
                    -Info @(
                        "Example: *.mov,*.wav,*.mp4"
                    ) `
                    -Prompt "Wildcard list" `
                    -CurrentValue ($state.Wildcard -join ", ")

                if ($inputResult.Action -eq "Submit") {
                    $state.Wildcard = @(ConvertFrom-RenderKitImportListInput -InputText $inputResult.Value)
                }
            }
            "clear-wildcard" {
                $state.Wildcard = @()
            }
            "apply" {
                if ($null -ne $state.FromDate -and $null -ne $state.ToDate -and $state.FromDate -gt $state.ToDate) {
                    $infoLines = @(
                        "From date must be earlier than or equal to the to date.",
                        "Leave everything empty and press Esc to skip additional criteria."
                    )
                    continue
                }

                if (-not $hasCriteria) {
                    return $null
                }

                return New-RenderKitImportCriterion `
                    -FolderFilter $state.FolderFilter `
                    -FromDate $state.FromDate `
                    -ToDate $state.ToDate `
                    -Wildcard $state.Wildcard
            }
        }

        $infoLines = @(
            "Use this menu to refine the scan result before selecting files.",
            "Leave everything empty and press Esc to skip additional criteria."
        )
    }
}

function Select-RenderKitImportFileSubsetMenu {
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

    $totalBytes = Get-RenderKitImportTotalByte -Files $Files
    $options = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $Files.Count; $i++) {
        $file = $Files[$i]
        $label = if (-not [string]::IsNullOrWhiteSpace([string]$file.RelativePath)) {
            [string]$file.RelativePath
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$file.FullName)) {
            [string]$file.FullName
        }
        else {
            [string]$file.Name
        }

        $details = @()
        if ($file.PSObject.Properties.Name -contains "LastWriteTime" -and $null -ne $file.LastWriteTime) {
            $details += ("Modified: {0}" -f (([datetime]$file.LastWriteTime).ToString("yyyy-MM-dd HH:mm:ss")))
        }
        if ($file.PSObject.Properties.Name -contains "Length") {
            $details += ("Size: {0}" -f (ConvertTo-RenderKitHumanSize -Bytes ([int64]$file.Length)))
        }
        if ($file.PSObject.Properties.Name -contains "Extension" -and -not [string]::IsNullOrWhiteSpace([string]$file.Extension)) {
            $details += ("Extension: {0}" -f $file.Extension)
        }

        $options.Add((New-RenderKitInteractiveMenuOption `
                -Key ("file-{0}" -f $i) `
                -Label $label `
                -Description ($details -join " | ") `
                -Value $file `
                -Selected $true))
    }

    $result = Invoke-RenderKitInteractiveMenu `
        -Title "Select files to import" `
        -Subtitle "Review the matched files and keep only the ones you want to import." `
        -Breadcrumb @("Import Media", "Selection") `
        -Status ([ordered]@{
                MatchedFiles = $Files.Count
                TotalSize    = ConvertTo-RenderKitHumanSize -Bytes ([int64]$totalBytes)
            }) `
        -Info @(
            "Everything starts selected. Remove items with Space or clear all with Delete.",
            "Esc returns an empty selection."
        ) `
        -Options $options.ToArray() `
        -AllowBack `
        -MultiSelect `
        -AllowEmptySelection

    if ($result.Action -eq "Back") {
        return @()
    }

    return @($result.SelectedValues)
}

function Confirm-RenderKitImportSelectionMenu {
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

    $result = Invoke-RenderKitInteractiveMenu `
        -Title "Confirm import" `
        -Subtitle "Review the final selection before classification or transfer." `
        -Breadcrumb @("Import Media", "Confirmation") `
        -Status ([ordered]@{
                SelectedFiles = $FileCount
                TotalSize     = ConvertTo-RenderKitHumanSize -Bytes ([int64]$TotalBytes)
            }) `
        -Info @(
            "Confirm to continue with the selected files.",
            "Cancel stops the import after the preview phase."
        ) `
        -Options @(
            New-RenderKitInteractiveMenuOption `
                -Key "confirm" `
                -Label "Confirm import" `
                -Description "Continue with the selected files." `
                -HotKey "Y" `
                -IsDefault $true,
            New-RenderKitInteractiveMenuOption `
                -Key "cancel" `
                -Label "Cancel import" `
                -Description "Stop the import before classification and transfer." `
                -HotKey "N"
        )

    return ($result.Option.Key -eq "confirm")
}

function Read-RenderKitImportSelectionReviewActionMenu {
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    $result = Invoke-RenderKitInteractiveMenu `
        -Title "Selection checkpoint" `
        -Subtitle "Choose how to continue after reviewing the selected files." `
        -Breadcrumb @("Import Media", "Selection Review") `
        -Info @(
            "Continue keeps the current selection.",
            "Edit returns to the file selection menu.",
            "Cancel stops the import."
        ) `
        -Options @(
            New-RenderKitInteractiveMenuOption `
                -Key "Continue" `
                -Label "Continue with the current selection" `
                -Description "Proceed to the final confirmation step." `
                -HotKey "Y" `
                -IsDefault $true,
            New-RenderKitInteractiveMenuOption `
                -Key "Edit" `
                -Label "Edit the selected files" `
                -Description "Return to the file subset menu and adjust the selection." `
                -HotKey "E",
            New-RenderKitInteractiveMenuOption `
                -Key "Cancel" `
                -Label "Cancel the import" `
                -Description "Stop the import and clear the current file selection." `
                -HotKey "C"
        )

    return [string]$result.Option.Key
}

function Read-RenderKitImportTransferModeMenu {
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    $result = Invoke-RenderKitInteractiveMenu `
        -Title "Transfer mode" `
        -Subtitle "Choose whether RenderKit should simulate or execute the final transfer." `
        -Breadcrumb @("Import Media", "Transfer") `
        -Info @(
            "Real transfer copies files into the project.",
            "Simulate runs the safety checks without writing files.",
            "No transfer stops after classification."
        ) `
        -Options @(
            New-RenderKitInteractiveMenuOption `
                -Key "Real" `
                -Label "Run the real transfer" `
                -Description "Copy the classified files into the destination project." `
                -HotKey "R" `
                -IsDefault $true,
            New-RenderKitInteractiveMenuOption `
                -Key "Simulate" `
                -Label "Simulate the transfer first" `
                -Description "Preview the transfer without changing files." `
                -HotKey "S",
            New-RenderKitInteractiveMenuOption `
                -Key "None" `
                -Label "Skip the transfer" `
                -Description "End the workflow after classification." `
                -HotKey "N"
        )

    return [string]$result.Option.Key
}

function Read-RenderKitImportBooleanMenu {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory)]
        [string]$Title,
        [Parameter(Mandatory)]
        [string]$Prompt,
        [bool]$Default = $true,
        [string[]]$Breadcrumb
    )

    $result = Invoke-RenderKitInteractiveMenu `
        -Title $Title `
        -Subtitle $Prompt `
        -Breadcrumb $Breadcrumb `
        -Options @(
            New-RenderKitInteractiveMenuOption `
                -Key "Yes" `
                -Label "Yes" `
                -Description "Continue with this action." `
                -HotKey "Y" `
                -IsDefault:$Default,
            New-RenderKitInteractiveMenuOption `
                -Key "No" `
                -Label "No" `
                -Description "Do not continue with this action." `
                -HotKey "N" `
                -IsDefault:(-not $Default)
        )

    return ($result.Option.Key -eq "Yes")
}

function Read-RenderKitImportUnassignedActionMenu {
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

    $options = New-Object System.Collections.Generic.List[object]
    if ($DestinationFolders) {
        for ($i = 0; $i -lt $DestinationFolders.Count; $i++) {
            $folder = $DestinationFolders[$i]
            $options.Add((New-RenderKitInteractiveMenuOption `
                    -Key ("assign-{0}" -f $i) `
                    -Label $folder `
                    -Description ("Assign files with extension '{0}' to '{1}'." -f $ExtensionLabel, $folder) `
                    -Value $folder `
                    -IsDefault:($i -eq 0)))
        }
    }

    $options.Add((New-RenderKitInteractiveMenuOption `
            -Key "tosort" `
            -Label "Send to TO SORT" `
            -Description "Route the unassigned files to the TO SORT folder." `
            -HotKey "T"))
    $options.Add((New-RenderKitInteractiveMenuOption `
            -Key "skip" `
            -Label "Skip these files" `
            -Description "Exclude these files from the import." `
            -HotKey "S"))

    $result = Invoke-RenderKitInteractiveMenu `
        -Title "Unassigned file action" `
        -Subtitle "Choose how to handle files that do not match a mapping." `
        -Breadcrumb @("Import Media", "Classification", "Unassigned Files") `
        -Status ([ordered]@{
                ExtensionLabel     = $ExtensionLabel
                FileCount          = $FileCount
                DestinationFolders = if ($DestinationFolders) { $DestinationFolders.Count } else { 0 }
            }) `
        -Info @(
            "Choose a destination folder, route the files to TO SORT, or skip them."
        ) `
        -Options $options.ToArray()

    if ($result.Option.Key -eq "tosort") {
        return [PSCustomObject]@{ Mode = "ToSort" }
    }

    if ($result.Option.Key -eq "skip") {
        return [PSCustomObject]@{ Mode = "Skip" }
    }

    return [PSCustomObject]@{
        Mode                = "Assign"
        RelativeDestination = [string]$result.Option.Value
    }
}
