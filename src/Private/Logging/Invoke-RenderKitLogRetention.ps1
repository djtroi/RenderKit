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
            
            try {
                $parsedDate = [System.DateTime]::ParseExact(
                    $dateString,
                    "yyyy-MM-dd HH:mm:ss",
                    [System.Globalization.CultureInfo]::InvariantCulture
                )

                if ($parsedDate -ge $cutoff){
                    $newContent += $line
                }
            }
            catch{

            }
        }
    }
    Set-Content -Path $file -Value $newContent
}
}