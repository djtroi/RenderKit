function Get-RenderKitDriveCandidate {
    [CmdletBinding()]
    param(
        [switch]$IncludeFixed,
        [switch]$IncludeUnsupportedFileSystem
    )

    $candidates = @(Get-RenderKitDriveCandidatesInternal `
        -IncludeFixed:$IncludeFixed `
        -IncludeUnsupportedFileSystem:$IncludeUnsupportedFileSystem)

    if ($candidates.Count -eq 0) {
        Write-Warning "No candidate drives found."
        return @()
    }

    return $candidates
}
