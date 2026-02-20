function Get-RenderKitDeviceWhitelist {
    [CmdletBinding()]
    param()

    $registry = Read-RenderKitDeviceRegistry

    return [PSCustomObject]@{
        Path          = Get-RenderKitDevicesPath
        Version       = $registry.Version
        VolumeNames   = $registry.VolumeNames
        SerialNumbers = $registry.SerialNumbers
    }
}
