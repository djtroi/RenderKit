# Module Version
$script:ManifestPath = Join-Path $PSScriptRoot 'RenderKit.psd1'
$script:RenderKitModuleRoot = $PSScriptRoot

if (Test-Path $script:ManifestPath) {
    $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
    $script:RenderKitModuleVersion = $manifest.ModuleVersion
}
else {
    $script:RenderKitModuleVersion = '0.0.0-unknown'
}

# Bootstrap Logging
$script:RenderKitLoggingInitialized = $false
$script:RenderKitBootstrapLog = New-Object System.Collections.Generic.List[string]
$script:RenderKitDebugMode = $false

# Paths
$publicPath  = Join-Path $PSScriptRoot 'Public'
$privatePath = Join-Path $PSScriptRoot 'Private'
$classesPath = Join-Path $PSScriptRoot 'Classes'

# Load Classes
if (Test-Path $classesPath){
    Get-ChildItem -Path $classesPath -Filter *.ps1 -Recurse | ForEach-Object { . $_.FullName }
}
else {
    Write-Verbose "No Classes folder found: $classesPath"
}

# Load Public
if (Test-Path $publicPath) {
    Get-ChildItem -Path $publicPath -Filter *.ps1 -Recurse | ForEach-Object { . $_.FullName }
}
else {
    Write-Verbose "Public folder not found: $publicPath"
}

# Load Private
if (Test-Path $privatePath) {
    Get-ChildItem -Path $privatePath -Filter *.ps1 -Recurse | ForEach-Object { . $_.FullName }
}
else {
    Write-Verbose "Private folder not found: $privatePath"
}