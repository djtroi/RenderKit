function Get-RenderKitMetadataFieldRegistryPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Path
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return Join-Path -Path $script:RenderKitModuleRoot `
        -ChildPath 'src/Resources/Metadata/fields.json'
}

function Test-RenderKitMetadataFieldRegistrySchema {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object]$Registry
    )

    if ([string]::IsNullOrWhiteSpace([string]$Registry.schemaVersion)) {
        return $false
    }
    if ([string]$Registry.artifactType -ne 'MetadataFieldRegistry') {
        return $false
    }
    if (-not $Registry.fields) {
        return $false
    }

    $names = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($field in @($Registry.fields)) {
        $name = [string]$field.name
        if ([string]::IsNullOrWhiteSpace($name)) {
            return $false
        }
        if (-not $names.Add($name)) {
            return $false
        }
    }

    return $true
}

function Read-RenderKitMetadataFieldRegistry {
    [CmdletBinding()]
    param(
        [string]$Path,
        [switch]$Reload
    )

    $resolvedPath = Get-RenderKitMetadataFieldRegistryPath -Path $Path
    if (-not $Reload -and
        $script:RenderKitMetadataFieldRegistryCache -and
        $script:RenderKitMetadataFieldRegistryCachePath -eq $resolvedPath) {
        return $script:RenderKitMetadataFieldRegistryCache
    }

    $registry = Read-RenderKitJsonFile `
        -Path $resolvedPath `
        -MaximumBytes 52428800 `
        -Validator { param($value) Test-RenderKitMetadataFieldRegistrySchema -Registry $value }

    Test-RenderKitArtifactCompatibility `
        -ArtifactType MetadataFieldRegistry `
        -Version ([string]$registry.schemaVersion) |
        Out-Null

    $script:RenderKitMetadataFieldRegistryCache = $registry
    $script:RenderKitMetadataFieldRegistryCachePath = $resolvedPath
    return $registry
}

function Get-RenderKitMetadataFieldName {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [string]$Path,
        [switch]$Reload
    )

    $registry = Read-RenderKitMetadataFieldRegistry -Path $Path -Reload:$Reload
    return @(
        $registry.fields |
            ForEach-Object { [string]$_.name } |
            Sort-Object
    )
}

function Get-RenderKitMetadataFieldDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Field,

        [object]$Registry
    )

    if (-not $Registry) {
        $Registry = Read-RenderKitMetadataFieldRegistry
    }

    return @(
        $Registry.fields |
            Where-Object { [string]$_.name -ieq $Field } |
            Select-Object -First 1
    )
}

function New-RenderKitMetadataFieldDynamicParameter {
    [CmdletBinding()]
    param(
        [string]$Name = 'Field',
        [int]$Position = 0,
        [switch]$Mandatory,
        [type]$ParameterType = [string]
    )

    $attributes = New-Object 'System.Collections.ObjectModel.Collection[System.Attribute]'
    $parameterAttribute = New-Object System.Management.Automation.ParameterAttribute
    $parameterAttribute.Mandatory = [bool]$Mandatory
    if ($Position -ge 0) {
        $parameterAttribute.Position = $Position
    }
    $attributes.Add($parameterAttribute)

    $fieldNames = @(Get-RenderKitMetadataFieldName)
    if ($fieldNames.Count -gt 0) {
        $validateSetAttribute = `
            [System.Management.Automation.ValidateSetAttribute]::new(
                [string[]]$fieldNames
            )
        $attributes.Add($validateSetAttribute)
    }

    $runtimeParameter = New-Object `
        System.Management.Automation.RuntimeDefinedParameter `
        -ArgumentList $Name, $ParameterType, $attributes

    $dictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
    $dictionary.Add($Name, $runtimeParameter)
    return $dictionary
}

function Test-RenderKitMetadataValueInValidateSet {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [object]$Value,

        [string[]]$ValidateSet,

        [switch]$AllowMultiple
    )

    if (-not $ValidateSet -or $ValidateSet.Count -eq 0) {
        return $true
    }

    $allowed = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($item in $ValidateSet) {
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            [void]$allowed.Add([string]$item)
        }
    }

    $values = @()
    if ($AllowMultiple -and $Value -is [System.Collections.IEnumerable] -and
        -not ($Value -is [string])) {
        $values = @($Value)
    }
    elseif ($AllowMultiple -and $Value -is [string] -and $Value -match ',') {
        $values = @($Value -split ',' | ForEach-Object { $_.Trim() })
    }
    else {
        $values = @($Value)
    }

    foreach ($candidate in $values) {
        if (-not $allowed.Contains([string]$candidate)) {
            return $false
        }
    }
    return $true
}

function Test-RenderKitMetadataValueType {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [object]$Value,

        [AllowEmptyString()]
        [string]$FieldType
    )

    if ($null -eq $Value) {
        return $false
    }

    $text = [string]$Value
    switch -Regex ($FieldType) {
        '^Boolean$' {
            $parsed = $false
            return [bool]::TryParse($text, [ref]$parsed)
        }
        '^Integer$' {
            $parsed = [int64]0
            return [int64]::TryParse(
                $text,
                [System.Globalization.NumberStyles]::Integer,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$parsed
            )
        }
        '^(Float|Decimal|Rating|Coordinate|Fraction)$' {
            $parsed = [double]0
            return [double]::TryParse(
                $text,
                [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$parsed
            )
        }
        '^(Date|DateTime)$' {
            $parsed = [datetime]::MinValue
            return [datetime]::TryParse(
                $text,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AllowWhiteSpaces,
                [ref]$parsed
            )
        }
        '^TimeSpan$' {
            $parsed = [timespan]::Zero
            return [timespan]::TryParse(
                $text,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$parsed
            )
        }
        '^GUID$' {
            $parsed = [guid]::Empty
            return [guid]::TryParse($text, [ref]$parsed)
        }
        '^(URI|Path|Hash|String|Color)$' {
            return -not [string]::IsNullOrWhiteSpace($text)
        }
        '^Json$' {
            if (-not ($Value -is [string])) { return $true }
            try {
                $Value | ConvertFrom-Json -ErrorAction Stop | Out-Null
                return $true
            }
            catch {
                return $false
            }
        }
        default {
            return $true
        }
    }
}

function Test-RenderKitMetadataFieldValueCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Field,

        [AllowNull()]
        [object]$Value,

        [object]$Registry
    )

    if (-not $Registry) {
        $Registry = Read-RenderKitMetadataFieldRegistry
    }

    $definition = Get-RenderKitMetadataFieldDefinition `
        -Field $Field `
        -Registry $Registry
    if (-not $definition) {
        return [PSCustomObject]@{
            Field = $Field
            Value = $Value
            IsValid = $false
            Reason = "Unknown metadata field '$Field'."
            FieldType = $null
            ValidateSet = @()
        }
    }

    $fieldType = [string]$definition.fieldType
    $validateSet = @($definition.validateSet | ForEach-Object { [string]$_ })
    $allowsMultiple = $fieldType -like 'List*' -or
        $fieldType -like 'MultiSelect*'

    $typeIsValid = Test-RenderKitMetadataValueType `
        -Value $Value `
        -FieldType $fieldType
    if (-not $typeIsValid) {
        return [PSCustomObject]@{
            Field = [string]$definition.name
            Value = $Value
            IsValid = $false
            Reason = "Value does not match field type '$fieldType'."
            FieldType = $fieldType
            ValidateSet = @($validateSet)
        }
    }

    $setIsValid = Test-RenderKitMetadataValueInValidateSet `
        -Value $Value `
        -ValidateSet $validateSet `
        -AllowMultiple:$allowsMultiple
    if (-not $setIsValid) {
        return [PSCustomObject]@{
            Field = [string]$definition.name
            Value = $Value
            IsValid = $false
            Reason = 'Value is not in the allowed metadata value set.'
            FieldType = $fieldType
            ValidateSet = @($validateSet)
        }
    }

    return [PSCustomObject]@{
        Field = [string]$definition.name
        Value = $Value
        IsValid = $true
        Reason = $null
        FieldType = $fieldType
        ValidateSet = @($validateSet)
    }
}

function Test-RenderKitMetadataFieldWritable {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Field,

        [object]$Registry
    )

    if (-not $Registry) {
        $Registry = Read-RenderKitMetadataFieldRegistry
    }

    $definition = Get-RenderKitMetadataFieldDefinition `
        -Field $Field `
        -Registry $Registry
    if (-not $definition) {
        return $false
    }

    if ($definition.effectiveReadOnly -eq $true) {
        return $false
    }
    if ($definition.readOnly -eq $true) {
        return $false
    }

    return $true
}

function Assert-RenderKitMetadataFieldWrite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Field,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Value,

        [switch]$Force
    )

    $registry = Read-RenderKitMetadataFieldRegistry
    $definition = Get-RenderKitMetadataFieldDefinition `
        -Field $Field `
        -Registry $registry
    if (-not $definition) {
        throw "Unknown metadata field '$Field'."
    }

    if (-not $Force -and -not (Test-RenderKitMetadataFieldWritable -Field $Field -Registry $registry)) {
        throw "Metadata field '$Field' is read-only in the RenderKit field registry. Use -Force only for deliberate internal metadata writes."
    }

    $validation = Test-RenderKitMetadataFieldValueCore `
        -Field $Field `
        -Value $Value `
        -Registry $registry
    if (-not [bool]$validation.IsValid) {
        throw "Metadata value for '$Field' is invalid: $($validation.Reason)"
    }

    return $definition
}
