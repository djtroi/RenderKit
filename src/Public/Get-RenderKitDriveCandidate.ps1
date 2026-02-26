function Get-RenderKitDriveCandidate {
    [CmdletBinding()]
    param(
        [switch]$IncludeFixed,
        [switch]$IncludeUnsupportedFileSystem,
        [switch]$DisableInteractiveFallback
    )

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

    return $candidates
}
