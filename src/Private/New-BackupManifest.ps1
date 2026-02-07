function New-BackupManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Project,
        [Parameter(Mandatory)]
        [hashtable]$Options,
        [hashtable]$Statistics,
        [hashtable]$Archive,
        [array]$CleanupSummary
    )
return [PSCustomObject]@{
    schemaVersion = "1.0" 

    backup = @{
    id              = [guid]::NewGuid().ToString()
    createdAt       = (Get-Date).ToString("o")
    createdBy       = $ENV:USERNAME
    machine         = $ENV:COMPUTERNAME
    tool = @{
        name        = "RenderKit"
        version     = $script:ModuleVersion
    }
}

project = @{
    id              = $Project.id
    name            = $Project.Name
    rootPath        = $Project.RootPath
}
    options         = $Options
    statistics      = $Statistics
    archive         = $Archive
    cleanup         = $CleanupSummary
}
}