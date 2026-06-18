# Set-ProjectRoot

## Summary

Stores the default project root in the RenderKit configuration.

## Syntax

```powershell
Set-ProjectRoot -Path <string>
```

## Prerequisites

- RenderKit is installed and imported in the current PowerShell session.
- All source and destination paths used by the command are accessible.
- The current user has sufficient permissions for write or delete operations.

## Parameters

| Parameter | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `-Path` | `string` | Yes | – | Source path or package path, depending on the command. |

## Usage

```powershell
Set-ProjectRoot -Path "D:\Editing_Projects"
```

Before running the command, inspect its full help with `Get-Help Set-ProjectRoot -Full`. For commands that support `ShouldProcess`, use `-WhatIf` before making production changes.

## Output and side effects

The command may write status or result objects to the pipeline. Commands that perform writes can also change RenderKit configuration, templates, mappings, project files, or destination packages according to the selected parameters. Verify the operation using the returned paths and properties.

## Notes and safety

> [!IMPORTANT]
> The destination directory must already exist. The setting is used by subsequent commands when they do not receive an explicit path.

## Related documentation

- [Installation and updates](installation.md)
- [Function overview](README.md)
- [Set-ProjectRoot source code](../src/Public/Set-ProjectRoot.ps1)