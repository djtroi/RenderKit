#New-Alias -Name Create-Project -Value New-Project
#New-Alias -Name create -Value New-Project
#New-Alias -Name np -Value New-Project
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
    $config = Get-RenderKitConfig 
    if(!($Path)){
        if(!($config.DefaultProjectPath)){
            Write-RenderKitLog -Message "No default project path set. Use Set-ProjectRoot first or provide a path using the -Path parameter" -Level Error
        }
        $Path = $config.DefaultProjectPath
    }

    if(!(Test-Path $Path)){
        Write-RenderKitLog -Message "Target path does not exist: $Path" -Level Error
    }

    if (!($TemplatePath)){
        if ($Template){
            $TemplatePath = Join-Path $PSScriptRoot "..\Templates\$Template.json"
        }
        Else {
            $TemplatePath = Join-Path $PSScriptRoot "..\Templates\default.json"
        }
        
    }
    $projectRoot = Join-Path $Path $ProjectName
    if(Test-Path $projectRoot){
        Write-RenderKitLog -Message "Project already exists: $projectRoot" -Level Error
    }
    
    $templateInfo = Resolve-ProjectTemplate `
    -TemplateName $Template `
    -TemplatePath $TemplatePath
    Write-RenderKitLog -Message "Resolving ProjectTemplate $Template $TemplatePath" -Level Debug

    try{

        $structure = Read-ProjectTemplate -Path $templateInfo.Path #-Path $TemplatePath 
        Write-RenderKitLog -Message "creating Project Root Folder"  -Level Debug
        New-Item -ItemType Directory -Path $projectRoot | Out-Null  
        #first things first create .renderkit
        $renderKitPath = Join-Path $projectRoot ".renderkit"
        New-Item -ItemType Directory -Path $renderKitPath | Out-Null 

        #Log Init
        Initialize-RenderKitLogging -ProjectRoot $projectRoot
        Write-RenderKitLog -Message "Logging initialized" -Level Debug

        #project .json
        $metadata = New-RenderKitProjectMetadata `
        -ProjectName $ProjectName `
        -TemplateName $templateInfo.Name `
        -TemplateSource $templateInfo.Source

        #$projectJsonPath = Join-Path $renderKitPath "project.json"
        #$metadata | ConvertTo-Json -Depth 5 | Set-Content -Path $projectJsonPath -Encoding UTF8

        Write-RenderKitProjectMetadata `
        -ProjectRoot $projectRoot `
        -Metadata $metadata


        New-FolderTree -Root $projectRoot -Structure $structure
        Write-RenderKitLog -Message "Project created successfully" -Level Info
    }
    catch{
        Write-RenderKitLog -Message "Project Creation failed $_" -Level Error
    }
}