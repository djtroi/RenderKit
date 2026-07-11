function New-RenderKitMetadataTemplateObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Description
    )

    $now = (Get-Date).ToUniversalTime().ToString('o')
    return [PSCustomObject]@{
        tool = 'RenderKit'
        schemaVersion = '1.0'
        artifactType = 'MetadataTemplate'
        name = [IO.Path]::GetFileNameWithoutExtension($Name)
        description = if ([string]::IsNullOrWhiteSpace($Description)) { $null } else { $Description }
        createdAtUtc = $now
        updatedAtUtc = $now
        revision = [PSCustomObject]@{
            generation = 1
        }
        fields = [PSCustomObject]@{}
    }
}

function Test-RenderKitMetadataTemplateSchema {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object]$Template
    )

    if ([string]$Template.artifactType -ne 'MetadataTemplate') {
        return $false
    }
    if ([string]::IsNullOrWhiteSpace([string]$Template.schemaVersion)) {
        return $false
    }
    if ([string]::IsNullOrWhiteSpace([string]$Template.name)) {
        return $false
    }
    if ($null -eq $Template.fields) {
        return $false
    }

    $compatibility = Test-RenderKitArtifactCompatibility `
        -ArtifactType MetadataTemplate `
        -Version ([string]$Template.schemaVersion)
    return [bool]($compatibility.CanRead -and $compatibility.CanWrite)
}

function Read-RenderKitMetadataTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $path = Get-RenderKitMetadataTemplatePath -Name $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Metadata template '$Name' was not found."
    }

    $template = Read-RenderKitJsonFile `
        -Path $path `
        -MaximumBytes 10485760 `
        -Validator { param($value) Test-RenderKitMetadataTemplateSchema -Template $value }
    return [PSCustomObject]@{
        Template = $template
        Path = $path
    }
}

function Write-RenderKitMetadataTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Template
    )

    if (-not $Template.revision) {
        $Template | Add-Member -NotePropertyName revision -NotePropertyValue ([PSCustomObject]@{ generation = 1 }) -Force
    }
    if (-not $Template.fields) {
        $Template | Add-Member -NotePropertyName fields -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    $Template.updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    $path = Get-RenderKitMetadataTemplatePath -Name ([string]$Template.name)
    Write-RenderKitJsonFileAtomic `
        -Path $path `
        -Value $Template `
        -Depth 30 `
        -Validator { param($value) Test-RenderKitMetadataTemplateSchema -Template $value } |
        Out-Null
    return [PSCustomObject]@{
        Template = $Template
        Path = $path
    }
}

function Get-RenderKitMetadataTemplate {
    [CmdletBinding()]
    param(
        [string]$Name
    )

    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        return (Read-RenderKitMetadataTemplate -Name $Name)
    }

    $root = Get-RenderKitMetadataTemplatesRoot
    return @(
        Get-ChildItem -LiteralPath $root -Filter '*.json' -File -ErrorAction SilentlyContinue |
            Sort-Object -Property BaseName |
            ForEach-Object {
                [PSCustomObject]@{
                    Template = (Read-RenderKitJsonFile `
                        -Path $_.FullName `
                        -MaximumBytes 10485760 `
                        -Validator { param($value) Test-RenderKitMetadataTemplateSchema -Template $value })
                    Path = $_.FullName
                }
            }
    )
}

function Set-RenderKitMetadataTemplateField {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Field,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Value,

        [switch]$NoOverride,

        [switch]$Force
    )

    Assert-RenderKitMetadataFieldWrite `
        -Field $Field `
        -Value $Value `
        -Force:$Force |
        Out-Null

    $templateContext = Read-RenderKitMetadataTemplate -Name $Name
    $template = $templateContext.Template
    $fields = ConvertTo-RenderKitMetadataDictionary -Value $template.fields

    if ($NoOverride -and $fields.Contains($Field)) {
        throw "Metadata template '$Name' already contains field '$Field'."
    }

    $oldJson = ConvertTo-RenderKitMetadataComparableJson -Value $fields
    Set-RenderKitMetadataFieldValue `
        -Fields $fields `
        -Name $Field `
        -Value $Value
    $newJson = ConvertTo-RenderKitMetadataComparableJson -Value $fields

    $template.fields = [PSCustomObject]$fields
    if ($oldJson -ne $newJson) {
        if (-not $template.revision) {
            $template | Add-Member -NotePropertyName revision -NotePropertyValue ([PSCustomObject]@{ generation = 1 }) -Force
        }
        $template.revision.generation = [int]$template.revision.generation + 1
    }

    return Write-RenderKitMetadataTemplate -Template $template
}
