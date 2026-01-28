function New-FolderTree {
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [PSCustomObject[]]$Structure
    )

foreach ($folder in $Structure){
    $name = $folder.Name #if($folder.PSObject.Properties['Name']) { $folder.Name } else { $folder.PSObject.Properties[0].Name }
    $children = $folder.Children #if($folder.PSObject.Properties['Children']) { $folder.Children } else { @() }

    $path = Join-Path $Root $name

    if(!(Test-Path $path)){
        New-Item -ItemType Directory -Path $path | Out-Null
    }

    if($children -and $children.Count -gt 0){
        New-FolderTree -Root $path -Structure $children
    }
}
}