function Write-RenderKitLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [validateset("Info", "Debug", "Warning", "Error")]
        [string]$Level = "Info",
        [switch]$NoConsole
    )


$timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$entry = "[$timestamp] [$level] $Message"

#file logging

if (!( $script:RenderKitLoggingInitialized )) {
    if (!( $script:RenderKitBootstrapLog )){
        $script:RenderKitBootstrapLog = New-Object System.Collections.Generic.List[string]
    }
    $script:RenderKitBootstrapLog.Add($entry)
}
else {
    Write-RenderKitLogFileEntry -Path $script:RenderKitLogFile -Value $entry

    if ( $script:RenderKitDebugMode -or $Level -eq "Debug" ){
        Write-RenderKitLogFileEntry -Path $script:RenderKitDebugLogFile -Value $entry
    }
}

#console output

if (!( $NoConsole )){
    switch ($Level) {
        "Out"       { Write-Output $Message }
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
function Write-RenderKitLogFileEntry {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    try {
        $logDirectory = Split-Path -Path $Path -Parent
        if (-not [string]::IsNullOrWhiteSpace($logDirectory) -and
            -not (Test-Path -LiteralPath $logDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $logDirectory -Force -ErrorAction Stop |
                Out-Null
        }

        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            New-Item -ItemType File -Path $Path -Force -ErrorAction Stop |
                Out-Null
        }

        Add-Content -LiteralPath $Path -Value $Value -ErrorAction Stop
    }
    catch {
        Write-Warning "RenderKit could not write to log file '$Path': $($_.Exception.Message)"
    }
}
}