[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ApiKey,

    [string]$Repository = 'PSGallery',
    [string]$DestinationPath,
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$buildScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'Build-RenderKitPackage.ps1'
$buildResult = & $buildScriptPath -RepositoryRoot $RepositoryRoot -OutputRoot $OutputRoot

if (-not (Test-Path -LiteralPath $buildResult.PackagePath)) {
    throw "Expected package '$($buildResult.PackagePath)' was not created."
}

$publishTarget = if ($DestinationPath) { $DestinationPath } else { $Repository }
$publishParams = @{
    NupkgPath = $buildResult.PackagePath
}

if ($DestinationPath) {
}
else {
    $publishParams.Repository = $Repository
}

if ($ApiKey) {
    $publishParams.ApiKey = $ApiKey
}

if ($PSCmdlet.ShouldProcess($publishTarget, "Publish RenderKit $($buildResult.Version)")) {
    if ($DestinationPath) {
        New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
        Copy-Item -LiteralPath $buildResult.PackagePath -Destination (Join-Path -Path $DestinationPath -ChildPath (Split-Path -Path $buildResult.PackagePath -Leaf)) -Force
    }
    else {
        Publish-PSResource @publishParams
    }
}

$buildResult
