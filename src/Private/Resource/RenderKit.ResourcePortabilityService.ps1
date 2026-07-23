function Assert-RenderKitResourceName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    $candidate = $Name.Trim()
    $normalized = [IO.Path]::GetFileNameWithoutExtension($candidate)
    if ([string]::IsNullOrWhiteSpace($normalized) -or
        $candidate -ne [IO.Path]::GetFileName($candidate) -or
        $normalized -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._-]{0,127}$') {
        throw "Resource name '$Name' is not a safe file name."
    }
    return $normalized
}

function Get-RenderKitResourceDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Template', 'Mapping')][string]$Kind,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('System', 'User')][string]$Source
    )
    $Name = Assert-RenderKitResourceName -Name $Name
    $path = if ($Kind -eq 'Template') {
        if ($Source -eq 'User') { Get-RenderKitUserTemplatePath -TemplateName $Name }
        else { Join-Path (Get-RenderKitSystemTemplatesRoot) "$([IO.Path]::GetFileNameWithoutExtension($Name)).json" }
    } else {
        if ($Source -eq 'User') { Get-RenderKitUserMappingPath -MappingId $Name }
        else { Get-RenderKitSystemMappingPath -MappingId $Name }
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "$Kind '$Name' was not found in $Source resources."
    }
    [PSCustomObject]@{ Kind = $Kind; Name = $Name; Source = $Source; Path = $path }
}

function Test-RenderKitResourceDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Template', 'Mapping')][string]$Kind,
        [Parameter(Mandatory)][string]$Path,
        [switch]$RequireWritable
    )
    $document = Read-RenderKitJsonFile -Path $Path
    $compatibility = if ($Kind -eq 'Template') {
        Confirm-Template -Template $document -RequireWritable:$RequireWritable
    } else {
        Confirm-RenderKitMapping -Mapping $document -RequireWritable:$RequireWritable
    }
    $name = if ($Kind -eq 'Template') { [string]$document.Name } else { [string]$document.Id }
    [PSCustomObject]@{
        Name = $name
        Version = [string]$document.Version
        Document = $document
        Compatibility = $compatibility
    }
}

function Import-RenderKitResourceDocument {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][ValidateSet('Template', 'Mapping')][string]$Kind,
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Error', 'Overwrite', 'Rename')][string]$ConflictAction = 'Error'
    )
    $sourcePath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    $validation = Test-RenderKitResourceDocument -Kind $Kind -Path $sourcePath -RequireWritable
    $name = Assert-RenderKitResourceName -Name $validation.Name
    $destinationPath = if ($Kind -eq 'Template') {
        Get-RenderKitUserTemplatePath -TemplateName $name
    } else { Get-RenderKitUserMappingPath -MappingId $name }
    if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
        if ($ConflictAction -eq 'Error') { throw "$Kind '$name' already exists as a user resource." }
        if ($ConflictAction -eq 'Rename') {
            $baseName = $name
            $suffix = 2
            do {
                $name = "$baseName-$suffix"
                $destinationPath = if ($Kind -eq 'Template') {
                    Get-RenderKitUserTemplatePath -TemplateName $name
                } else { Get-RenderKitUserMappingPath -MappingId $name }
                $suffix++
            } while (Test-Path -LiteralPath $destinationPath -PathType Leaf)
            if ($Kind -eq 'Template') { $validation.Document.Name = $name }
            else { $validation.Document.Id = $name }
        }
    }
    if ($PSCmdlet.ShouldProcess($destinationPath, "Import $Kind '$name'")) {
        if ($Kind -eq 'Template') {
            Write-RenderKitTemplateFile -Template $validation.Document -Path $destinationPath
        } else {
            Write-RenderKitMappingFile -Mapping $validation.Document -MappingId $name
        }
    }
    [PSCustomObject]@{
        Name = $name; Path = $destinationPath; Source = 'User'
        FormatVersion = $validation.Version; ConflictAction = $ConflictAction
    }
}

function Export-RenderKitResourceDocument {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][ValidateSet('Template', 'Mapping')][string]$Kind,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('System', 'User')][string]$Source,
        [Parameter(Mandatory)][string]$Path
    )
    $descriptor = Get-RenderKitResourceDescriptor -Kind $Kind -Name $Name -Source $Source
    $validation = Test-RenderKitResourceDocument -Kind $Kind -Path $descriptor.Path
    $destinationPath = [IO.Path]::GetFullPath($Path)
    if (Test-Path -LiteralPath $destinationPath -PathType Container) {
        $destinationPath = Join-Path $destinationPath "$([IO.Path]::GetFileNameWithoutExtension($validation.Name)).json"
    }
    $parent = Split-Path -Parent $destinationPath
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $written = $false
    if ($PSCmdlet.ShouldProcess($destinationPath, "Export $Kind '$Name'")) {
        Write-RenderKitJsonFileAtomic -Value $validation.Document -Path $destinationPath -Depth 20 | Out-Null
        $written = $true
    }
    $file = Get-Item -LiteralPath $destinationPath -ErrorAction SilentlyContinue
    [PSCustomObject]@{
        Name = $validation.Name
        Path = if ($file) { $file.FullName } else { $destinationPath }
        SizeBytes = if ($file) { [int64]$file.Length } else { $null }
        Written = $written
    }
}

function Test-RenderKitStoredResource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Template', 'Mapping')][string]$Kind,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('System', 'User')][string]$Source
    )
    try {
        $descriptor = Get-RenderKitResourceDescriptor -Kind $Kind -Name $Name -Source $Source
        $validation = Test-RenderKitResourceDocument -Kind $Kind -Path $descriptor.Path
        [PSCustomObject]@{
            Name = $validation.Name; Source = $Source; Path = $descriptor.Path
            FormatVersion = $validation.Version; IsValid = $true; Message = $null
        }
    } catch {
        [PSCustomObject]@{
            Name = $Name; Source = $Source; Path = $null; FormatVersion = $null
            IsValid = $false; Message = $_.Exception.Message
        }
    }
}
