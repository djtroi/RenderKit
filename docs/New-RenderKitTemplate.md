# New-RenderKitTemplate

## Summary

Creates a new custom project template.

## Syntax

```powershell
New-RenderKitTemplate -Name <string>
```

## Prerequisites

- RenderKit is installed and imported in the current PowerShell session.
- All source and destination paths used by the command are accessible.
- The current user has sufficient permissions for write or delete operations.

## Parameters

| Parameter | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `-Name` | `string` | Yes | – | Display name or name of the new object. |

## Usage

```powershell
New-RenderKitTemplate -Name "client-delivery"
```

Before running the command, inspect its full help with `Get-Help New-RenderKitTemplate -Full`. For commands that support `ShouldProcess`, use `-WhatIf` before making production changes.

## Output and side effects

The command may write status or result objects to the pipeline. Commands that perform writes can also change RenderKit configuration, templates, mappings, project files, or destination packages according to the selected parameters. Verify the operation using the returned paths and properties.

## Notes and safety

> [!IMPORTANT]
> Next, add folders, mappings, and deliverables with the corresponding `Add-*` commands.

## Related documentation

- [Installation and updates](installation.md)
- [Function overview](README.md)
- [New-RenderKitTemplate source code](../src/Public/New-RenderKitTemplate.ps1)