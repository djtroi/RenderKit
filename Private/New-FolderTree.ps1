function New-FolderTree {
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [hashtable]$Structure
    )

    foreach ($folderName in $Structure.Keys){
        $currentPath = Join-Path $Root $folderName
        if (!(Test-Path $currentPath)){
            New-Item -ItemType Directory -Path $currentPath | Out-Null
        }
        $children = $Structure[$folderName]
        if ($children.Count -gt 0){
            New-FolderTree -Root $currentPath -Structure $children 
        }
    }
}
$template = Get-Content $TemplatePath -Raw | ConvertFrom-Json
New-FolderTree -Root $projectRoot -Structure $template.folders