# Remove-Project

## Summary

Removes a RenderKit project, including its project directory.

## Syntax

```powershell
Remove-Project -ProjectName <string> [-Path <string>] [-DryRun <switch>]
```

## Prerequisites

- RenderKit is installed and imported in the current PowerShell session.
- All source and destination paths used by the command are accessible.
- The current user has sufficient permissions for write or delete operations.

## Parameters

| Parameter | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `-ProjectName` | `string` | Yes | – | Name of the project. |
| `-Path` | `string` | No | – | Source path or package path, depending on the command. |
| `-DryRun` | `switch` | No | – | Simulates the operation without making changes. |

## Usage

```powershell
Remove-Project -ProjectName "ClientA_2026" -DryRun
```

Before running the command, inspect its full help with `Get-Help Remove-Project -Full`. For commands that support `ShouldProcess`, use `-WhatIf` before making production changes.

## Output and side effects

The command may write status or result objects to the pipeline. Commands that perform writes can also change RenderKit configuration, templates, mappings, project files, or destination packages according to the selected parameters. Verify the operation using the returned paths and properties.

## Notes and safety

> [!IMPORTANT]
> This operation is destructive. Preview it with `-DryRun` or `-WhatIf` first.

## Related documentation

- [Installation and updates](installation.md)
- [Function overview](README.md)
- [Remove-Project source code](../src/Public/Remove-Project.ps1)