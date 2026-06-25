function Resolve-BackupArchivePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Project,
        [string]$DestinationRoot,
        [datetime]$Timestamp = (Get-Date),
        [ValidateSet('Zip', 'SevenZip', 'TarZstd', 'Folder')]
        [string]$ArchiveFormat = 'Zip'
    )

    Write-RenderKitLog -Level Debug -Message "Resolve-BackupArchivePath started: ProjectName='$($Project.Name)', RootPath='$($Project.RootPath)', DestinationRoot='$DestinationRoot', Timestamp='$Timestamp'."

    $effectiveDestinationRoot = $DestinationRoot
    if ([string]::IsNullOrWhiteSpace($effectiveDestinationRoot)) {
        $effectiveDestinationRoot = Split-Path -Path $Project.RootPath -Parent
    }

    if ([string]::IsNullOrWhiteSpace($effectiveDestinationRoot)) {
        Write-RenderKitLog -Level Error -Message "Destination root could not be resolved."
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

    $extension = switch ($ArchiveFormat) {
        'Zip' { '.zip' }
        'SevenZip' { '.7z' }
        'TarZstd' { '.tar.zst' }
        'Folder' { '' }
    }
    $archiveFileName = "{0}_backup_{1}{2}" -f $safeProjectName, $Timestamp.ToString("yyyyMMdd-HHmmss"), $extension
    $archivePath = Join-Path -Path $effectiveDestinationRoot -ChildPath $archiveFileName

    Write-RenderKitLog -Level Info -Message "Resolved backup archive path '$archivePath'."

    return [PSCustomObject]@{
        DestinationRoot = $effectiveDestinationRoot
        ArchiveFileName = $archiveFileName
        ArchivePath     = $archivePath
    }
}
