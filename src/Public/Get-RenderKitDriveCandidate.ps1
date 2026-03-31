<#
.SYNOPSIS
Lists ranked drive candidates for import.

.DESCRIPTION
Evaluates mounted drives and returns scored candidates, with optional interactive fallback.

.PARAMETER IncludeFixed
Includes fixed disks in addition to removable media.

.PARAMETER IncludeUnsupportedFileSystem
Includes drives with file systems outside the preferred set.

.PARAMETER DisableInteractiveFallback
Disables interactive fallback prompt when no removable candidates are found.

.EXAMPLE
Get-RenderKitDriveCandidate
Returns ranked removable drive candidates.

.EXAMPLE
Get-RenderKitDriveCandidate -IncludeFixed -IncludeUnsupportedFileSystem
Returns a broader candidate list including fixed drives and unsupported file systems.

.EXAMPLE
Get-RenderKitDriveCandidate -DisableInteractiveFallback
Returns candidates without asking follow-up questions.

.INPUTS
None. You cannot pipe input to this command.

.OUTPUTS
System.Object[]
Returns candidate drive objects with scoring and whitelist match metadata.

.LINK
Select-RenderKitDriveCandidate

.LINK
Get-RenderKitDeviceWhitelist

.LINK
https://github.com/djtroi/RenderKit
#>
function Get-RenderKitDriveCandidate {
    [CmdletBinding()]
    param(
        [switch]$IncludeFixed,
        [switch]$IncludeUnsupportedFileSystem,
        [switch]$DisableInteractiveFallback
    )

    Write-RenderKitLog -Level Debug -Message "Get-RenderKitDriveCandidate started: IncludeFixed=$($IncludeFixed.IsPresent), IncludeUnsupportedFileSystem=$($IncludeUnsupportedFileSystem.IsPresent), DisableInteractiveFallback=$($DisableInteractiveFallback.IsPresent)."

    $candidates = @(Get-RenderKitDriveCandidatesInternal `
        -IncludeFixed:$IncludeFixed `
        -IncludeUnsupportedFileSystem:$IncludeUnsupportedFileSystem)

    if ($candidates.Count -eq 0) {
        Write-Warning "No candidate drives found."

        if (-not $DisableInteractiveFallback -and -not $IncludeFixed) {
            $fallbackAnswer = Read-Host "No removable candidates found. Include fixed drives? [Y/N]"
            if ($fallbackAnswer) {
                switch ($fallbackAnswer.Trim().ToUpperInvariant()) {
                    "Y" { return Select-RenderKitDriveCandidate -IncludeFixed -IncludeUnsupportedFileSystem:$IncludeUnsupportedFileSystem }
                    "YES" { return Select-RenderKitDriveCandidate -IncludeFixed -IncludeUnsupportedFileSystem:$IncludeUnsupportedFileSystem }
                    "J" { return Select-RenderKitDriveCandidate -IncludeFixed -IncludeUnsupportedFileSystem:$IncludeUnsupportedFileSystem }
                    "JA" { return Select-RenderKitDriveCandidate -IncludeFixed -IncludeUnsupportedFileSystem:$IncludeUnsupportedFileSystem }
                }
            }
        }

        return @()
    }

    Write-RenderKitLog -Level Debug -Message "Get-RenderKitDriveCandidate found $($candidates.Count) candidate drive(s)."
    return $candidates
}
