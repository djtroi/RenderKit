function Write-RenderKitLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [validateset("Info", "Debug", "Warning", "Error")]
        [string]$Level = "Info",
        [switch]$NoConsole
    )


$timestamp = (Get-Date).ToString("yyyy-MMM-dd HH:mm:ss")
$entry = "[$timestamp] [$level] $Message"

#file logging

if (!( $script:RenderKitLoggingInitialized )) {
    if (!( $script:RenderKitBootstrapLog )){
        $script:RenderKitBootstrapLog = New-Object System.Collections.Generic.List[string]
    }
    $script:RenderKitBootstrapLog.Add($entry)
}
else {
    Add-Content -Path $script:RenderKitLogFile -Value $entry 

    if ( $script:RenderKitDebugMode -or $Level -eq "Debug "){
        Add-Content -Path $script:RenderKitDebugLogFile -Value $entry 
    }
}

#console output

if (!( $NoConsole )){
    switch ($Level) {
        "Info"      { Write-Information $Message -InformationAction Continue }
        "Warning"   { Write-Warning $Message }
        "Error"     { Write-Error $Message }
        "Debug"     {
            if ( $script:RenderKitDebugMode ) {
                Write-Verbose "[DEBUG] $Message" -Verbose
            }
        }
    }
}
}