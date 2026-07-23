@{
    RootModule = 'RenderKit.psm1'
    ModuleVersion = '1.1.1' # Major.Minor.Patch
    Author = 'Norbert Marton'
    Description = 'PowerShell tools for structured video editing project workflows.'
    GUID = '32e3f476-8e44-4511-82c7-952748e6463b'
    CompanyName = 'Concept MARTON'
    Copyright = 'Copyright © 2026 Norbert Marton'
    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport = @(
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
Version 1.1.1 fixes RenderKit Studio media-import compatibility:
- Restores the internal mapping filename resolver used while classifying imported media against bundled system mappings.
- Prevents `Import-Media` from failing with an unrecognized `Resolve-RenderKitMappingFileName` command in packaged Studio broker runs.
'@
        } # End of PSData hashtable

    } # End of PrivateData hashtable
}