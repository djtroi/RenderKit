function Write-RenderKitLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [validateset("Info", "Debug", "Warning", "Error")]
        [string]$Level = "Info",
        [switch]$Terminate
    )

    $timestamp = Get-LogTimeStamp
    $entry = "[$timestamp] [$Level] $Message"

    $script:LogBuffer.Add($entry)

    switch($Level){
        "Info" { Write-Information $entry -InformationAction Continue }
        "Debug" { Write-Debug $entry }
        "Warning" { Write-Warning $entry }
        "Error" {
            Write-Error $entry
            if ($Terminate){
                throw $Message
            }
        }

    }
}