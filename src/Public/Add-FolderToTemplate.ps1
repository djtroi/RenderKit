#todo buggy
function Add-FolderToTemplate {
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$TemplateName,
        [Parameter(Mandatory, Position = 1)]
        [string]$FolderName,
        [string]$Mapping

    )
    $root = Get-RenderKitRoot
    $templateRoot = Join-Path $root "templates\$TemplateName.json"

    if (!(Test-Path $templateRoot)) {
        Write-RenderKitLog -Level Error -Message "$TemplateName nor found. Is the name correct?"
    }

    # if ($FolderName) {
    #     Write-RenderKitLog -Level Error -Message "$FolderName already exists."
    # }

    $json = Get-Content $templateRoot | ConvertFrom-Json 

    $json.Folders += @{
        FolderName      =   $folder
        Mapping         =   if (!($Mapping)) { $Mapping } else { $null } 
    }

    $json | ConvertTo-Json -Depth 5 | 
    Add-Content $templateRoot -Encoding UTF8 

    Write-RenderKitLog -Level Info -Message "Folder ""$FolderName"" added to $TemplateName"
}