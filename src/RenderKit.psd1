@{
    RootModule = 'RenderKit.psm1'
    ModuleVersion = '0.2.0' # Major.Minor.Patch
    Author = 'Norbert Marton'
    Description = 'Powershell tools for video editing project workflows.'
    GUID = '32e3f476-8e44-4511-82c7-952748e6463b'
    CompanyName = "Concept MARTON"
    Copyright = 'Copyright © 2026 Norbert Marton'
    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion = '5.1.14393.0'
    FunctionsToExport = @(
        'New-Project'
        'Backup-Project'
        'Set-ProjectRoot'
        'Add-RenderKitMappingToTemplate'
        'Add-RenderKitTypeToMapping'
        'New-RenderKitMapping'
        'New-RenderKitTemplate'
        'Add-FolderToTemplate'
        )
    CmdletsToExport = @()
    AliasesToExport = @()
    VariablesToExport = '*'
    PrivateData = @{
        PSData = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = 'RenderKit', 'renderkit', 'rk', 'rkit', 'render', 'kit', 'video editing', 'cutting', 'production', 'video', 'workflow', 'projectmanagement'

            # A URL to the license for this module.
            LicenseUri = 'https://github.com/djtroi/RenderKit?tab=MIT-1-ov-file'

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/djtroi/RenderKit'

            # A URL to an icon representing this module.
            IconUri = 'https://raw.githubusercontent.com/djtroi/RenderKit/refs/heads/main/src/assets/RenderKit_Logo.png'

            # ReleaseNotes of this module
            ReleaseNotes = 'https://github.com/djtroi/RenderKit/releases/latest'

            # Prerelease tag for PSGallery.
            Prerelease = 'alpha'

         } # End of PSData hashtable

         } # End of PrivateData hashtable 
}