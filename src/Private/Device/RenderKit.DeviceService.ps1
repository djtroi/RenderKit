function Get-RenderKitDevicesPath {
    return Join-Path (Get-RenderKitRoot) "Devices.json"
}

function New-RenderKitDeviceRegistry {
    return [PSCustomObject]@{
        Version       = "1.0"
        VolumeNames   = @()
        SerialNumbers = @()
    }
}

function Read-RenderKitDeviceRegistry {
    $path = Get-RenderKitDevicesPath

    if (!(Test-Path $path)) {
        $emptyRegistry = New-RenderKitDeviceRegistry
        Write-RenderKitDeviceRegistry -Registry $emptyRegistry | Out-Null
        Write-RenderKitLog -Level Info -Message "Created empty device whitelist at '$path'."
        return $emptyRegistry
    }

    try {
        $registry = Get-Content -Path $path -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Invalid JSON in device whitelist '$path'."
    }

    $version = "1.0"
    if (
        $registry.PSObject.Properties.Name -contains "Version" -and
        -not [string]::IsNullOrWhiteSpace($registry.Version)
    ) {
        $version = [string]$registry.Version
    }

    $volumeNames = @()
    if ($registry.PSObject.Properties.Name -contains "VolumeNames") {
        $volumeNames = @(
            $registry.VolumeNames |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                ForEach-Object { ([string]$_).Trim() } |
                Sort-Object -Unique
        )
    }

    $serialNumbers = @()
    if ($registry.PSObject.Properties.Name -contains "SerialNumbers") {
        $serialNumbers = @(
            $registry.SerialNumbers |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                ForEach-Object { ([string]$_).Trim() } |
                Sort-Object -Unique
        )
    }

    return [PSCustomObject]@{
        Version       = $version
        VolumeNames   = $volumeNames
        SerialNumbers = $serialNumbers
    }
}

function Write-RenderKitDeviceRegistry {
    param(
        [Parameter(Mandatory)]
        [object]$Registry
    )

    $path = Get-RenderKitDevicesPath

    $version = "1.0"
    if (
        $Registry.PSObject.Properties.Name -contains "Version" -and
        -not [string]::IsNullOrWhiteSpace($Registry.Version)
    ) {
        $version = [string]$Registry.Version
    }

    $volumeNames = @()
    if ($Registry.PSObject.Properties.Name -contains "VolumeNames") {
        $volumeNames = @(
            $Registry.VolumeNames |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                ForEach-Object { ([string]$_).Trim() } |
                Sort-Object -Unique
        )
    }

    $serialNumbers = @()
    if ($Registry.PSObject.Properties.Name -contains "SerialNumbers") {
        $serialNumbers = @(
            $Registry.SerialNumbers |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                ForEach-Object { ([string]$_).Trim() } |
                Sort-Object -Unique
        )
    }

    $normalizedRegistry = [PSCustomObject]@{
        Version       = $version
        VolumeNames   = $volumeNames
        SerialNumbers = $serialNumbers
    }

    $normalizedRegistry |
        ConvertTo-Json -Depth 10 |
        Set-Content -Path $path -Encoding UTF8

    return $normalizedRegistry
}

function Resolve-RenderKitDriveLetter {
    param(
        [Parameter(Mandatory)]
        [string]$DriveLetter
    )

    $value = $DriveLetter.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }

    $value = $value.TrimEnd('\')
    if ($value.Length -eq 1) {
        $value = "${value}:"
    }
    elseif ($value.Length -gt 2 -and $value[1] -eq ':') {
        $value = $value.Substring(0, 2)
    }

    return $value.ToUpperInvariant()
}

function Get-RenderKitFileSystemPriority {
    param(
        [string]$FileSystem
    )

    if ([string]::IsNullOrWhiteSpace($FileSystem)) {
        return 0
    }

    switch ($FileSystem.ToUpperInvariant()) {
        "EXFAT" { return 2 }
        "FAT32" { return 1 }
        default { return 0 }
    }
}

function Get-RenderKitMountedDrives {
    [CmdletBinding()]
    param(
        [switch]$IncludeFixed,
        [switch]$IncludeUnsupportedFileSystem
    )

    $allowedDriveTypes = @(2) # Removable
    if ($IncludeFixed) {
        $allowedDriveTypes += 3 # Fixed
    }

    try {
        $logicalDisks = Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction Stop
    }
    catch {
        throw "Unable to query mounted drives. $_"
    }

    $result = @()
    foreach ($disk in $logicalDisks) {
        $driveType = [int]$disk.DriveType
        if ($allowedDriveTypes -notcontains $driveType) {
            continue
        }

        $fileSystem = [string]$disk.FileSystem
        $fileSystemPriority = Get-RenderKitFileSystemPriority -FileSystem $fileSystem

        if (-not $IncludeUnsupportedFileSystem -and $fileSystemPriority -eq 0) {
            continue
        }

        $sizeGB = $null
        if ($disk.Size) {
            $sizeGB = [Math]::Round(([double]$disk.Size / 1GB), 2)
        }

        $freeGB = $null
        if ($disk.FreeSpace) {
            $freeGB = [Math]::Round(([double]$disk.FreeSpace / 1GB), 2)
        }

        $result += [PSCustomObject]@{
            DriveLetter        = [string]$disk.DeviceID
            VolumeName         = [string]$disk.VolumeName
            FileSystem         = $fileSystem
            FileSystemPriority = $fileSystemPriority
            VolumeSerialNumber = [string]$disk.VolumeSerialNumber
            DriveType          = $driveType
            IsRemovable        = $driveType -eq 2
            SizeGB             = $sizeGB
            FreeGB             = $freeGB
        }
    }

    return $result
}

function Get-RenderKitDriveCandidatesInternal {
    [CmdletBinding()]
    param(
        [switch]$IncludeFixed,
        [switch]$IncludeUnsupportedFileSystem
    )

    $registry = Read-RenderKitDeviceRegistry
    $drives = Get-RenderKitMountedDrives `
        -IncludeFixed:$IncludeFixed `
        -IncludeUnsupportedFileSystem:$IncludeUnsupportedFileSystem

    $candidates = @()
    foreach ($drive in $drives) {
        $isWhitelistedVolumeName = $false
        if (-not [string]::IsNullOrWhiteSpace($drive.VolumeName)) {
            $isWhitelistedVolumeName = $registry.VolumeNames -contains $drive.VolumeName
        }

        $isWhitelistedSerialNumber = $false
        if (-not [string]::IsNullOrWhiteSpace($drive.VolumeSerialNumber)) {
            $isWhitelistedSerialNumber = $registry.SerialNumbers -contains $drive.VolumeSerialNumber
        }

        $score = 0
        if ($drive.FileSystemPriority -eq 2) {
            $score += 20
        }
        elseif ($drive.FileSystemPriority -eq 1) {
            $score += 10
        }

        if ($drive.IsRemovable) {
            $score += 15
        }

        if ($isWhitelistedVolumeName) {
            $score += 40
        }

        if ($isWhitelistedSerialNumber) {
            $score += 80
        }

        $candidates += [PSCustomObject]@{
            DriveLetter               = $drive.DriveLetter
            VolumeName                = $drive.VolumeName
            FileSystem                = $drive.FileSystem
            FileSystemPriority        = $drive.FileSystemPriority
            IsSupportedFileSystem     = $drive.FileSystemPriority -gt 0
            VolumeSerialNumber        = $drive.VolumeSerialNumber
            DriveType                 = $drive.DriveType
            IsRemovable               = $drive.IsRemovable
            SizeGB                    = $drive.SizeGB
            FreeGB                    = $drive.FreeGB
            IsWhitelistedVolumeName   = $isWhitelistedVolumeName
            IsWhitelistedSerialNumber = $isWhitelistedSerialNumber
            Score                     = $score
        }
    }

    return $candidates | Sort-Object `
        @{ Expression = "Score"; Descending = $true }, `
        @{ Expression = "FileSystemPriority"; Descending = $true }, `
        @{ Expression = "DriveLetter"; Descending = $false }
}
