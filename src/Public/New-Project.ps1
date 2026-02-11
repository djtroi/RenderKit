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
            Write-Verbose "No default project path set. Use Set-ProjectRoot first or provide a path using the -Path parameter" 
        }
        $Path = $config.DefaultProjectPath
    }

    if(!(Test-Path $Path)){
        Write-Verbose "Target path does not exist: $Path" 
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
        Write-Verbose "Project already exists: $projectRoot" 
    }
    $templateInfo = Resolve-ProjectTemplate `
    -TemplateName $Template `
    -TemplatePath $TemplatePath
    Write-Verbose "Resolving ProjectTemplate $Template $TemplatePath" 

    try{

        $structure = Read-ProjectTemplate -Path $templateInfo.Path #-Path $TemplatePath 
        Write-Verbose "creating Project Root Folder" 
        New-Item -ItemType Directory -Path $projectRoot | Out-Null

        #first things first create .renderkit
        $renderKitPath = Join-Path $projectRoot ".renderkit"
        New-Item -ItemType Directory -Path $renderKitPath | Out-Null

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
        Write-Verbose "Project created successfully"
    }
    catch{
        throw "Template validation failed $_"
    }
}