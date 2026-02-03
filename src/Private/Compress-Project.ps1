function Compress-Project{
    param(
        [string]$ProjectPath,
        [string]$DestinationPath
    )

    Compress-Archive -Path $ProjectPath -DestinationPath $DestinationPath -Force
}