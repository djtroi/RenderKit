# New-Project

## Summary

Creates a new project from a RenderKit template and writes project metadata.

## Syntax

```powershell
New-Project -Name <string> [-Template <string>] [-Path <string>]
```

## Prerequisites

- RenderKit is installed and imported in the current PowerShell session.
- All source and destination paths used by the command are accessible.
- The current user has sufficient permissions for write or delete operations.

## Parameters

| Parameter | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `-Name` | `string` | Yes | – | Display name or name of the new object. |
| `-Template` | `string` | No | – | Name of the project template. |
| `-Path` | `string` | No | – | Source path or package path, depending on the command. |

## Usage

```powershell
New-Project -Name "ClientA_2026" -Template "youtube"
```

Before running the command, inspect its full help with `Get-Help New-Project -Full`. For commands that support `ShouldProcess`, use `-WhatIf` before making production changes.

## Output and side effects

The command may write status or result objects to the pipeline. Commands that perform writes can also change RenderKit configuration, templates, mappings, project files, or destination packages according to the selected parameters. Verify the operation using the returned paths and properties.

## Notes and safety

> [!IMPORTANT]
> When no explicit path is supplied, the command uses the project root configured with `Set-ProjectRoot`.

## Related documentation

- [Installation and updates](installation.md)
- [Function overview](README.md)
- [New-Project source code](../src/Public/New-Project.ps1)