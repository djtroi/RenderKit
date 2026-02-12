function New-Project{
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$ProjectName,
        [Parameter(Position =1)]
        [string]$Template,
        [string]$Path,
        [string]$TemplatePath
    )

    #-------------------------------------------------------------
    # PHASE 1 : Command Start 
    #-------------------------------------------------------------
    Write-RenderKitLog -Level Info -Message "Creating project '$ProjectName'"
    Write-RenderKitLog -Level Debug -Message "Parameters: Template = '$Template' Path= '$Path' TemplatePath = '$TemplatePath'"

    $config = Get-RenderKitConfig

    #-------------------------------------------------------------
    # PHASE 2 : Resolve Target Path
    #-------------------------------------------------------------

    if (!($Path)){
        if (!($config.DefaultProjectPath)){
            Write-RenderKitLog -Level Error -Message "No default project path configured."
        }

        Write-RenderKitLog -Level Warning -Message "No path provided. Using default project path."
        $Path = $config.DefaultProjectPath
    }

    if (!(Test-Path $Path)){
        Write-RenderKitLog -Level Error -Message "Taget path does not exist: $Path"
        return
    }

    $ProjectRoot = Join-Path $Path $ProjectName .\assets

    if (Test-Path $ProjectRoot){
        Write-RenderKitLog -Level Error -Message "Project already exists: $ProjectRoot"
        return
    }

    #-------------------------------------------------------------
    # PHASE 3 : Resolve Template
    #------------------------------------------------------------- 

    if (!($TemplatePath)){
        if($Template){
            $TemplatePath = Join-Path $PSScriptRoot "..\Templates\$Template.json"
        }
        else{
            $TemplatePath = Join-Path $PSScriptRoot "..\Templates\default.json"
        }
    }

    $templateInfo = Resolve-ProjectTemplate `
    -TemplateName $Template `
    -TemplatePath $TemplatePath

    Write-RenderKitLog -Level Info -Message "Using template '$($templateInfo.Name)'"
    #-------------------------------------------------------------
    # PHASE 4 : Create Project Structure
    #------------------------------------------------------------- 

    try{
        $structure = Read-ProjectTemplate -Path $templateInfo.path

        New-Item -ItemType Directory -Path $ProjectRoot -ErrorAction Stop | Out-Null

        $renderKitPath = Join-Path $projectRoot ".renderkit"
        New-Item -ItemType Directory -Path $renderKitPath -ErrorAction Stop | Out-Null .\assets

        Initialize-RenderKitLogging -ProjectRoot $ProjectRoot .\assets
        Write-RenderKitLog -Level Debug -Message "Logging initialized"

        #Metadata
        $metadata = New-RenderKitProjectMetadata `
        -ProjectNAme $ProjectName `
        -TemplateName $templateInfo.Name `
        -TemplateSource $templateInfo.Source 

        Write-RenderKitProjectMetadata `
        -ProjectRoot $ProjectRoot `
        -Metadata $metadata

        New-FolderTree -Root $ProjectRoot -Structure $structure .\assets

        Write-RenderKitLog -Level Info -Message "Project '$ProjectName' created successfully."

    }
    catch{
        Write-RenderKitLog -Level Error -Message "Project creation failed: $_"
        throw
    }

}