$script:RenderKitModuleRoot = $PSScriptRoot
$script:RenderKitModuleVersion = '0.0.0'
$script:RenderKitPublicFunctions = @(
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
