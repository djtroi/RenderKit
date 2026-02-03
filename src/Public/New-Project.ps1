New-Alias -Name Create-Project -Value New-Project
New-Alias -Name create -Value New-Project
New-Alias -Name np -Value New-Project
function New-Project{
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
    $projectRoot = Join-Path $Path $ProjectName
    if(Test-Path $projectRoot){
        throw "Project already exists: $projectRoot"
    }
    try{
        $structure = Read-ProjectTemplate -Path $TemplatePath 
        #Create Project Root Folder
        New-Item -ItemType Directory -Path $projectRoot | Out-Null

        #first things first create .renderkit
        $renderKitPath = Join-Path $projectRoot ".renderkit"
        New-Item -ItemType Directory -Path $renderKitPath | Out-Null

        #project .json
        $metadata = New-RenderKitProjectMetadata -ProjectName $ProjectName -TemplateName "default" -TemplateSource (Split-Path $TemplatePath -Leaf)
        $projectJsonPath = Join-Path $renderKitPath "project.json"

        $metadata | ConvertTo-Json -Depth 5 | Set-Content -Path $projectJsonPath -Encoding UTF8

        New-FolderTree -Root $projectRoot -Structure $structure
        Write-Host "Project created successfully"
    }
    catch{
        throw "Template validation failed $_"
    }

    $projectRoot = Join-Path $Path $ProjectName


    $template = Get-Content $TemplatePath -Raw | ConvertFrom-Json
    try{
    New-FolderTree -Root $projectRoot -Structure $template.folders
    
    Write-Host "Project created"
    }
    catch{
        throw "Failed to create project folders: $_"
    }
}