New-Alias -Name setroot -Value Set-ProjectRoot
New-Alias -Name projectroot -Value Set-ProjectRoot
<#
.SYNOPSIS
Sets the default RenderKit project root path.

.DESCRIPTION
Validates the given path and stores it in `%APPDATA%\RenderKit\config.json`.

.PARAMETER Path
Absolute or relative directory path to store as default RenderKit project root.

.EXAMPLE
Set-ProjectRoot -Path "D:\Projects"
Sets `D:\Projects` as default project root.

.EXAMPLE
Set-ProjectRoot -Path ".\Projects"
Sets a path relative to the current location.

.INPUTS
None. You cannot pipe input to this command.

.OUTPUTS
None. The command writes config to disk and prints the selected path.

.LINK
New-Project

.LINK
Backup-Project

.LINK
https://github.com/djtroi/RenderKit
#>
function Set-ProjectRoot{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    Write-RenderKitLog -Level Debug -Message "Set-ProjectRoot started: Path='$Path'."

    if (!(Test-Path -Path $Path)) {
        Write-RenderKitLog -Level Error -Message "The specified project root path '$Path' does not exist or is not a directory."
        throw "The specified path '$Path' does not exist or is not a directory."
    }

    $configDir = Join-Path $env:APPDATA "RenderKit"
    if(!(Test-Path $configDir)){
        New-Item -ItemType Directory -Path $configDir | Out-Null
    }

    $configPath = Join-Path $configDir "config.json"
    $config = @{}
    if(Test-Path $configPath){
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
    }
    $config.DefaultProjectPath = $Path
    $config | ConvertTo-Json -Depth 5 | Set-Content $configPath

    Write-RenderKitLog -Level Info -Message "Default project root set to '$Path'."
    Write-Host "Project root set to: $Path"
}
