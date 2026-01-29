function New-FolderTree {
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [PSCustomObject[]]$Structure
    )
$Structure = $Structure | Where-Object { $_ -and $_.Name }

foreach ($folder in $Structure){
#    if (!($folder.Name)){
#        throw "Invalid folder object - Name is missing"
#    }

    $path = Join-Path $Root $folder.Name
    if(!(Test-Path $path)){
        New-Item -ItemType Directory -Path $path | Out-Null
    }

if ($folder.Children -and $folder.Children.Count -gt 0){
    New-FolderTree -Root $path -Structure $folder.Children
}
}
}