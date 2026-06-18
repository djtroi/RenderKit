[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Version,

    [ValidateSet('PSResourceGet', 'PowerShellGet')]
    [string]$PackageManager = 'PSResourceGet',

    [string]$Repository = 'PSGallery',

    [ValidateRange(1, 20)]
    [int]$MaximumAttempts = 5,

    [ValidateRange(1, 300)]
    [int]$RetryDelaySeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$downloadRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('RenderKit-GalleryTest-{0}' -f ([guid]::NewGuid().ToString('N')))
$downloadPath = Join-Path -Path $downloadRoot -ChildPath ("RenderKit.{0}.nupkg" -f $Version)

function Invoke-RenderKitRetry {
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Operation
    )

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        try {
            return & $Operation
        }
        catch {
            if ($attempt -eq $MaximumAttempts) {
                throw
            }

            Write-Warning "Attempt $attempt of $MaximumAttempts failed: $($_.Exception.Message)"
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
}

Remove-Module RenderKit -Force -ErrorAction SilentlyContinue

try {
    New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null

    Invoke-RenderKitRetry {
        Invoke-WebRequest `
            -Uri "https://www.powershellgallery.com/api/v2/package/RenderKit/$Version" `
            -OutFile $downloadPath `
            -UseBasicParsing `
            -ErrorAction Stop
    } | Out-Null

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Test-RenderKitPackage.ps1') `
        -PackagePath $downloadPath `
        -ExpectedVersion $Version |
        Out-Host

    if ($PackageManager -eq 'PSResourceGet') {
        Import-Module Microsoft.PowerShell.PSResourceGet -Force -ErrorAction Stop

        Invoke-RenderKitRetry {
            Install-PSResource `
                -Name RenderKit `
                -Version $Version `
                -Repository $Repository `
                -Scope CurrentUser `
                -TrustRepository `
                -Reinstall `
                -ErrorAction Stop
        } | Out-Null
    }
    else {
        $powerShellGet = Get-Module -ListAvailable -Name PowerShellGet |
            Sort-Object -Property Version -Descending |
            Select-Object -First 1

        if (-not $powerShellGet -or $powerShellGet.Version -lt [version]'2.2.5') {
            throw 'PowerShellGet 2.2.5 or later is required for the legacy installation test.'
        }

        Import-Module PowerShellGet -MinimumVersion 2.2.5 -Force -ErrorAction Stop

        Invoke-RenderKitRetry {
            Install-Module `
                -Name RenderKit `
                -RequiredVersion $Version `
                -Repository $Repository `
                -Scope CurrentUser `
                -Force `
                -AllowClobber `
                -ErrorAction Stop
        } | Out-Null
    }

    Import-Module RenderKit -RequiredVersion $Version -Force -ErrorAction Stop
    $module = Get-Module -Name RenderKit

    if (-not $module -or $module.Version.ToString() -ne $Version) {
        throw "RenderKit $Version was installed but could not be imported at the requested version."
    }

    $commands = @(Get-Command -Module RenderKit)
    if ($commands.Count -eq 0) {
        throw "RenderKit $Version imported without any exported commands."
    }

    [PSCustomObject]@{
        PackageManager = $PackageManager
        Repository     = $Repository
        Version        = $module.Version.ToString()
        ModuleBase     = $module.ModuleBase
        CommandCount   = $commands.Count
        DownloadSha256 = (Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash
        Validation     = 'Passed'
    }
}
finally {
    Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $downloadRoot -Recurse -Force -ErrorAction SilentlyContinue
}