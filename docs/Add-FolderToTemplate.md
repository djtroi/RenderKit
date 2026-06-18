# Add-FolderToTemplate

## Summary

Recursively adds a folder path to an existing user template.

## Syntax

```powershell
Add-FolderToTemplate -TemplateName <string> -FolderPath <string> [-MappingId <string>]
```

## Prerequisites

- RenderKit is installed and imported in the current PowerShell session.
- All source and destination paths used by the command are accessible.
- The current user has sufficient permissions for write or delete operations.

## Parameters

| Parameter | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `-TemplateName` | `string` | Yes | – | Name of the user template. |
| `-FolderPath` | `string` | Yes | – | Relative folder path. |
| `-MappingId` | `string` | No | – | Mapping ID or list of mapping IDs used as a filter. |

## Usage

```powershell
Add-FolderToTemplate -TemplateName "client" -FolderPath "Footage/CameraA" -MappingId "video"
```

Before running the command, inspect its full help with `Get-Help Add-FolderToTemplate -Full`. For commands that support `ShouldProcess`, use `-WhatIf` before making production changes.

## Output and side effects

The command may write status or result objects to the pipeline. Commands that perform writes can also change RenderKit configuration, templates, mappings, project files, or destination packages according to the selected parameters. Verify the operation using the returned paths and properties.

## Notes and safety

> [!IMPORTANT]
> Use `/` or `\` as a path separator. A mapping ID is assigned only to the final folder in the path.

## Related documentation

- [Installation and updates](installation.md)
- [Function overview](README.md)
- [Add-FolderToTemplate source code](../src/Public/Add-FolderToTemplate.ps1)