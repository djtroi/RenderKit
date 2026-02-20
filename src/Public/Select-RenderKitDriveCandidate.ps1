function Select-RenderKitDriveCandidate {
    [CmdletBinding()]
    param(
        [switch]$IncludeFixed,
        [switch]$IncludeUnsupportedFileSystem
    )

    $candidates = @(Get-RenderKitDriveCandidate `
        -IncludeFixed:$IncludeFixed `
        -IncludeUnsupportedFileSystem:$IncludeUnsupportedFileSystem)

    if ($candidates.Count -eq 0) {
        return $null
    }

    $displayRows = @()
    for ($i = 0; $i -lt $candidates.Count; $i++) {
        $item = $candidates[$i]
        $displayRows += [PSCustomObject]@{
            Index       = $i
            Drive       = $item.DriveLetter
            VolumeName  = $item.VolumeName
            FileSystem  = $item.FileSystem
            Serial      = $item.VolumeSerialNumber
            Whitelisted = ($item.IsWhitelistedVolumeName -or $item.IsWhitelistedSerialNumber)
            Score       = $item.Score
        }
    }

    $displayRows | Format-Table -AutoSize | Out-Host

    $selection = Read-Host "Select source drive by index (press Enter to cancel)"
    if ([string]::IsNullOrWhiteSpace($selection)) {
        Write-Information "Drive selection cancelled." -InformationAction Continue
        return $null
    }

    $selectedIndex = -1
    if (-not [int]::TryParse($selection, [ref]$selectedIndex)) {
        throw "Invalid selection '$selection'. Enter a numeric index."
    }

    if ($selectedIndex -lt 0 -or $selectedIndex -ge $candidates.Count) {
        throw "Selection '$selection' is out of range."
    }

    return $candidates[$selectedIndex]
}
