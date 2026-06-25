function Get-RenderKitBackupManifestSchemaVersion {
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    return '2.0'
}

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
        [array]$CleanupSummary,
        [object]$Job,
        [object]$Profile,
        [object]$Pipeline,
        [array]$StorageTiers,
        [object]$Safety
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
    if (-not $Job) {
        $Job = [PSCustomObject]@{
            id            = $null
            type          = 'BackupProject'
            executionMode = 'Immediate'
            queued        = $false
        }
    }
    if (-not $Profile) {
        $Profile = [PSCustomObject]@{
            configProfile     = 'legacy'
            cleanupPresets    = @($Options.profiles)
            compressionPreset = 'Balanced'
        }
    }
    if (-not $Pipeline) {
        $Pipeline = [PSCustomObject]@{
            archiveFormat = 'Zip'
            chunking      = [PSCustomObject]@{
                enabled    = $false
                strategy   = 'Disabled'
                resumeMode = 'WholeArchive'
            }
        }
    }
    if (-not $StorageTiers) {
        $StorageTiers = @()
    }
    if (-not $Safety) {
        $Safety = [PSCustomObject]@{
            deletePolicy = [PSCustomObject]@{
                mode                           = if ($Options.keepSourceProject) { 'KeepSource' } else { 'RemoveSourceAfterVerified' }
                requiresArchiveIntegrity       = $true
                requiresPrimaryTierVerification = $true
                requiresAllTierVerification    = $false
            }
        }
    }

    return [PSCustomObject]@{
        schemaVersion = Get-RenderKitBackupManifestSchemaVersion
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
        job        = $Job
        profile    = $Profile
        pipeline   = $Pipeline
        storageTiers = @($StorageTiers)
        safety     = $Safety
        statistics = $Statistics
        archive    = $Archive
        cleanup    = $CleanupSummary
    }
}
