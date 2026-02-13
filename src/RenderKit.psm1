$script:ManifestPath = Join-Path $PSScriptRoot 'RenderKit.psd1'

if (Test-Path $script:ManifestPath) {
    $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
    $script:RenderKitModuleVersion = $manifest.ModuleVersion
}
else {
    $script:RenderKitModuleVersion = '0.0.0-unknown'
}


$publicPath  = Join-Path $PSScriptRoot 'Public'
$privatePath = Join-Path $PSScriptRoot 'Private'
$templatesPath = Join-Path $PSScriptRoot 'Templates'
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
    Get-ChildItem "$privatePath\*.ps1" | ForEach-Object { . $_ }
} else {
    Write-Error "Private folder not found: $privatePath "
}


if (-not (Test-Path $templatesPath)) {
    Write-Error "Templates folder not found: $templatesPath "
}


