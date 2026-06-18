# Rename-Project

## Summary

Renames a project directory and its metadata without changing the project ID.

## Syntax

```powershell
Rename-Project -ProjectName <string> -NewName <string> [-Path <string>] [-DryRun <switch>]
```

## Prerequisites

- RenderKit is installed and imported in the current PowerShell session.
- All source and destination paths used by the command are accessible.
- The current user has sufficient permissions for write or delete operations.

## Parameters

| Parameter | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `-ProjectName` | `string` | Yes | – | Name of the project. |
| `-NewName` | `string` | Yes | – | Name of the copy or the new project name. |
| `-Path` | `string` | No | – | Source path or package path, depending on the command. |
| `-DryRun` | `switch` | No | – | Simulates the operation without making changes. |

## Usage

```powershell
Rename-Project -ProjectName "ClientA_2026" -NewName "ClientA_2026_Final" -WhatIf
```

Before running the command, inspect its full help with `Get-Help Rename-Project -Full`. For commands that support `ShouldProcess`, use `-WhatIf` before making production changes.

## Output and side effects

The command may write status or result objects to the pipeline. Commands that perform writes can also change RenderKit configuration, templates, mappings, project files, or destination packages according to the selected parameters. Verify the operation using the returned paths and properties.

## Notes and safety

> [!IMPORTANT]
> The destination name must not already exist; the existing GUID is preserved.

## Related documentation

- [Installation and updates](installation.md)
- [Function overview](README.md)
- [Rename-Project source code](../src/Public/Rename-Project.ps1)