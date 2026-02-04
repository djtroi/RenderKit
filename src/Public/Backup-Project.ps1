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
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectName,
        [string]$Path,
        [string]$Software = @("DaVinci", "Adobe", "General"),
        [switch]$KeepEmptyFolders,
        [switch]$DryRun
    )
    Write-Verbose "Resolving RenderKit project '$ProjectName'"
    $project = Get-RenderKitProject -ProjectName $ProjectName -Path $Path
    $projectRoot = $project.RootPath

    Write-Verbose "Validated RenderKit project at $projectRoot"
    Write-Verbose "PRoject ID: $($project.id)"
    if (!($PSCmdlet.ShouldProcess(
        $projectRoot,
        "Remove cache/proxy files and create backup archive"
    ))){
        return
    }

    $rules = Get-CleanupRules -Software $Software

    Write-Verbose "Cleaning project artifacts..."

    Remove-ProjectArtifacts -ProjectPath $projectRoot -Rules $rules -DryRun:$DryRun

    if (!($KeepEmptyFolders)) {
        Remove-EmptyFolders -Path $projectRoot -DryRun:$DryRun
    }

    if (!($DryRun)){
        $zipPath = "$projectRoot.zip"
        Compress-Project -ProjectPath $projectRoot -DestinationPath $zipPath
        Write-Verbose "Backup created: $zipPath"
    }
    else{
        Write-Verbose "DryRun enabled -no files were deleted or archived"
    }
return [PSCustomObject]@{
    ProjectName             = $project.Name
    ProjectId               = $project.id
    RootPath                = $projectRoot
    BackupPath              = if ($DryRun) { $null } else { "$projectRoot.zip"}
    DryRun                  = $DryRun
}


$manifest = New-BackupManifest `
-Project $project `
-Options @{
    software            = $Software
    keepEmptyFolders    = $KeepEmptyFolders.IsPresent
    dryRun              = $DryRun.IsPresen
}

Save-BackupManifest `
-Manifest $manifest `
-ProjectRoot $projectRoot
}