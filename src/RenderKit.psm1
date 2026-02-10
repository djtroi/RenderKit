# --- Module metadata bootstrap ---
$script:RenderKitModule = Get-Module -Name RenderKit -ErrorAction SilentlyContinue

$script:RenderKitModule.Version.ToString()
else {
    "0.0.0-unknown"
}
$publicPath  = Join-Path $PSScriptRoot 'Public'
$privatePath = Join-Path $PSScriptRoot 'Private'
$templatesPath = Join-Path $PSScriptRoot 'Templates'


if (Test-Path $publicPath) {
    Get-ChildItem "$publicPath\*.ps1" | ForEach-Object { . $_ }
} else {
    Write-Warning "Public folder not found: $publicPath"
}


if (Test-Path $privatePath) {
    Get-ChildItem "$privatePath\*.ps1" | ForEach-Object { . $_ }
} else {
    Write-Verbose "Private folder not found: $privatePath (optional)"
}


if (-not (Test-Path $templatesPath)) {
    Write-Verbose "Templates folder not found: $templatesPath (optional)"
}

Export-ModuleMember -Alias * -Function `
    New-Project,
    Backup-Project,
    Set-ProjectRoot,
    Get-ModuleVersion
