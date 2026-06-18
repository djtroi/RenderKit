function Get-RenderKitConfig {
    $configPath = Get-RenderKitConfigPath
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        return @{}
    }

    Get-Content -LiteralPath $configPath -Raw -ErrorAction Stop |
        ConvertFrom-Json -ErrorAction Stop
}
