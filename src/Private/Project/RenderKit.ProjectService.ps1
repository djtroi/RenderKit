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

    Write-RenderKitProjectMetadata `
        -ProjectRoot $ProjectRoot `
        -Metadata $metadata
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

    return Join-Path $ProjectRoot ".renderkit\project.json"
}

function New-RenderKitProjectMetadata {
    [CmdletBinding()]
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
