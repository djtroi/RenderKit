function Get-RenderKitTemplate {
    param(
        [ValidateSet("all", "system", "user")]
        [string]$Source = "all"
    )

    $templates = @()

    if ($Source -in @("all", "system")) {
        $systemRoot = Get-RenderKitSystemTemplatesRoot
        if (Test-Path $systemRoot) {
            $templates = Get-ChildItem $systemRoot -Filter "*.json" | ForEach-Object {
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
            $templates = Get-ChildItem $userRoot -Filter "*.json" | ForEach-Object {
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

    $templates = Get-RenderKitTemplate

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
            Write-RenderKitLog -Level Error -Message "Template '$TemplateName' not found."
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
        Write-RenderKitLog -Level Error -Message "Default template not found (default.json)."
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
        return Read-RenderKitJsonFile -Path $Path
    }
    catch {
        Write-RenderKitLog -Level Error -Message "Invalid JSON in template '$Path'."
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

    Confirm-Template -Template $Template -RequireWritable | Out-Null
    Write-RenderKitJsonFileAtomic `
        -Value $Template `
        -Path $Path `
        -Depth 20 |
        Out-Null
}

function Get-ProjectTemplate {

    param(
        [string]$TemplateName
    )

    $resolved = Resolve-ProjectTemplate -TemplateName $TemplateName

    $json = Read-RenderKitTemplateFile -Path $resolved.Path
    Confirm-Template -Template $json | Out-Null

    return [PSCustomObject]@{
        Name         = $resolved.Name
        Version      = $json.Version
        Source       = $resolved.Source
        Folders      = $json.Folders
        Mappings     = $json.Mappings
        Deliverables = $json.Deliverables
    }
}

function Confirm-Template {
    param(
        [Parameter(Mandatory)]
        $Template,

        [switch]$RequireWritable
    )

    if (-not ($Template.PSObject.Properties.Name -contains 'Version') -or
        [string]::IsNullOrWhiteSpace([string]$Template.Version)) {
        throw "Template is missing 'Version' property."
    }

    if (-not ($Template.PSObject.Properties.Name -contains 'Name') -or
        [string]::IsNullOrWhiteSpace([string]$Template.Name)) {
        throw "Template is missing 'Name' property."
    }
    if (-not ($Template.PSObject.Properties.Name -contains 'Folders') -or
        $null -eq $Template.Folders) {
        throw "Template is missing 'Folders' property."
    }

    $compatibility = Test-RenderKitArtifactCompatibility `
        -ArtifactType Template `
        -Version ([string]$Template.Version)
    if (-not $compatibility.CanRead -or
        ($RequireWritable -and -not $compatibility.CanWrite)) {
        throw "Template version '$($Template.Version)' is not supported for this operation (status: $($compatibility.Status))."
    }
    if ($compatibility.Status -eq 'UpgradeAvailable') {
        Write-RenderKitLog -Level Warning -Message (
            "Template version '$($Template.Version)' is supported but version " +
            "'$($compatibility.CurrentVersion)' is current."
        )
    }

    foreach ($folder in $Template.Folders){
        Test-FolderNode $folder
    }

    return $compatibility
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
