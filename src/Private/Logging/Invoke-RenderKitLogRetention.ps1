function Invoke-RenderKitLogRetention {

    if (!( $script:RenderKitLoggingInitialized )) {
        return
    }

    $cutoff = (Get-Date).AddDays(-14)

    foreach ($file in @($script:RenderKitLogFile, $script:RenderKitDebugLogFile)) {
        if (!( Test-Path $file )) { continue }
    

    $newContent = @()

    foreach ($line in Get-Content $file){
        if ($line -match "^\[(.*?)\]" ){
            $dateString = $matches[1]

            if([datetime]::TryParse($dateString, [ref]$parseDate)){
                if ($parsedDate -ge $cutoff) {
                    $newContent += $line 
                }
            }
        }
    }
    Set-Content -Path $file -Value $newContent
}
}