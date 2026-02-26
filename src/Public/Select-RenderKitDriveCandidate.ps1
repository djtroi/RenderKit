function Show-RenderKitDriveCandidateTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Candidates
    )

    if (-not $Candidates -or $Candidates.Count -eq 0) {
        return
    }

    $displayRows = @()
    for ($i = 0; $i -lt $Candidates.Count; $i++) {
        $item = $Candidates[$i]
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
}

function Read-RenderKitDriveCandidateIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Candidates,
        [string]$Prompt = "Drive index (Enter to cancel)"
    )

    while ($true) {
        $selection = Read-Host $Prompt
        if ([string]::IsNullOrWhiteSpace($selection)) {
            return $null
        }

        $selectedIndex = -1
        if (-not [int]::TryParse($selection, [ref]$selectedIndex)) {
            Write-Warning "Invalid selection '$selection'. Enter a numeric index."
            continue
        }

        if ($selectedIndex -lt 0 -or $selectedIndex -ge $Candidates.Count) {
            Write-Warning "Selection '$selection' is out of range."
            continue
        }

        return [int]$selectedIndex
    }
}

function Select-RenderKitDriveCandidate {
    [CmdletBinding()]
    param(
        [switch]$IncludeFixed,
        [switch]$IncludeUnsupportedFileSystem
    )

    $candidates = @(Get-RenderKitDriveCandidate `
        -IncludeFixed:$IncludeFixed `
        -IncludeUnsupportedFileSystem:$IncludeUnsupportedFileSystem `
        -DisableInteractiveFallback)

    if ($candidates.Count -eq 0) {
        return $null
    }

    Show-RenderKitDriveCandidateTable -Candidates $candidates

    while ($true) {
        $action = Read-Host "Action: [S]elect source, [W]hitelist drive, [C]ancel (default S)"
        if ([string]::IsNullOrWhiteSpace($action)) {
            $action = "S"
        }

        switch ($action.Trim().ToUpperInvariant()) {
            "S" {
                $index = Read-RenderKitDriveCandidateIndex `
                    -Candidates $candidates `
                    -Prompt "Select source drive by index (Enter to cancel)"
                if ($null -eq $index) {
                    Write-Information "Drive selection cancelled." -InformationAction Continue
                    return $null
                }

                return $candidates[$index]
            }
            "SELECT" {
                $index = Read-RenderKitDriveCandidateIndex `
                    -Candidates $candidates `
                    -Prompt "Select source drive by index (Enter to cancel)"
                if ($null -eq $index) {
                    Write-Information "Drive selection cancelled." -InformationAction Continue
                    return $null
                }

                return $candidates[$index]
            }
            "W" {
                $index = Read-RenderKitDriveCandidateIndex `
                    -Candidates $candidates `
                    -Prompt "Whitelist drive by index (Enter to cancel)"
                if ($null -eq $index) {
                    continue
                }

                $targetDrive = $candidates[$index]
                Add-RenderKitDeviceWhitelistEntry -DriveLetter $targetDrive.DriveLetter -Confirm:$false | Out-Null
                Write-Information "Drive '$($targetDrive.DriveLetter)' was added to the whitelist." -InformationAction Continue

                $selectNow = Read-Host "Use '$($targetDrive.DriveLetter)' as source now? [Y/N]"
                if ($selectNow) {
                    switch ($selectNow.Trim().ToUpperInvariant()) {
                        "Y" { return $targetDrive }
                        "YES" { return $targetDrive }
                        "J" { return $targetDrive }
                        "JA" { return $targetDrive }
                    }
                }
            }
            "WHITELIST" {
                $index = Read-RenderKitDriveCandidateIndex `
                    -Candidates $candidates `
                    -Prompt "Whitelist drive by index (Enter to cancel)"
                if ($null -eq $index) {
                    continue
                }

                $targetDrive = $candidates[$index]
                Add-RenderKitDeviceWhitelistEntry -DriveLetter $targetDrive.DriveLetter -Confirm:$false | Out-Null
                Write-Information "Drive '$($targetDrive.DriveLetter)' was added to the whitelist." -InformationAction Continue

                $selectNow = Read-Host "Use '$($targetDrive.DriveLetter)' as source now? [Y/N]"
                if ($selectNow) {
                    switch ($selectNow.Trim().ToUpperInvariant()) {
                        "Y" { return $targetDrive }
                        "YES" { return $targetDrive }
                        "J" { return $targetDrive }
                        "JA" { return $targetDrive }
                    }
                }
            }
            "C" { return $null }
            "CANCEL" { return $null }
            "N" { return $null }
            "NO" { return $null }
            default {
                Write-Warning "Unknown action '$action'."
            }
        }
    }
}
