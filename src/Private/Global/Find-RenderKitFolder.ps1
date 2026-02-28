function Find-RenderKitFolder {
    param(
        [System.Collections.Generic.List[RenderKitFolder]]$Folders,
        [string]$Name
    )

    foreach ($folder in $Folders) {
        if ($folder.Name -eq $Name) {
            return $folder
        }

        if ($folder.SubFolders.Count -gt 0) {
            $result = Find-RenderKitFolder -Folders $folder.SubFolders -Name $Name
            if($result) { return $result }
        }
    }

    return $null
}