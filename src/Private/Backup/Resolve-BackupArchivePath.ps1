function Resolve-BackupArchivePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Project,
        [string]$DestinationRoot,
        [datetime]$Timestamp = (Get-Date)
    )

    $effectiveDestinationRoot = $DestinationRoot
    if ([string]::IsNullOrWhiteSpace($effectiveDestinationRoot)) {
        $effectiveDestinationRoot = Split-Path -Path $Project.RootPath -Parent
    }

    if ([string]::IsNullOrWhiteSpace($effectiveDestinationRoot)) {
        throw "Destination root could not be resolved."
    }

    if (Test-Path -Path $effectiveDestinationRoot) {
        $effectiveDestinationRoot = (Resolve-Path -Path $effectiveDestinationRoot).ProviderPath
    }

    $safeProjectName = [System.Text.RegularExpressions.Regex]::Replace(
        [string]$Project.Name,
        '[^a-zA-Z0-9_.-]',
        '_'
    )

    $archiveFileName = "{0}_backup_{1}.zip" -f $safeProjectName, $Timestamp.ToString("yyyyMMdd-HHmmss")
    $archivePath = Join-Path -Path $effectiveDestinationRoot -ChildPath $archiveFileName

    return [PSCustomObject]@{
        DestinationRoot = $effectiveDestinationRoot
        ArchiveFileName = $archiveFileName
        ArchivePath     = $archivePath
    }
}
