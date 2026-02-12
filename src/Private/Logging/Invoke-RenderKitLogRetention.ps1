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
            $parsedDate = $null
            #if([datetime]::ParseExact($dateString, "yyyy-MM-dd HH:mm:ss", $null)){
            if ([datetime]::TryParse($dateString, [ref]$parsedDate)){
                if ($parsedDate -ge $cutoff) {
                    $newContent += $line 
                }
            }
        }
    }
    Set-Content -Path $file -Value $newContent
}
}