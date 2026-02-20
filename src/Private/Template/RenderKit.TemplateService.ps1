function Get-RenderKitTemplates {
    param(
        [ValidateSet("all", "system", "user")]
        [string]$Source = "all"
    )

    $templates = @()

    if ($Source -in @("all", "system")) {
        $systemRoot = Get-RenderKitSystemTemplatesRoot
        if (Test-Path $systemRoot) {
            $templates += Get-ChildItem $systemRoot -Filter "*.json" | ForEach-Object {
                [PSCustomObject]@{
                    Name   = $_.BaseName
                    Path   = $_.FullName
                    Source = "system"
                }
            }
        }
    }

    if ($Source -in @("all", "user")) {
        $userRoot = Get-RenderKitUserTemplatesRoot
        if (Test-Path $userRoot) {
            $templates += Get-ChildItem $userRoot -Filter "*.json" | ForEach-Object {
                [PSCustomObject]@{
                    Name   = $_.BaseName
                    Path   = $_.FullName
                    Source = "user"
                }
            }
        }
    }

    return $templates
}

function Resolve-ProjectTemplate {
    param(
        [string]$TemplateName
    )

    Write-RenderKitLog -Level Debug -Message "Resolving project template..."

    $templates = Get-RenderKitTemplates

    $normalizedName = $null
    if (-not [string]::IsNullOrWhiteSpace($TemplateName)) {
        $normalizedName = [IO.Path]::GetFileNameWithoutExtension($TemplateName)
    }

    # user template input overrides system
    if ($normalizedName) {
        $match = $templates |
            Where-Object Name -eq $normalizedName |
            Sort-Object @{Expression = {$_.Source -eq "user"}; Descending = $true} |
            Select-Object -First 1

        if (-not $match) {
            throw "Template '$TemplateName' not found."
        }

        return $match
    }

    # fallback to system default.json
    $default = $templates |
        Where-Object { $_.Name -eq "default" -and $_.Source -eq "system" } |
        Select-Object -First 1

    if (-not $default) {
        $default = $templates |
            Where-Object Name -eq "default" |
            Sort-Object @{Expression = {$_.Source -eq "user"}; Descending = $true} |
            Select-Object -First 1
    }

    if (-not $default) {
        throw "Default template not found (default.json)."
    }

    return $default
}

function Read-RenderKitTemplateFile {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        return Get-Content $Path -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Invalid JSON in template '$Path'"
    }
}

function Write-RenderKitTemplateFile {
    param(
        [Parameter(Mandatory)]
        [object]$Template,
        [Parameter(Mandatory)]
        [string]$Path
    )

    $Template | ConvertTo-Json -Depth 20 |
        Set-Content -Path $Path -Encoding UTF8
}

function Get-ProjectTemplate {

    param(
        [string]$TemplateName
    )

    $resolved = Resolve-ProjectTemplate -TemplateName $TemplateName

    $json = Read-RenderKitTemplateFile -Path $resolved.Path
    Confirm-Template -Template $json

    return [PSCustomObject]@{
        Name     = $resolved.Name
        Source   = $resolved.Source
        Folders  = $json.Folders
        Mappings = $json.Mappings
    }
}

function Confirm-Template {
    param(
        [Parameter(Mandatory)]
        $Template
    )

    if (!($Template.Version)) {
        Write-RenderKitLog -Level Error -Message "Template is missing 'Version' property"
    }

    if (!($Template.Name)) {
        Write-RenderKitLog -Level Error -Message "Template is missing 'Name' property."
    }
    if (!($Template.Folders)) {
        Write-RenderKitLog -Level Error -Message "Template is Missing 'Folders' property."
    }

    if ($Template.Version -ne "1.0") { #TODO Implement Logic, that reads from .psd1 the actual schema version 
        Write-RenderKitLog -Level Warning -Message "Unsupported Template Version '$($Template.Version)'."
    }

    foreach ($folder in $Template.Folders){
        Test-FolderNode $folder
    }
}

function Test-FolderNode {
    param(
        [Parameter(Mandatory)]
        $Folder
    )

    if (!($Folder.Name)) {
        Write-RenderKitLog -Level Error -Message "Folder node missing 'Name' Property"
    }

    if (!($Folder.PSObject.Properties.Name -contains "SubFolders")) {
        Write-RenderKitLog -Message "Folder '$($Folder.Name)' missing 'SubFolders' property"
    }

    if($Folder.SubFolders) {
        foreach ($sub in $Folder.SubFolders) {
            Test-FolderNode $sub
        }
    }
}
