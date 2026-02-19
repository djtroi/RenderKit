function Get-ProjectTemplate {
    param(
        [Parameter(Mandatory)]
        [string]$TemplateName
    )
    $root = Get-RenderKitRoot
    $templatePath = Join-Path $root "templates\$TemplateName.json" 

    if(!(Test-Path $templatePath)) {
        Write-RenderKitLog -Level Error -Message " $TemplateName not found at $templatePath"
    }

    $raw = Get-Content $templatePath -Raw 

    try {
        $json = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-RenderKitLog -Level Error -Message " Template $TemplateName contains invalid JSON" 
    }

    Confirm-Template -Template $json 

    return $json
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
        Write-RenderKitLog -Level Error -Message "Template is Mssing 'Folders' property."
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
        Write-RenderKitLog "Folder '$($Folder.Name)' missing 'SubFolders' property"
    }

    if($Folder.SubFolders) {
        foreach ($sub in $Folder.SubFolders) {
            Test-FolderNode $sub
        }
    }
}

function New-ProjectFolderRecursive {
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,
        [Parameter(Mandatory)]
        $FolderNode
    )

    $currentPath = Join-Path $BasePath $FolderNode.Name 

    if (!(Test-Path $currentPath)) {
        New-Item -ItemType Directory -Path $currentPath | Out-Null 
    }

    if ($FolderNode.SubFolders) {
        foreach ($sub in $FolderNode.SubFolders) {
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
        New-Item -ItemType Directory -Path $renderKitPath -ErrorAction Stop | Out-Null

        #Metadata
        $metadata = New-RenderKitProjectMetadata `
        -ProjectName $ProjectName `
        -TemplateName $templateInfo.Name `
        -TemplateSource $templateInfo.Source 

        Write-RenderKitProjectMetadata `
        -ProjectRoot $ProjectRoot `
        -Metadata $metadata

}