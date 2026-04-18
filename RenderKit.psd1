@{
    RootModule = 'RenderKit.psm1'
    ModuleVersion = '0.3.6' # Major.Minor.Patch
    Author = 'Norbert Marton'
    Description = 'PowerShell tools for structured video editing project workflows.'
    GUID = '32e3f476-8e44-4511-82c7-952748e6463b'
    CompanyName = 'Concept MARTON'
    Copyright = 'Copyright © 2026 Norbert Marton'
    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport = @(
        'Add-FolderToTemplate'
        'Add-RenderKitDeviceWhitelistEntry'
        'Add-RenderKitMappingToTemplate'
        'Add-RenderKitTypeToMapping'
        'Backup-Project'
        'Get-RenderKitDeviceWhitelist'
        'Get-RenderKitDriveCandidate'
        'Import-Media'
        'New-Project'
        'New-RenderKitMapping'
        'New-RenderKitTemplate'
        'Select-RenderKitDriveCandidate'
        'Set-ProjectRoot'
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
            IconUri = 'https://raw.githubusercontent.com/djtroi/RenderKit/main/src/assets/RenderKit_Logo.png'

            # ReleaseNotes of this module
            ReleaseNotes = 'Prepared version 0.3.5 with a staged release workflow, lean gallery artifacts, and deterministic module packaging.'
        } # End of PSData hashtable

    } # End of PrivateData hashtable
}
