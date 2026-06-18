# Add-RenderKitMappingToTemplate

## Summary

Links a mapping ID to an existing user template.

## Syntax

```powershell
Add-RenderKitMappingToTemplate [-TemplateName <string>] [-MappingId <string>]
```

## Prerequisites

- RenderKit is installed and imported in the current PowerShell session.
- All source and destination paths used by the command are accessible.
- The current user has sufficient permissions for write or delete operations.

## Parameters

| Parameter | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `-TemplateName` | `string` | No | – | Name of the user template. |
| `-MappingId` | `string` | No | – | Mapping ID or list of mapping IDs used as a filter. |

## Usage

```powershell
Add-RenderKitMappingToTemplate -TemplateName "client" -MappingId "video"
```

Before running the command, inspect its full help with `Get-Help Add-RenderKitMappingToTemplate -Full`. For commands that support `ShouldProcess`, use `-WhatIf` before making production changes.

## Output and side effects

The command may write status or result objects to the pipeline. Commands that perform writes can also change RenderKit configuration, templates, mappings, project files, or destination packages according to the selected parameters. Verify the operation using the returned paths and properties.

## Notes and safety

> [!IMPORTANT]
> Create the mapping file with `New-RenderKitMapping` before linking it to a template.

## Related documentation

- [Installation and updates](installation.md)
- [Function overview](README.md)
- [Add-RenderKitMappingToTemplate source code](../src/Public/Add-RenderKitMappingToTemplate.ps1)