function New-BackupManifest {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        "PSUseShouldProcessForStateChangingFunctions",
        "",
        Justification = "internal function. The public function already has a DryRun feature")]
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

    if (-not $Statistics) {
        $Statistics = @{}
    }
    if (-not $Archive) {
        $Archive = @{}
    }
    if (-not $CleanupSummary) {
        $CleanupSummary = @()
    }

    return [PSCustomObject]@{
        schemaVersion = "1.1"
        backup = @{
            id        = [guid]::NewGuid().ToString()
            createdAt = (Get-Date).ToString("o")
            createdBy = $ENV:USERNAME
            machine   = $ENV:COMPUTERNAME
            tool      = @{
                name    = "RenderKit"
                version = $script:RenderKitModuleVersion
            }
        }
        project = @{
            id       = $Project.id
            name     = $Project.Name
            rootPath = $Project.RootPath
        }
        options    = $Options
        statistics = $Statistics
        archive    = $Archive
        cleanup    = $CleanupSummary
    }
}
