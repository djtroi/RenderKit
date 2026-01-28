function Set-ProjectRoot{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (!(Test-Path -Path $Path)) {
        throw "The specified path '$Path' does not exist or is not a directory."
    }

    $configDir = Join-Path $env:APPDATA "RenderKit"
    if(!(Test-Path $configDir)){
        New-Item -ItemType Directory -Path $configDir | Out-Null
    }

    $configPath = Join-Path $configDir "config.json"
    $config = @{}
    if(Test-Path $configPath){
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
    }
    $config.DefaultProjectPath = $Path
    $config | ConvertTo-Json -Depth 5 | Set-Content $configPath

    Write-Host "Project root set to: $Path"
}