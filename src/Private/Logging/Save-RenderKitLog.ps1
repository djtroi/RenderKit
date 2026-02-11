function Save-RenderKitLog {
    [CmdletBinding()]
    param(
        [ValidateSet("Information", "Error")]
        [string]$EventType = "Information"
    )

    if ( $script:LogBuffer.Count -eq 0 ) { return }

    switch ( $script:LogMode ) {
        "File"{
            $script:LogBuffer | Out-File $script:LogFilePath -Append -Encoding utf8
        }

        "EventLog" {
            $message = $script:LogBuffer -join "`n"
            Write-EventLog `
            -Logname $script:EventLogName `
            -Source $script:EventSource `
            -EntryType $EventType `
            -EventId 1000 `
            -Message $message
        }
    }
    $script:LogBuffer.Clear()
}