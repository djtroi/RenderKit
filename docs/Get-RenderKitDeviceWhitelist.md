# Get-RenderKitDeviceWhitelist

## Summary

Reads the stored volume names and serial numbers from the device whitelist.

## Syntax

```powershell
Get-RenderKitDeviceWhitelist
```

## Prerequisites

- RenderKit is installed and imported in the current PowerShell session.
- All source and destination paths used by the command are accessible.
- The current user has sufficient permissions for write or delete operations.

## Parameters

| Parameter | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| – | – | – | – | The command has no parameters. |

## Usage

```powershell
Get-RenderKitDeviceWhitelist
```

Before running the command, inspect its full help with `Get-Help Get-RenderKitDeviceWhitelist -Full`. For commands that support `ShouldProcess`, use `-WhatIf` before making production changes.

## Output and side effects

The command may write status or result objects to the pipeline. Commands that perform writes can also change RenderKit configuration, templates, mappings, project files, or destination packages according to the selected parameters. Verify the operation using the returned paths and properties.

## Notes and safety

> [!IMPORTANT]
> The command does not modify data and can be used to review the whitelist before drive detection.

## Related documentation

- [Installation and updates](installation.md)
- [Function overview](README.md)
- [Get-RenderKitDeviceWhitelist source code](../src/Public/Get-RenderKitDeviceWhitelist.ps1)