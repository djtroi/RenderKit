function Initialize-RenderKitLogging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

$renderKitPath = Join-Path $ProjectRoot ".renderkit"

if (!( Test-Path $renderKitPath )) {
    #New-Item -ItemType Directory -Path $renderKitPath -Force | Out-Null
    throw ".renderkit folder not found. Logging cannot be initialized"
}

$script:RenderKitLogFile        =   Join-Path $renderKitPath "renderkit.log"
$script:RenderKitDebugLogFile   =   Join-Path $renderKitPath "renderkit.debug.log"

if (!( Test-Path $script:RenderKitLogFile )) {
    New-Item -ItemType File -Path $script:RenderKitLogFile | Out-Null   
}

if (!( Test-Path $script:RenderKitDebugLogFile )) {
    New-Item -ItemType File -Path $script:RenderKitDebugLogFile | Out-Null
}

$script:RenderKitLoggingInitialized = $true 

#flush bootstrap logs

if ( $script:RenderKitBootstrapLog ) {
    foreach ( $line in $script:RenderKitBootstrapLog ) {
        Add-Content -Path $script:RenderKitLogFile -Value $line
    }
    $script:RenderKitBootstrapLog = $null
}

Invoke-RenderKitLogRetention
}