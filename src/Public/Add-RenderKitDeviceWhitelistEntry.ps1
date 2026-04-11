Register-RenderKitFunction "Add-RenderKitDeviceWhitelistEntry"
function Add-RenderKitDeviceWhitelistEntry {
    <#
.SYNOPSIS
Adds device whitelist entries for import source detection.

.DESCRIPTION
Accepts volume names, serial numbers, drive letters, or mounted volumes and persists new entries.
Supports `-WhatIf` / `-Confirm` via `SupportsShouldProcess`.

.PARAMETER VolumeName
One or more volume labels to whitelist.

.PARAMETER SerialNumber
One or more volume serial numbers to whitelist.

.PARAMETER DriveLetter
Drive letter to resolve (for example `E` or `E:`). Volume name and serial number are derived from the mounted drive.

.PARAMETER FromMountedVolumes
Adds all currently mounted volumes (respecting include switches) to the whitelist candidate set.

.PARAMETER IncludeFixed
Includes fixed disks when resolving mounted drives.

.EXAMPLE
Add-RenderKitDeviceWhitelistEntry -DriveLetter E
Adds whitelist entries resolved from drive `E:`.

.EXAMPLE
Add-RenderKitDeviceWhitelistEntry -FromMountedVolumes -IncludeFixed
Collects mounted drives (including fixed) and adds new whitelist entries.

.EXAMPLE
Add-RenderKitDeviceWhitelistEntry -VolumeName "EOS_DIGITAL" -SerialNumber "A1B2-C3D4" -WhatIf
Shows what would be written without modifying the whitelist file.

.INPUTS
None. You cannot pipe input to this command.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns path plus added and final whitelist entries, or `$null` when nothing valid was resolved.

.LINK
Get-RenderKitDeviceWhitelist

.LINK
Get-RenderKitDriveCandidate

.LINK
https://github.com/djtroi/RenderKit
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string[]]$VolumeName,
        [string[]]$SerialNumber,
        [string]$DriveLetter,
        [switch]$FromMountedVolumes,
        [switch]$IncludeFixed
    )

    Write-RenderKitLog -Level Debug -Message "Add-RenderKitDeviceWhitelistEntry started: VolumeNameCount=$(@($VolumeName).Count), SerialNumberCount=$(@($SerialNumber).Count), DriveLetter='$DriveLetter', FromMountedVolumes=$($FromMountedVolumes.IsPresent), IncludeFixed=$($IncludeFixed.IsPresent)."

    if (
        -not $VolumeName -and
        -not $SerialNumber -and
        -not $DriveLetter -and
        -not $FromMountedVolumes
    ) {
        Write-RenderKitLog -Level Error -Message "No whitelist input provided. Use -VolumeName, -SerialNumber, -DriveLetter, or -FromMountedVolumes."
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
        $mounted = Get-RenderKitMountedDrive `
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
        $mounted = Get-RenderKitMountedDrive -IncludeFixed -IncludeUnsupportedFileSystem

        $matchedDrive = $mounted |
            Where-Object DriveLetter -eq $normalizedDriveLetter |
            Select-Object -First 1

        if (-not $matchedDrive) {
            Write-RenderKitLog -Level Error -Message "Drive '$DriveLetter' was not found among mounted drives."
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
