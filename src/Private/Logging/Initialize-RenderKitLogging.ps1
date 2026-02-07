function Initialize-RenderKitLogging {
    [CmdletBinding()]
    param(
        [ValidateSet("None", "Console", "File", "Eventlog")]
        [string]$Mode = "Console",
        [string]$LogFilePath, 
        [string]$EventLogName = "RenderKit",
        [String]$EventSource = "RenderKit"
    )

    $script:LogMode = $Mode 
    $script:LogBuffer = -New-Object System.Collections.Generic.List[string]
    $script:EventLogName = $EventLogName
    $script:EventSource = $EventSource
    $script:LogFilePath = $LogFilePath

    if  ( $Mode -eq "EventLog" ){
        if (!([System.Diagnostics.EventLog]::SourceExists($EventSource))){
            New-EventLog -LogName $EventLogName -Source $EventSource
        }
        }
    }
