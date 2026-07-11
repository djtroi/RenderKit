[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SourcePath,

    [string]$DestinationPath = (Join-Path -Path $PSScriptRoot -ChildPath '../src/Resources/Metadata/fields.json')
)

function Get-RenderKitWorkbookCellText {
    param(
        [Parameter(Mandatory)]$UsedRange,
        [Parameter(Mandatory)][int]$Row,
        [Parameter(Mandatory)][int]$Column
    )

    $text = [string]$UsedRange.Cells.Item($Row, $Column).Text
    if ($null -eq $text) { return '' }
    return $text.Trim()
}

function Split-RenderKitMetadataListText {
    param(
        [AllowNull()][string]$Value,
        [string]$Pattern = '[|,]'
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
    return @(
        $Value -split $Pattern |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )
}

function ConvertTo-RenderKitNullableBoolean {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    switch -Regex ($Value.Trim()) {
        '^(true|yes|y|1|x)$' { return $true }
        '^(false|no|n|0)$' { return $false }
        default { return $null }
    }
}

function Get-RenderKitMetadataValidateSet {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][string]$FieldType,
        [AllowNull()][string]$AcceptedInput,
        [Parameter(Mandatory)][hashtable]$Enums
    )

    if ($Enums.ContainsKey($Name)) {
        return @($Enums[$Name])
    }

    if ($FieldType -eq 'Boolean') {
        return @('true', 'false')
    }

    if ([string]::IsNullOrWhiteSpace($AcceptedInput)) {
        return @()
    }

    $candidate = $AcceptedInput -replace "(`r`n|`n|`r)", ' '
    $candidate = $candidate.Trim()

    if ($candidate -match '(?i)^Known extensions:\s*(.+)$') {
        $candidate = $Matches[1]
    }
    elseif ($candidate -match '(?i)^common\s+(.+)$') {
        $candidate = $Matches[1]
    }
    elseif ($candidate -match '(?i)\bcommon\s+(.+)$' -and $candidate -notmatch '(?i)regex') {
        $candidate = $Matches[1]
    }
    elseif ($candidate -match '(?i)^(Allowed values|Allowed|One of|Values):\s*(.+)$') {
        $candidate = $Matches[2]
    }
    elseif ($candidate -match '(?i)regex|invalid|path separators|0\.\.|1\.\.|0..N|1..N|Any |ISO |UUID|GUID') {
        return @()
    }

    if ($candidate -notmatch '[|,]') {
        return @()
    }

    $tokens = if ($candidate -match '\|') {
        Split-RenderKitMetadataListText -Value $candidate -Pattern '\|'
    }
    else {
        Split-RenderKitMetadataListText -Value $candidate -Pattern ','
    }

    return @(
        $tokens |
            Where-Object { $_ -notmatch '(?i)^(Regex|common|e\.g\.|example)' } |
            Select-Object -Unique
    )
}

function New-RenderKitMetadataFieldVariant {
    param(
        [Parameter(Mandatory)]$UsedRange,
        [Parameter(Mandatory)][string]$SheetName,
        [Parameter(Mandatory)][int]$Row,
        [Parameter(Mandatory)][hashtable]$Enums
    )

    $name = Get-RenderKitWorkbookCellText -UsedRange $UsedRange -Row $Row -Column 1
    $fieldType = Get-RenderKitWorkbookCellText -UsedRange $UsedRange -Row $Row -Column 2
    $guiType = Get-RenderKitWorkbookCellText -UsedRange $UsedRange -Row $Row -Column 3
    $acceptedInput = Get-RenderKitWorkbookCellText -UsedRange $UsedRange -Row $Row -Column 4
    $category = Get-RenderKitWorkbookCellText -UsedRange $UsedRange -Row $Row -Column 5
    $appliesTo = Get-RenderKitWorkbookCellText -UsedRange $UsedRange -Row $Row -Column 6
    $sourceStandard = Get-RenderKitWorkbookCellText -UsedRange $UsedRange -Row $Row -Column 7
    $sourceUrl = Get-RenderKitWorkbookCellText -UsedRange $UsedRange -Row $Row -Column 8
    $editable = ConvertTo-RenderKitNullableBoolean (Get-RenderKitWorkbookCellText -UsedRange $UsedRange -Row $Row -Column 9)
    $required = ConvertTo-RenderKitNullableBoolean (Get-RenderKitWorkbookCellText -UsedRange $UsedRange -Row $Row -Column 10)
    $readOnly = ConvertTo-RenderKitNullableBoolean (Get-RenderKitWorkbookCellText -UsedRange $UsedRange -Row $Row -Column 11)
    $example = Get-RenderKitWorkbookCellText -UsedRange $UsedRange -Row $Row -Column 12
    $notes = Get-RenderKitWorkbookCellText -UsedRange $UsedRange -Row $Row -Column 13
    $validateSet = Get-RenderKitMetadataValidateSet `
        -Name $name `
        -FieldType $fieldType `
        -AcceptedInput $acceptedInput `
        -Enums $Enums

    return [ordered]@{
        sheet = $SheetName
        row = $Row
        name = $name
        fieldType = $fieldType
        guiType = $guiType
        category = $category
        appliesTo = @(Split-RenderKitMetadataListText -Value $appliesTo -Pattern '[,;/|]')
        sourceStandard = $sourceStandard
        sourceUrls = @(Split-RenderKitMetadataListText -Value $sourceUrl -Pattern "(`r`n|`n|`r)")
        acceptedInput = $acceptedInput
        validateSet = @($validateSet)
        editable = $editable
        required = $required
        readOnly = $readOnly
        effectiveReadOnly = ($readOnly -eq $true -or $guiType -eq 'ReadOnlyLabel')
        example = $example
        notes = $notes
    }
}

function Get-RenderKitUniqueValue {
    param(
        [AllowNull()][object[]]$Values
    )

    if ($null -eq $Values) { return $null }
    $unique = @(
        $Values |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            Sort-Object -Unique
    )
    if ($unique.Count -eq 1) { return [string]$unique[0] }
    return $null
}

function Join-RenderKitUniqueValues {
    param([AllowNull()][object[]]$Values)

    return @(
        $Values |
            ForEach-Object {
                if ($null -eq $_) { return }
                if ($_ -is [array]) { $_ } else { $_ }
            } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            Sort-Object -Unique
    )
}

$resolvedSourcePath = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).ProviderPath
$resolvedDestinationPath = [System.IO.Path]::GetFullPath($DestinationPath)
$destinationDirectory = Split-Path -Path $resolvedDestinationPath -Parent
if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
}

$excel = $null
$workbook = $null
$fieldSheets = @('Common_Asset', 'Audio', 'Video', 'Image')

try {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false
    $workbook = $excel.Workbooks.Open($resolvedSourcePath, 0, $true)

    $enums = @{}
    $enumSheet = $workbook.Worksheets.Item('Enums')
    $enumUsed = $enumSheet.UsedRange
    for ($column = 1; $column -le $enumUsed.Columns.Count; $column++) {
        $enumName = Get-RenderKitWorkbookCellText -UsedRange $enumUsed -Row 1 -Column $column
        if ([string]::IsNullOrWhiteSpace($enumName)) { continue }
        $enumValues = New-Object System.Collections.Generic.List[string]
        for ($row = 2; $row -le $enumUsed.Rows.Count; $row++) {
            $enumValue = Get-RenderKitWorkbookCellText -UsedRange $enumUsed -Row $row -Column $column
            if (-not [string]::IsNullOrWhiteSpace($enumValue)) {
                $enumValues.Add($enumValue)
            }
        }
        $enums[$enumName] = @($enumValues.ToArray() | Select-Object -Unique)
    }

    $fieldRows = New-Object System.Collections.Generic.List[object]
    foreach ($sheetName in $fieldSheets) {
        $sheet = $workbook.Worksheets.Item($sheetName)
        $used = $sheet.UsedRange
        for ($row = 2; $row -le $used.Rows.Count; $row++) {
            $name = Get-RenderKitWorkbookCellText -UsedRange $used -Row $row -Column 1
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $fieldRows.Add((New-RenderKitMetadataFieldVariant `
                -UsedRange $used `
                -SheetName $sheetName `
                -Row $row `
                -Enums $enums))
        }
    }

    $fieldMap = [ordered]@{}
    foreach ($variant in $fieldRows) {
        $key = ([string]$variant.name).ToLowerInvariant()
        if (-not $fieldMap.Contains($key)) {
            $fieldMap[$key] = New-Object System.Collections.Generic.List[object]
        }
        $fieldMap[$key].Add($variant)
    }

    $fields = New-Object System.Collections.Generic.List[object]
    foreach ($key in @($fieldMap.Keys | Sort-Object)) {
        $variants = @($fieldMap[$key].ToArray())
        $first = $variants[0]
        $readOnlyValues = @($variants | ForEach-Object { $_.effectiveReadOnly })
        $validateSet = Join-RenderKitUniqueValues -Values @($variants | ForEach-Object { $_.validateSet })
        $field = [ordered]@{
            name = [string]$first.name
            fieldType = Get-RenderKitUniqueValue -Values @($variants | ForEach-Object { $_.fieldType })
            guiType = Get-RenderKitUniqueValue -Values @($variants | ForEach-Object { $_.guiType })
            categories = Join-RenderKitUniqueValues -Values @($variants | ForEach-Object { $_.category })
            appliesTo = Join-RenderKitUniqueValues -Values @($variants | ForEach-Object { $_.appliesTo })
            sourceStandards = Join-RenderKitUniqueValues -Values @($variants | ForEach-Object { $_.sourceStandard })
            sourceUrls = Join-RenderKitUniqueValues -Values @($variants | ForEach-Object { $_.sourceUrls })
            acceptedInput = Get-RenderKitUniqueValue -Values @($variants | ForEach-Object { $_.acceptedInput })
            validateSet = @($validateSet)
            editable = Get-RenderKitUniqueValue -Values @($variants | ForEach-Object { $_.editable })
            required = Get-RenderKitUniqueValue -Values @($variants | ForEach-Object { $_.required })
            readOnly = Get-RenderKitUniqueValue -Values @($variants | ForEach-Object { $_.readOnly })
            effectiveReadOnly = -not ($readOnlyValues -contains $false)
            examples = Join-RenderKitUniqueValues -Values @($variants | ForEach-Object { $_.example })
            notes = Join-RenderKitUniqueValues -Values @($variants | ForEach-Object { $_.notes })
            variants = @($variants)
        }
        $fields.Add($field)
    }

    $registry = [ordered]@{
        schemaVersion = '1.0'
        artifactType = 'MetadataFieldRegistry'
        generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        source = [ordered]@{
            workbookName = [System.IO.Path]::GetFileName($resolvedSourcePath)
            workbookSha256 = (Get-FileHash -LiteralPath $resolvedSourcePath -Algorithm SHA256).Hash
            fieldSheets = $fieldSheets
        }
        fieldRowCount = $fieldRows.Count
        fieldCount = $fields.Count
        duplicateFieldNameCount = ($fieldRows.Count - $fields.Count)
        enums = [ordered]@{}
        fields = @($fields.ToArray())
    }

    foreach ($enumKey in @($enums.Keys | Sort-Object)) {
        $registry.enums[$enumKey] = @($enums[$enumKey])
    }

    $json = $registry | ConvertTo-Json -Depth 30
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($resolvedDestinationPath, $json, $encoding)

    [PSCustomObject]@{
        Path = $resolvedDestinationPath
        FieldRows = $fieldRows.Count
        Fields = $fields.Count
        DuplicateFieldNames = ($fieldRows.Count - $fields.Count)
        EnumCount = $enums.Count
    }
}
finally {
    if ($workbook) { $workbook.Close($false) | Out-Null }
    if ($excel) { $excel.Quit() | Out-Null }
    if ($workbook) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) }
    if ($excel) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) }
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}
