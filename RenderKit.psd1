@{
    RootModule = 'RenderKit.psm1'
    ModuleVersion = '1.1.0' # Major.Minor.Patch
    Author = 'Norbert Marton'
    Description = 'PowerShell tools for structured video editing project workflows.'
    GUID = '32e3f476-8e44-4511-82c7-952748e6463b'
    CompanyName = 'Concept MARTON'
    Copyright = 'Copyright © 2026 Norbert Marton'
    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport = @(
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
    CmdletsToExport = @()
    AliasesToExport = @(
        'projectroot'
        'setroot'
    )
    VariablesToExport = @()
    PrivateData = @{
        PSData = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('RenderKit', 'powershell', 'video', 'video-editing', 'media-import', 'backup', 'workflow', 'project-management')

            # A URL to the license for this module.
            LicenseUri = 'https://github.com/djtroi/RenderKit/blob/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/djtroi/RenderKit'

            # A URL to an icon representing this module.
            #IconUri = 'https://raw.githubusercontent.com/djtroi/RenderKit/main/src/assets/RenderKit_Logo.png'

            # ReleaseNotes of this module
            ReleaseNotes = @'
Version 1.1.0 expands RenderKit's media-production engine:
- Adds versioned metadata templates, field validation, import/export, cache refresh, history, and rollback commands.
- Adds native-first media inspection and verified writers for XMP/IPTC, RIFF BWF/iXML, ID3v2.4, and Matroska metadata, with explicit fallback routing.
- Adds versioned client and publishing schedule registries with optimistic concurrency and host-facing engine operations.
- Adds project discovery/search-index improvements and the expanded backup profile, adapter, job-control, worker, reporting, and recovery workflows.
- Bundles hash-verified MediaInfo, ExifTool, TagLibSharp, and MKVToolNix runtimes with their required notices and package validation.
- Refreshes the public documentation and contract tests for the 1.1.0 surface.
'@
        } # End of PSData hashtable

    } # End of PrivateData hashtable
}
