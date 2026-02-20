#todo buggy
function Add-FolderToTemplate {
    param(
    [Parameter(Mandatory, Position = 0)]    
    [string]$TemplateName,
    [Parameter(Mandatory, Position = 1)]
    [string]$FolderPath,
    [string]$MappingId
    )

    $templatePath = Get-RenderKitUserTemplatePath -TemplateName $TemplateName

    if (!(Test-Path $templatePath)) {
        Write-RenderKitLog -Level Error -Message "Template '$TemplateName' not found."
    }

    $json = Read-RenderKitTemplateFile -Path $templatePath

    if (!($json.Folders)) {
        $json | Add-Member -MemberType NoteProperty -Name Folders -Value ([System.Collections.ArrayList]::new()) -Force
    }
    elseif ($json.Folders -isnot [System.Collections.ArrayList]) {
        $json.Folders = [System.Collections.ArrayList]@($json.Folders)
    }

    $parts = $FolderPath -split '[\\/]'
    $currentLevel = $json.Folders

    foreach ($part in $parts) {

        $existing = $currentLevel | Where-Object Name -eq $part

        if (!($existing)) {

            $newFolder = [PSCustomObject]@{
                Name            = $part
                MappingId       = $null
                SubFolders      = [System.Collections.ArrayList]::new()
            }

            #$currentLevel += $newFolder
            $null = $currentLevel.Add($newFolder)
            $existing = $newFolder

        }
        if (!($existing.SubFolders -isnot [System.Collections.ArrayList])){
            #$existing | Add-Member -MemberType NoteProperty -Name SubFolders -Value @() -Force
            $existing.SubFolders = [System.Collections.ArrayList]@($existing.SubFolders)
        }

        $currentLevel = $existing.SubFolders
    }

    # Mapping nur auf finalem Ordner setzen
    if ($MappingId) {
        $existing.MappingId = $MappingId
        Write-RenderKitLog -Level Debug -Message "Mapping found: $MappingId"
    }

    Write-RenderKitTemplateFile -Template $json -Path $templatePath

    Write-RenderKitLog -Level Info -Message "Folder '$FolderPath' added to '$TemplateName'"
}
