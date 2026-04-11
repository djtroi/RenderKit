Register-RenderKitFunction "Get-RenderKitDeviceWhitelist"
function Get-RenderKitDeviceWhitelist {
    <#
.SYNOPSIS
Returns the configured device whitelist.

.DESCRIPTION
Reads the device registry and returns version, volume names, and serial numbers.

.EXAMPLE
Get-RenderKitDeviceWhitelist
Returns current whitelist metadata from `%APPDATA%\RenderKit\Devices.json`.

.INPUTS
None. You cannot pipe input to this command.

.OUTPUTS
System.Management.Automation.PSCustomObject
Returns `Path`, `Version`, `VolumeNames`, and `SerialNumbers`.

.LINK
Add-RenderKitDeviceWhitelistEntry

.LINK
Get-RenderKitDriveCandidate

.LINK
https://github.com/djtroi/RenderKit
#>
    [CmdletBinding()]
    param()

    Write-RenderKitLog -Level Debug -Message "Get-RenderKitDeviceWhitelist started."

    $registry = Read-RenderKitDeviceRegistry

    return [PSCustomObject]@{
        Path          = Get-RenderKitDevicesPath
        Version       = $registry.Version
        VolumeNames   = $registry.VolumeNames
        SerialNumbers = $registry.SerialNumbers
    }
}
