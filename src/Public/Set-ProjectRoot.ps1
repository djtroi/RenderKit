Register-RenderKitFunction "Set-ProjectRoot"
function Set-ProjectRoot{
    <#
.SYNOPSIS
Sets the default RenderKit project root path.

.DESCRIPTION
Validates the given path and stores it in the platform-specific RenderKit
configuration directory.

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
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    Write-RenderKitLog -Level Debug -Message "Set-ProjectRoot started: Path='$Path'."

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-RenderKitLog -Level Error -Message "The specified project root path '$Path' does not exist or is not a directory."
        throw "The specified path '$Path' does not exist or is not a directory."
    }

    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    $configPath = Get-RenderKitConfigPath -SkipLegacyMigration
    $config = Get-RenderKitConfig
    $previousProjectRoot = $null
    if ($config -and
        ($config.PSObject.Properties.Name -contains 'DefaultProjectPath') -and
        -not [string]::IsNullOrWhiteSpace([string]$config.DefaultProjectPath)) {
        $previousProjectRoot = [string]$config.DefaultProjectPath
    }

    if ($PSCmdlet.ShouldProcess($configPath, 'Write RenderKit config')) {
        $configPath = Get-RenderKitConfigPath -EnsureParent
        if (-not $config) {
            $config = [PSCustomObject]@{}
        }
        if ($config.PSObject.Properties.Name -contains 'DefaultProjectPath') {
            $config.DefaultProjectPath = $resolvedPath
        }
        else {
            $config | Add-Member `
                -MemberType NoteProperty `
                -Name DefaultProjectPath `
                -Value $resolvedPath
        }

        $config |
            ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath $configPath -Encoding UTF8

        if (-not [string]::IsNullOrWhiteSpace($previousProjectRoot) -and
            [System.IO.Path]::GetFullPath($previousProjectRoot) -ne
            [System.IO.Path]::GetFullPath($resolvedPath)) {
            Set-RenderKitProjectSearchIndexEntry `
                -Path $previousProjectRoot `
                -Kind 'PreviousProjectRoot' `
                -Source 'SetProjectRoot' `
                -Priority 70 `
                -Recursive $true `
                -ReplacePriority |
                Out-Null
        }

        Set-RenderKitProjectSearchIndexEntry `
            -Path $resolvedPath `
            -Kind 'CurrentProjectRoot' `
            -Source 'SetProjectRoot' `
            -Priority 100 `
            -Recursive $true |
            Out-Null

        Write-RenderKitLog -Level Info -Message "Default project root set to '$resolvedPath'."
        Write-Output "Project root set to: $resolvedPath"
    }
}