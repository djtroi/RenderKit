# Add-RenderKitDeviceWhitelistEntry

## Summary

Adds volume identifiers to the whitelist used for automatic source-drive detection.

## Syntax

```powershell
Add-RenderKitDeviceWhitelistEntry [-VolumeName <string[]>] [-SerialNumber <string[]>] [-DriveLetter <string>] [-FromMountedVolumes <switch>] [-IncludeFixed <switch>]
```

## Prerequisites

- RenderKit is installed and imported in the current PowerShell session.
- All source and destination paths used by the command are accessible.
- The current user has sufficient permissions for write or delete operations.

## Parameters

| Parameter | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `-VolumeName` | `string[]` | No | – | Volume names to store. |
| `-SerialNumber` | `string[]` | No | – | Volume serial numbers to store. |
| `-DriveLetter` | `string` | No | – | Drive letter to resolve. |
| `-FromMountedVolumes` | `switch` | No | – | Uses currently mounted volumes. |
| `-IncludeFixed` | `switch` | No | – | Includes fixed drives. |

## Usage

```powershell
Add-RenderKitDeviceWhitelistEntry -DriveLetter E -WhatIf
```

Before running the command, inspect its full help with `Get-Help Add-RenderKitDeviceWhitelistEntry -Full`. For commands that support `ShouldProcess`, use `-WhatIf` before making production changes.

## Output and side effects

The command may write status or result objects to the pipeline. Commands that perform writes can also change RenderKit configuration, templates, mappings, project files, or destination packages according to the selected parameters. Verify the operation using the returned paths and properties.

## Notes and safety

> [!IMPORTANT]
> At least one source (`VolumeName`, `SerialNumber`, `DriveLetter`, or `FromMountedVolumes`) is required.

## Related documentation

- [Installation and updates](installation.md)
- [Function overview](README.md)
- [Add-RenderKitDeviceWhitelistEntry source code](../src/Public/Add-RenderKitDeviceWhitelistEntry.ps1)