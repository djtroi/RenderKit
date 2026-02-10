function Resolve-ProjectTemplate {
    param(
        [string]$TemplateName,
        [string]$TemplatePath
    )
    Write-Verbose "Checking TemplatePath" 
    if ($TemplatePath){
        if(!(Test-Path $TemplatePath)){
            #Write-RenderKitLog "Template not found at path: $TemplatePath" -Level Error
        }

        return @{
            Name = [IO.Path]::GetFileNameWithoutExtension($TemplatePath)
            Path = $TemplatePath
            Source = "custom"
        }

        #Name = Template Folder
        if ($TemplateName) {
            $templates = Get-RenderKitTemplates
            $match = $templates | Where-Object Name -eq $TemplateName 


            if (!$match){
                Write-Verbose "Template '$TemplateName' not found. Available: $($templates.Name -join ', ')" 
            }

            return @{
                Name = $match.Name
                Path = $match.Path
                Source = "builtin"
            }

        }
    }

    #Default Path
    $defaultPath = Join-Path $PSScriptRoot "..\Templates\default.json"

    return @{
        Name = "default"
        Path = $defaultPath
        Source = "builtin"
    }
}