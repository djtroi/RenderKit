#todo buggy
function Add-FolderToTemplate {
    param(
    [Parameter(Mandatory, Position = 0)]    
    [string]$TemplateName,
    [Parameter(Mandatory, Position = 1)]
    [string]$FolderPath,
    [string]$Mapping
    )

 $root = Get-RenderKitRoot
    $templatePath = Join-Path $root "templates\$TemplateName.json"

    if (!(Test-Path $templatePath)) {
        throw "Template '$TemplateName' not found."
    }

    $json = Get-Content $templatePath -Raw | ConvertFrom-Json

    # Ensure Folders exists
    if (-not $json.PSObject.Properties['Folders']) {
        $json | Add-Member -MemberType NoteProperty -Name Folders -Value @()
    }

    $parts = $FolderPath -split '[\\/]'
    $currentLevel = $json.Folders

    foreach ($part in $parts) {

        $existing = $currentLevel | Where-Object Name -eq $part

        if (-not $existing) {

            $newFolder = [PSCustomObject]@{
                Name       = $part
                Mapping    = $null
                SubFolders = @()
            }

            $currentLevel = @($currentLevel) + $newFolder

            $existing = $newFolder
        }

        # Ensure SubFolders exists
        if (-not $existing.PSObject.Properties['SubFolders']) {
            $existing | Add-Member -MemberType NoteProperty -Name SubFolders -Value @()
        }

        $currentLevel = $existing.SubFolders
    }

    # Mapping nur auf finalem Ordner setzen
    if ($Mapping) {
        $existing.Mapping = $Mapping
    }

    $json | ConvertTo-Json -Depth 20 |
        Set-Content $templatePath -Encoding UTF8

    Write-RenderKitLog -Level Info -Message "Folder '$FolderPath' added to '$TemplateName'"
}

#no return in the .json somehow.