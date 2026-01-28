function Get-RenderKitConfig {
    $configPath = Join-Path $env:APPDATA "RenderKit\config.json"
    if (!(Test-Path $configPath)){
        return @{}
    }
    Get-Content $configPath -Raw | ConvertFrom-Json
}