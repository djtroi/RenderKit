@{
    RootModule = 'RenderKit.psm1'
    ModuleVersion = '1.0.0' # Major.Minor.Patch
    Author = 'Norbert Marton'
    Description = 'PowerShell tools for structured video editing project workflows.'
    GUID = '32e3f476-8e44-4511-82c7-952748e6463b'
    CompanyName = 'Concept MARTON'
    Copyright = 'Copyright © 2026 Norbert Marton'
    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport = @(
        'Add-RenderKitDeliverableToTemplate'
        'Add-FolderToTemplate'
        'Add-RenderKitDeviceWhitelistEntry'
        'Add-RenderKitMappingToTemplate'
        'Add-RenderKitTypeToMapping'
        'Backup-Project'
        'Get-BackupJob'
        'Resume-BackupProjectJob'
        'Resume-BackupJob'
        'Get-RenderKitJobStatus'
        'Get-RenderKitJobWorkerStatus'
        'Get-RenderKitDeviceWhitelist'
        'Get-RenderKitDriveCandidate'
        'Import-Media'
        'New-Project'
        'New-RenderKitMapping'
        'New-RenderKitTemplate'
        'Select-RenderKitDriveCandidate'
        'Set-ProjectRoot'
        'Start-RenderKitJobWorker'
        'Stop-BackupJob'
        'Stop-BackupProjectJob'
        'Pause-BackupJob'
        'Suspend-BackupProjectJob'
        'Rename-Project'
        'Remove-Project'
        'Import-Project'
        'Export-Project'
        'Copy-Project'
        'Send-Project'
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
Version 1.0.0 introduces the RenderKit engine foundations and state model:
- Cross-platform user storage for configuration, state, cache, and user data, including RENDERKIT_HOME overrides.
- Atomic JSON persistence with file locking, backup restoration, validation hooks, and transaction-style state updates.
- Artifact versioning and compatibility metadata for projects, registry data, events, jobs, templates, mappings, devices, and configuration.
- Internal project registry and lifecycle services for tracking known projects, reconciling moved or missing project folders, validating status transitions, and emitting lifecycle events.
- Domain-event storage, event-to-job automation subscriptions, durable jobs, trusted worker primitives, handler metadata catalogs, and repair/health checks.
- Host-facing engine contracts with operation contexts, correlation and causation IDs, stable RenderKitResult envelopes, registered error codes, and a machine-readable contract snapshot for broker/Electron handoff.

This release also updates project commands and import/export flows to keep registry and lifecycle state consistent, moves EventStore and JobStore metadata to schema version 1.1 while retaining readable 1.0 compatibility, and expands documentation and Pester coverage for the new foundations.
'@
        } # End of PSData hashtable

    } # End of PrivateData hashtable
}
