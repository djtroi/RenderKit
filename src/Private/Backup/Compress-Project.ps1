function Compress-Project{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,
        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    Compress-Archive -Path $ProjectPath -DestinationPath $DestinationPath -Force

    $archiveItem = Get-Item -Path $DestinationPath -ErrorAction Stop
    $hash = Get-FileHash -Path $DestinationPath -Algorithm SHA256 -ErrorAction Stop

    return [PSCustomObject]@{
        Path          = $archiveItem.FullName
        SizeBytes     = [int64]$archiveItem.Length
        HashAlgorithm = "SHA256"
        Hash          = $hash.Hash
    }
}
