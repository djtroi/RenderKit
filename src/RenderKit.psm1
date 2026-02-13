#Module Version
$script:ManifestPath = Join-Path $PSScriptRoot 'RenderKit.psd1'

if (Test-Path $script:ManifestPath) {
    $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
    $script:RenderKitModuleVersion = $manifest.ModuleVersion
}
else {
    $script:RenderKitModuleVersion = '0.0.0-unknown'
}

#Bootstrap Logging
$script:RenderKitLoggingInitialized = $false
$script:RenderKitBootstrapLog = New-Object System.Collections.Generic.List[string]
$script:RenderKitDebugMode = $false

#Release
$publicPath  = Join-Path $PSScriptRoot 'Public'
$privatePath = Join-Path $PSScriptRoot 'Private'
$resourcesPath = Join-Path $PSScriptRoot 'Resources'
$classesPath = Join-Path $PSScriptRoot 'Classes'

if (Test-Path $classesPath){
    Get-ChildItem -Path $classesPath\*.ps1 | ForEach-Object {. $_ }
} else {
    Write-Error "No Classes folder found $classesPath"
}

if (Test-Path $publicPath) {
    Get-ChildItem "$publicPath\*.ps1" | ForEach-Object { . $_ }
} else {
    Write-Error "Public folder not found: $publicPath"
}


if (Test-Path $privatePath) {
    Get-ChildItem -Path $privatePath -Filter *.ps1 -Recurse | ForEach-Object { . $_.FullName }
} else {
    Write-Error "Private folder not found: $privatePath "
}


if (-not (Test-Path $resourcesPath)) {
    Get-ChildItem "$resourcesPath\*.ps1" -Recurse | ForEach-Object { . $_ }
} else {
    Write-Error "Resources folder not found: $resourcesPath "
}


