function New-Project {
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,
        [Parameter(Position = 1)]
        [string]$Template,
        [string]$Path
    )
    #define Template
    $ProjectRoot = Resolve-ProjectPath -ProjectName $Name -Path $Path 
    
    #project path
    if(Test-Path $ProjectRoot) {
        Write-RenderKitLog -Level Error -Message "Project '$Name' already exists at '$rootPath'."
    }

    Write-RenderKitLog -Level Info -Message "Creating project '$Name' at '$ProjectRoot' using template '$Template'."

    #load template
    $templateObject = Get-ProjectTemplate -TemplateName $Template

    #create root
    
    try{
    New-ProjectMetadataFolder `
    -ProjectName $Name `
    -ProjectRoot $ProjectRoot `
    -TemplateName $templateObject.Name `
    -TemplateSource $templateObject.Source
    Initialize-RenderKitLogging -ProjectRoot $ProjectRoot 
    Write-RenderKitLog -Level Debug -Message "Logging initialized"
    }
    catch{
        throw $_ 
        Write-RenderKitLog -Level Error -Message "Couldn't create .renderkit folder"
    }
    #create foldertree
    foreach ($folder in $templateObject.Folders){
        New-ProjectFolderRecursive -BasePath $ProjectRoot -FolderNode $folder
    }

    Write-RenderKitLog -Level Info -Message "Project '$Name' created successfully."
}