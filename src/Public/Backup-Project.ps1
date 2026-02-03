# 1. Call Function
# 2. Validation 
#   -> Does the project exist?
#   -> Can the function write?
# 3. Scanning
#   -> Find Cache-Files (Software based)
#   -> Find Proxy-Files (path based)
# 4. Dry-Run Function 
# 5. Cleanup 
#   -> Delete Cache
#   -> Delete Proxies (optional)
# 6. Backup
#   -> Create Zip 
#   -> Password (optional)
# 7. Logging & Result

New-Alias -Name Archive-Project -Value Backup-Project
New-Alias -Name archive -Value Backup-Project
New-Alias -Name bk -Value Backup-Project
New-Alias -Name backup -Value Backup-Project
function Backup-Project{
    param(
        [Parameter(Mandatory)]
        [string]$ProjectName,
        [string]$Path,
        [string]$Software = @("DaVinci", "Adobe", "General"),
        [switch]$KeepEmptyFolders,
        [switch]$DryRun
    )
    $config = Get-RenderKitConfig
    if (!$Path) { $Path = $config.DefaultProjectPath}

    $projectPath = Get-ProjectPath -ProjectName $ProjectName -BasePath $Path
    $rules = Get-CleanupRules -Software $Software

    Write-Verbose "Cleaning project artifacts..."

    Remove-ProjectArtifacts -ProjectPath $projectPath -Rules $rules -DryRun:$DryRun

    if (!($KeepEmptyFolders)){
        Remove-EmptyFolders -Path $projectPath -DryRun:$DryRun
    }
    if (!($DryRun)){
        $zipPath = "$projectPath.zip"
        Compress-Project -ProjectPath $projectPath -DestinationPath $zipPath
        Write-Verbose "Backup created: $zipPath"
    }
}