function Set-RenderKitDebugMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$Enabled
    )

    $script:RenderKitDebugMode = $Enabled 

    if ( $Enabled ){
        Write-RenderKitLog -Message "Debug Mode enqabled." -Level Info
    }
    else {
        Write-RenderKitLog -Message "Debug mode disabled" -Level Info
    }
}