[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PackagePath,

    [Parameter(Mandatory)]
    [string]$Version,

    [ValidateSet('PSResourceGet', 'PowerShellGet')]
    [string]$PackageManager
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PackagePath = (Resolve-Path -LiteralPath $PackagePath).ProviderPath
$repositoryName = 'RenderKitLocalTest'
$repositoryRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('RenderKit-Repository-{0}' -f ([guid]::NewGuid().ToString('N')))

try {
    New-Item -ItemType Directory -Path $repositoryRoot -Force | Out-Null
    Copy-Item -LiteralPath $PackagePath -Destination $repositoryRoot

    if ($PackageManager -eq 'PSResourceGet') {
        Import-Module Microsoft.PowerShell.PSResourceGet -Force -ErrorAction Stop
        Unregister-PSResourceRepository -Name $repositoryName -ErrorAction SilentlyContinue
        Register-PSResourceRepository -Name $repositoryName -Uri $repositoryRoot -Trusted

        Install-PSResource `
            -Name RenderKit `
            -Version $Version `
            -Repository $repositoryName `
            -Scope CurrentUser `
            -TrustRepository `
            -Reinstall `
            -ErrorAction Stop
    }
    else {
        Import-Module PowerShellGet -MinimumVersion 2.2.5 -Force -ErrorAction Stop
        Unregister-PSRepository -Name $repositoryName -ErrorAction SilentlyContinue
        Register-PSRepository `
            -Name $repositoryName `
            -SourceLocation $repositoryRoot `
            -PublishLocation $repositoryRoot `
            -InstallationPolicy Trusted

        Install-Module `
            -Name RenderKit `
            -RequiredVersion $Version `
            -Repository $repositoryName `
            -Scope CurrentUser `
            -Force `
            -AllowClobber `
            -ErrorAction Stop
    }

    Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
    Import-Module RenderKit -RequiredVersion $Version -Force -ErrorAction Stop
    $module = Get-Module -Name RenderKit

    if (-not $module -or $module.Version.ToString() -ne $Version) {
        throw "The local $PackageManager installation did not import RenderKit $Version."
    }

    [PSCustomObject]@{
        PackageManager = $PackageManager
        Version        = $module.Version.ToString()
        ModuleBase     = $module.ModuleBase
        CommandCount   = @(Get-Command -Module RenderKit).Count
        Validation     = 'Passed'
    }
}
finally {
    Remove-Module RenderKit -Force -ErrorAction SilentlyContinue

    if ($PackageManager -eq 'PSResourceGet') {
        Unregister-PSResourceRepository -Name $repositoryName -ErrorAction SilentlyContinue
    }
    else {
        Unregister-PSRepository -Name $repositoryName -ErrorAction SilentlyContinue
    }

    Remove-Item -LiteralPath $repositoryRoot -Recurse -Force -ErrorAction SilentlyContinue
}
