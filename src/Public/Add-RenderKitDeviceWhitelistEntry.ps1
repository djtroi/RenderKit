function Add-RenderKitDeviceWhitelistEntry {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string[]]$VolumeName,
        [string[]]$SerialNumber,
        [string]$DriveLetter,
        [switch]$FromMountedVolumes,
        [switch]$IncludeFixed
    )

    if (
        -not $VolumeName -and
        -not $SerialNumber -and
        -not $DriveLetter -and
        -not $FromMountedVolumes
    ) {
        throw "Provide -VolumeName, -SerialNumber, -DriveLetter, or -FromMountedVolumes."
    }

    $pendingVolumeNames = @()
    $pendingSerialNumbers = @()

    if ($VolumeName) {
        $pendingVolumeNames += $VolumeName
    }

    if ($SerialNumber) {
        $pendingSerialNumbers += $SerialNumber
    }

    if ($FromMountedVolumes) {
        $mounted = Get-RenderKitMountedDrives `
            -IncludeFixed:$IncludeFixed `
            -IncludeUnsupportedFileSystem

        $mountedVolumeNames = @(
            $mounted |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_.VolumeName) } |
                Select-Object -ExpandProperty VolumeName
        )

        $pendingVolumeNames += $mountedVolumeNames
    }

    if ($DriveLetter) {
        $normalizedDriveLetter = Resolve-RenderKitDriveLetter -DriveLetter $DriveLetter
        $mounted = Get-RenderKitMountedDrives -IncludeFixed -IncludeUnsupportedFileSystem

        $matchedDrive = $mounted |
            Where-Object DriveLetter -eq $normalizedDriveLetter |
            Select-Object -First 1

        if (-not $matchedDrive) {
            throw "Drive '$DriveLetter' was not found."
        }

        if (-not [string]::IsNullOrWhiteSpace($matchedDrive.VolumeName)) {
            $pendingVolumeNames += $matchedDrive.VolumeName
        }

        if (-not [string]::IsNullOrWhiteSpace($matchedDrive.VolumeSerialNumber)) {
            $pendingSerialNumbers += $matchedDrive.VolumeSerialNumber
        }
    }

    $pendingVolumeNames = @(
        $pendingVolumeNames |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { ([string]$_).Trim() } |
            Sort-Object -Unique
    )

    $pendingSerialNumbers = @(
        $pendingSerialNumbers |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { ([string]$_).Trim() } |
            Sort-Object -Unique
    )

    if ($pendingVolumeNames.Count -eq 0 -and $pendingSerialNumbers.Count -eq 0) {
        Write-Warning "No valid whitelist entries were resolved."
        return $null
    }

    $registry = Read-RenderKitDeviceRegistry
    $newVolumeNames = @($pendingVolumeNames | Where-Object { $registry.VolumeNames -notcontains $_ })
    $newSerialNumbers = @($pendingSerialNumbers | Where-Object { $registry.SerialNumbers -notcontains $_ })

    if ($newVolumeNames.Count -eq 0 -and $newSerialNumbers.Count -eq 0) {
        Write-RenderKitLog -Level Info -Message "No new whitelist entries to add."
        return [PSCustomObject]@{
            Path               = Get-RenderKitDevicesPath
            AddedVolumeNames   = @()
            AddedSerialNumbers = @()
            VolumeNames        = $registry.VolumeNames
            SerialNumbers      = $registry.SerialNumbers
        }
    }

    $path = Get-RenderKitDevicesPath
    if ($PSCmdlet.ShouldProcess($path, "Update RenderKit device whitelist")) {
        $registry.VolumeNames = @($registry.VolumeNames + $newVolumeNames | Sort-Object -Unique)
        $registry.SerialNumbers = @($registry.SerialNumbers + $newSerialNumbers | Sort-Object -Unique)

        $savedRegistry = Write-RenderKitDeviceRegistry -Registry $registry
        Write-RenderKitLog -Level Info -Message "Updated device whitelist at '$path'."

        return [PSCustomObject]@{
            Path               = $path
            AddedVolumeNames   = $newVolumeNames
            AddedSerialNumbers = $newSerialNumbers
            VolumeNames        = $savedRegistry.VolumeNames
            SerialNumbers      = $savedRegistry.SerialNumbers
        }
    }
}
