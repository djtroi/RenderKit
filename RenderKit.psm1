$script:RenderKitModuleRoot = $PSScriptRoot
$script:RenderKitModuleVersion = '0.0.0'
$script:RenderKitPublicFunctions = @(
    'Confirm-RenderKitMapping'
    'Confirm-Template'
    'Get-RenderKitConfig'
    'Get-RenderKitEngineClientDetail'
    'Get-RenderKitEngineClientList'
    'Get-RenderKitEngineEventDetail'
    'Get-RenderKitEngineEventList'
    'Get-RenderKitEngineInfo'
    'Get-RenderKitEngineJobDetail'
    'Get-RenderKitEngineJobHandlerCatalog'
    'Get-RenderKitEngineJobList'
    'Get-RenderKitEngineProjectDetail'
    'Get-RenderKitEnginePublicationDetail'
    'Get-RenderKitEnginePublicationList'
    'Get-RenderKitEngineState'
    'Get-RenderKitStorageRoot'
    'Get-RenderKitSystemMappingPath'
    'Get-RenderKitSystemMappingsRoot'
    'Get-RenderKitSystemTemplatesRoot'
    'Get-RenderKitTemplate'
    'Get-RenderKitUserMappingPath'
    'Get-RenderKitUserMappingsRoot'
    'Get-RenderKitUserTemplatePath'
    'Invoke-RenderKitEngineEventBridge'
    'Invoke-RenderKitWorkerTick'
    'New-RenderKitEngineClient'
    'New-RenderKitEngineJob'
    'New-RenderKitEnginePublication'
    'New-RenderKitError'
    'New-RenderKitOperationContext'
    'New-RenderKitResult'
    'Read-RenderKitDiscoveredProjectStore'
    'Read-RenderKitEventStore'
    'Read-RenderKitJobStore'
    'Read-RenderKitJsonFile'
    'Read-RenderKitTemplateFile'
    'Request-RenderKitEngineJobCancellation'
    'Resolve-ProjectPath'
    'Retry-RenderKitEngineJob'
    'Set-RenderKitEngineClient'
    'Set-RenderKitEnginePublication'
    'Write-RenderKitMappingFile'
    'Write-RenderKitTemplateFile'
    'Add-Metadata'
    'Add-MetadataTemplate'
    'Add-MetadataTemplateField'
    'Add-RenderKitDeliverableToTemplate'
    'Add-FolderToTemplate'
    'Add-RenderKitDeviceWhitelistEntry'
    'Add-RenderKitMappingToTemplate'
    'Add-RenderKitTypeToMapping'
    'Backup-Project'
    'Get-BackupAdapter'
    'Get-BackupConfigProfile'
    'Get-BackupJob'
    'Get-Metadata'
    'Get-MetadataTemplate'
    'Resume-BackupProjectJob'
    'Resume-BackupJob'
    'Get-RenderKitJobStatus'
    'Get-RenderKitJobWorkerStatus'
    'Get-RenderKitDeviceWhitelist'
    'Get-RenderKitDriveCandidate'
    'Get-RenderKitMetadataFieldRegistry'
    'Get-RenderKitClient'
    'Get-RenderKitPublication'
    'Import-BackupConfigProfile'
    'Import-Metadata'
    'Import-Media'
    'New-BackupConfigProfile'
    'New-MetadataTemplate'
    'New-Project'
    'New-RenderKitMapping'
    'New-RenderKitClient'
    'New-RenderKitPublication'
    'New-RenderKitTemplate'
    'Select-RenderKitDriveCandidate'
    'Set-BackupConfigProfile'
    'Set-MetadataTemplateField'
    'Set-RenderKitClient'
    'Set-RenderKitPublication'
    'Set-ProjectRoot'
    'Start-RenderKitJobWorker'
    'Stop-BackupJob'
    'Stop-BackupProjectJob'
    'Pause-BackupJob'
    'Rollback-Metadata'
    'Suspend-BackupProjectJob'
    'Rename-Project'
    'Remove-BackupConfigProfile'
    'Remove-Project'
    'Register-BackupAdapter'
    'Remove-BackupAdapter'
    'Import-Project'
    'Export-BackupConfigProfile'
    'Export-Metadata'
    'Export-Project'
    'Copy-Project'
    'Send-Project'
    'Test-BackupConfigProfile'
    'Test-RenderKitMetadataFieldValue'
    'Update-BackupConfigProfile'
    'Update-MetadataCache'
    'Get-Project'
)
$script:RenderKitPublicAliases = @(
    'projectroot'
    'setroot'
)

$moduleInfo = $ExecutionContext.SessionState.Module
if ($moduleInfo -and $moduleInfo.Version) {
    $script:RenderKitModuleVersion = $moduleInfo.Version.ToString()
}

function Register-RenderKitFunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    # Compatibility shim for existing source files. The public surface is
    # defined centrally in the manifest and exported explicitly below.
    if ($script:RenderKitPublicFunctions -notcontains $Name) {
        return
    }
}

function Get-RenderKitSourceFiles {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
     Justification = 'Files is the logically right term for this function')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Get-ChildItem -LiteralPath $Path -Recurse -File -Filter '*.ps1' |
        Sort-Object -Property FullName
}

$srcRoot = Join-Path -Path $PSScriptRoot -ChildPath 'src'
foreach ($relativePath in 'Classes', 'Private', 'Public') {
    $folderPath = Join-Path -Path $srcRoot -ChildPath $relativePath
    foreach ($sourceFile in Get-RenderKitSourceFiles -Path $folderPath) {
        . $sourceFile.FullName
    }
}

Set-Alias -Name 'projectroot' -Value 'Set-ProjectRoot' -Scope Script
Set-Alias -Name 'setroot' -Value 'Set-ProjectRoot' -Scope Script

Export-ModuleMember -Function $script:RenderKitPublicFunctions -Alias $script:RenderKitPublicAliases
