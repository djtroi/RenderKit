# Add-RenderKitTypeToMapping

## Summary

Adds a media type and its file extensions to a mapping.

## Syntax

```powershell
Add-RenderKitTypeToMapping [-MappingId <string>] [-TypeName <string>] [-Extensions <string[]>]
```

## Prerequisites

- RenderKit is installed and imported in the current PowerShell session.
- All source and destination paths used by the command are accessible.
- The current user has sufficient permissions for write or delete operations.

## Parameters

| Parameter | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `-MappingId` | `string` | No | – | Mapping ID or list of mapping IDs used as a filter. |
| `-TypeName` | `string` | No | – | Logical media type. |
| `-Extensions` | `string[]` | No | – | File extensions assigned to the type. |

## Usage

```powershell
Add-RenderKitTypeToMapping -MappingId "video" -TypeName "Video" -Extensions ".mp4", ".mov"
```

Before running the command, inspect its full help with `Get-Help Add-RenderKitTypeToMapping -Full`. For commands that support `ShouldProcess`, use `-WhatIf` before making production changes.

## Output and side effects

The command may write status or result objects to the pipeline. Commands that perform writes can also change RenderKit configuration, templates, mappings, project files, or destination packages according to the selected parameters. Verify the operation using the returned paths and properties.

## Notes and safety

> [!IMPORTANT]
> Specify file extensions with a leading period.

## Related documentation

- [Installation and updates](installation.md)
- [Function overview](README.md)
- [Add-RenderKitTypeToMapping source code](../src/Public/Add-RenderKitTypeToMapping.ps1)