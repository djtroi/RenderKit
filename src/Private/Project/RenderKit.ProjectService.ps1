function Resolve-ProjectPath {
    param(
        [string]$ProjectName,
        [string]$Path
    )

    $config = Get-RenderKitConfig

    # Default Path Handling
    if (-not $Path) {
        if (-not $config.DefaultProjectPath) {
            Write-RenderKitLog -Level Error -Message "No default project path configured. Use 'Set-ProjectRoot first'"
            throw $_
        }

        Write-RenderKitLog -Level Warning -Message "No path provided. Using default project path."
        $Path = $config.DefaultProjectPath
    }

    # Validate Path
    if (-not (Test-Path $Path)) {
        Write-RenderKitLog -Level Error -Message "Target path does not exist: $Path"
        throw $_
    }

    # Build Project Root
    $ProjectRoot = Join-Path $Path $ProjectName

    if (Test-Path $ProjectRoot) {
        Write-RenderKitLog -Level Error -Message "Project already exists: $ProjectRoot"
        throw $_
    }

    return $ProjectRoot
}

function New-RenderKitProjectFromTemplate {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        "PSUseShouldProcessForStateChangingFunctions",
        "",
        Justification = "internal function. The public function already has a DryRun feature")]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectName,
        [Parameter(Mandatory)]
        [string]$ProjectRoot,
        [Parameter(Mandatory)]
        $Template
    )

    try {
        Write-RenderKitLog -Level Debug -Message "Creating new ProjectMetaDataFolder"
        New-ProjectMetadataFolder `
            -ProjectName $ProjectName `
            -ProjectRoot $ProjectRoot `
            -TemplateName $Template.Name `
            -TemplateSource $Template.Source
        Initialize-RenderKitLogging -ProjectRoot $ProjectRoot
        Write-RenderKitLog -Level Debug -Message "Logging initialized"
    }
    catch {
        Write-RenderKitLog -Level Error -Message "Couldn't create .renderkit folder"
        throw $_
    }

    foreach ($folder in $Template.Folders){
        New-ProjectFolderRecursive -BasePath $ProjectRoot -FolderNode $folder
    }
}

function New-ProjectFolderRecursive {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        "PSUseShouldProcessForStateChangingFunctions",
        "",
        Justification = "internal function. The public function already has a DryRun feature")]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,
        [Parameter(Mandatory)]
        $FolderNode
    )

    if (-not $FolderNode -or -not $FolderNode.Name) {
        return
    }

    $currentPath = Join-Path $BasePath $FolderNode.Name

    if (!(Test-Path $currentPath)) {
        New-Item -ItemType Directory -Path $currentPath | Out-Null
    }

    $children = $null
    if ($FolderNode.PSObject.Properties.Name -contains "SubFolders") {
        $children = $FolderNode.SubFolders
    } elseif ($FolderNode.PSObject.Properties.Name -contains "Children") {
        $children = $FolderNode.Children
    }

    if ($children) {
        foreach ($sub in $children) {
            New-ProjectFolderRecursive -BasePath $currentPath -FolderNode $sub
        }
    }
}

function New-ProjectMetadataFolder {
    [CmdletBinding(SupportsShouldProcess)]

    param(
        [Parameter(Mandatory)]
        [string]$ProjectName,

        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [string]$TemplateName,

        [Parameter(Mandatory)]
        [string]$TemplateSource
    )

    $renderKitPath = Join-Path $ProjectRoot ".renderkit"

    New-Item -ItemType Directory -Path $renderKitPath -Force | Out-Null

    $metadata = New-RenderKitProjectMetadata `
        -ProjectName $ProjectName `
        -TemplateName $TemplateName `
        -TemplateSource $TemplateSource
    if ($PSCmdlet.ShouldProcess($ProjectName, "Write RenderKit ProjectMetadata")){
        Write-RenderKitProjectMetadata `
            -ProjectRoot $ProjectRoot `
            -Metadata $metadata
    }
}

function Get-Platform {
    if ($IsWindows) { return "windows" }
    if ($isMacOs) { return "macos" }
    if ($IsLinux) { return "linux" }
    else {
        return "unknown"
    }
}

function Get-RenderKitProjectMetadataPath{
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    return Join-Path -Path (Join-Path -Path $ProjectRoot -ChildPath ".renderkit") -ChildPath "project.json"
}


function New-RenderKitProjectMetadata {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        "PSUseShouldProcessForStateChangingFunctions",
        "",
        Justification = "Function only creates an in-memory object and does not modify state"
    )]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
     Justification = 'Data counts a a singular noun')]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectName,
        [Parameter(Mandatory)]
        [string]$TemplateName,
        [Parameter(Mandatory)]
        [string]$TemplateSource
    )

    return [PSCustomObject]@{
        tool            = "RenderKit"
        schemaVersion   = "1.0"

        project = @{
            id          = ([guid]::NewGuid()).guid
            name        = $ProjectName
            createdAt   = (Get-Date).ToString("o") # ISO 8601
            createdBy   = $env:USERNAME
            platform    = Get-Platform
            toolVersion = $script:RenderKitModuleVersion #$script:RenderKitVersion
        }

        paths = @{
            root        = "."
        }

        template = @{
            name        = $TemplateName
            source      = $TemplateSource
        }
    }
}

function Write-RenderKitProjectMetadata{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
     Justification = 'Data counts here as singular noun')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,
        [Parameter(Mandatory)]
        [object]$Metadata
    )

    $renderKitDir = Join-Path $ProjectRoot ".renderkit"

    if (!(Test-Path $renderKitDir)){
        New-Item -ItemType Directory -Path $renderKitDir | Out-Null
    }
    $jsonPath = Get-RenderKitProjectMetadataPath -ProjectRoot $ProjectRoot

    $Metadata |
    ConvertTo-Json -Depth 6 |
    Set-Content -Path $jsonPath -Encoding UTF8
}

function Remove-RenderKitProjectDirectory {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        "PSUseShouldProcessForStateChangingFunctions",
        "",
        Justification = "internal function. The public function already has a DryRun feature and ShouldProcess support"
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
        Write-RenderKitLog -Level Error -Message "Project folder not found: $ProjectRoot"
        throw "Project folder not found: $ProjectRoot"
    }

    Remove-Item -LiteralPath $ProjectRoot -Recurse -Force -ErrorAction Stop
}

function Rename-RenderKitProjectDirectory {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        "PSUseShouldProcessForStateChangingFunctions",
        "",
        Justification = "internal function. The public function already has a DryRun feature and ShouldProcess support"
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,
        [Parameter(Mandatory)]
        [string]$NewProjectRoot
    )

    if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
        Write-RenderKitLog -Level Error -Message "Project folder not found: $ProjectRoot"
        throw "Project folder not found: $ProjectRoot"
    }

    if (Test-Path -LiteralPath $NewProjectRoot) {
        Write-RenderKitLog -Level Error -Message "Target project path already exists: $NewProjectRoot"
        throw "Target project path already exists: $NewProjectRoot"
    }

    $newName = Split-Path -Path $NewProjectRoot -Leaf
    Rename-Item -LiteralPath $ProjectRoot -NewName $newName -ErrorAction Stop
}

function Update-RenderKitProjectName {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        "PSUseShouldProcessForStateChangingFunctions",
        "",
        Justification = "internal function. The public function already has a DryRun feature and ShouldProcess support"
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,
        [Parameter(Mandatory)]
        [string]$NewProjectName,
        [Parameter(Mandatory)]
        [string]$ExpectedProjectId
    )

    $metadataPath = Get-RenderKitProjectMetadataPath -ProjectRoot $ProjectRoot
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        Write-RenderKitLog -Level Error -Message "Project metadata not found: $metadataPath"
        throw "Project metadata not found: $metadataPath"
    }

    try {
        $metadata = Get-Content -LiteralPath $metadataPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-RenderKitLog -Level Error -Message "Invalid project metadata JSON in '$metadataPath'."
        throw "Invalid project metadata JSON in $metadataPath"
    }

    if (-not $metadata.project -or -not $metadata.project.id -or $metadata.tool -ne "RenderKit") {
        Write-RenderKitLog -Level Error -Message "Invalid RenderKit project metadata schema in '$metadataPath'."
        throw "Invalid RenderKit project metadata schema"
    }

    if ([string]$metadata.project.id -ne $ExpectedProjectId) {
        Write-RenderKitLog -Level Error -Message "Project metadata id mismatch in '$metadataPath'."
        throw "Project metadata id mismatch in $metadataPath"
    }

    $metadata.project.name = $NewProjectName
    $metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metadataPath -Encoding UTF8

    return $metadata
}