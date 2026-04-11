Register-RenderKitFunction "Show-RenderKitDriveCadidateTable"
function Show-RenderKitDriveCandidateTable {
    <#
.SYNOPSIS
Displays drive candidates as a table.

.DESCRIPTION
Formats candidate drives with index and key metadata for interactive selection.

.PARAMETER Candidates
Drive candidate objects to display.

.EXAMPLE
Show-RenderKitDriveCandidateTable -Candidates (Get-RenderKitDriveCandidate)
Prints candidate drives in tabular form.

.INPUTS
None. You cannot pipe input to this command.

.OUTPUTS
None. Writes a formatted table to host output.

.LINK
Get-RenderKitDriveCandidate
#>
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
Register-RenderKitFunction "Read-RenderKitDriveCandidateIndex"
function Read-RenderKitDriveCandidateIndex {
    <#
    .SYNOPSIS
    Reads a drive index from user input.

    .DESCRIPTION
    Re-prompts until a valid index is provided or the user cancels with Enter.

    .PARAMETER Candidates
    Candidate list used for range validation.

    .PARAMETER Prompt
    Prompt text shown while reading user input.

    .EXAMPLE
    Read-RenderKitDriveCandidateIndex -Candidates $candidates -Prompt "Pick index"
    Reads a valid index or returns `$null` when cancelled.

    .INPUTS
    None. You cannot pipe input to this command.

    .OUTPUTS
    System.Nullable[Int32]
    Returns selected index or `$null` when cancelled.

    .LINK
    Select-RenderKitDriveCandidate
    #>
    [CmdletBinding()]
    [OutputType([int])]
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
Register-RenderKitFunction "Select-RenderKitDriveCandidate"
function Select-RenderKitDriveCandidate {
    <#
    .SYNOPSIS
    Interactively selects a drive candidate.

    .DESCRIPTION
    Shows candidates, supports source selection, optional whitelisting, or cancellation.

    .PARAMETER IncludeFixed
    Includes fixed disks in candidate discovery.

    .PARAMETER IncludeUnsupportedFileSystem
    Includes drives with unsupported file systems in candidate discovery.

    .EXAMPLE
    Select-RenderKitDriveCandidate
    Shows removable candidates and prompts for selection.

    .EXAMPLE
    Select-RenderKitDriveCandidate -IncludeFixed
    Includes fixed drives and allows interactive selection.

    .INPUTS
    None. You cannot pipe input to this command.

    .OUTPUTS
    System.Object
    Returns selected candidate object or `$null` when cancelled.

    .LINK
    Get-RenderKitDriveCandidate

    .LINK
    Add-RenderKitDeviceWhitelistEntry

    .LINK
    https://github.com/djtroi/RenderKit
    #>
    [CmdletBinding()]
    [OutputType([System.Object])]
    param(
        [switch]$IncludeFixed,
        [switch]$IncludeUnsupportedFileSystem
    )

    Write-RenderKitLog -Level Debug -Message "Select-RenderKitDriveCandidate started: IncludeFixed=$($IncludeFixed.IsPresent), IncludeUnsupportedFileSystem=$($IncludeUnsupportedFileSystem.IsPresent)."

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
