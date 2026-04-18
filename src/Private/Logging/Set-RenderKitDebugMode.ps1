function Set-RenderKitDebugMode {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        "PSUseShouldProcessForStateChangingFunctions",
        "",
        Justification = "internal function. The public function already has a DryRun feature")]
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