#Workflow could be like: 
# Set-ProjectRoot "D:\Projects"
# Create-Project "WeddingVideo_Bloom"
# or
# Create-Project "SpecialForces" -Path E:\VerySpecialClient
function Create-Project{
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$ProjectName,
        [string]$Path,
        [string]$TemplatePath
    )
    $config = Get-RenderKitConfig
    if(!($Path)){
        if(!($config.DefaultProjectPath)){
            throw "No default project path set. Use Set-ProjectRoot first or provide a path using the -Path parameter"
        }
        $Path = $config.DefaultProjectPath
    }

    if(!(Test-Path $Path)){
        throw "Target path does not exist: $Path"
    }

    if (!($TemplatePath)){
        $TemplatePath = Join-Path $PSScriptRoot "..\Template\default.json"
    }
    try{
        $template = Read-ProjectTemplate -Path $TemplatePath 
    }
    catch{
        throw "Template validation failed $_"
    }

    $projectRoot = Join-Path $Path $ProjectName

    if(Test-Path $projectRoot){
        throw "Project already exist: $projectRoot"
    }

    $template = Get-Content $TemplatePath -Raw | ConvertFrom-Json
    try{
    New-FolderTree -Root $projectRoot -Structure $template.folders
    
    Write-Host "Project created"
    }
    catch{
        throw "Failed to create project folders: $_"
    }
}