# New-RenderKitMapping

## Summary

Creates a new custom mapping file as the basis for media types.

## Syntax

```powershell
New-RenderKitMapping -Id <string>
```

## Prerequisites

- RenderKit is installed and imported in the current PowerShell session.
- All source and destination paths used by the command are accessible.
- The current user has sufficient permissions for write or delete operations.

## Parameters

| Parameter | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `-Id` | `string` | Yes | – | Unique identifier of the rule. |

## Usage

```powershell
New-RenderKitMapping -Name "camera-media"
```

Before running the command, inspect its full help with `Get-Help New-RenderKitMapping -Full`. For commands that support `ShouldProcess`, use `-WhatIf` before making production changes.

## Output and side effects

The command may write status or result objects to the pipeline. Commands that perform writes can also change RenderKit configuration, templates, mappings, project files, or destination packages according to the selected parameters. Verify the operation using the returned paths and properties.

## Notes and safety

> [!IMPORTANT]
> Next, add types with `Add-RenderKitTypeToMapping` and link the mapping to a template.

## Related documentation

- [Installation and updates](installation.md)
- [Function overview](README.md)
- [New-RenderKitMapping source code](../src/Public/New-RenderKitMapping.ps1)