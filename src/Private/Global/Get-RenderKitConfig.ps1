 function Get-RenderKitConfig {

    $configPath = Get-RenderKitConfigPath
    $config = Read-RenderKitJsonFile `
        -Path $configPath `
        -AllowMissing
    if ($null -eq $config) {
         return @{}
     }


    return $config
}
