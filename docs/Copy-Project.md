# Copy-Project

## Summary

Copies an existing RenderKit project and creates a new project identity for the copy.

## Syntax

```powershell
Copy-Project -ProjectName <string> [-NewName <string>] [-Path <string>] [-DryRun <switch>]
```

## Prerequisites

- RenderKit is installed and imported in the current PowerShell session.
- All source and destination paths used by the command are accessible.
- The current user has sufficient permissions for write or delete operations.

## Parameters

| Parameter | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `-ProjectName` | `string` | Yes | – | Name of the project. |
| `-NewName` | `string` | No | – | Name of the copy or the new project name. |
| `-Path` | `string` | No | – | Source path or package path, depending on the command. |
| `-DryRun` | `switch` | No | – | Simulates the operation without making changes. |

## Usage

```powershell
Copy-Project -ProjectName "ClientA_2026" -NewName "ClientA_2026_Copy" -DryRun
```

Before running the command, inspect its full help with `Get-Help Copy-Project -Full`. For commands that support `ShouldProcess`, use `-WhatIf` before making production changes.

## Output and side effects

The command may write status or result objects to the pipeline. Commands that perform writes can also change RenderKit configuration, templates, mappings, project files, or destination packages according to the selected parameters. Verify the operation using the returned paths and properties.

## Notes and safety

> [!IMPORTANT]
> The implementation is named `Copy-Project`, but the current manifest exports `Clone-Project`. Until this mismatch is resolved, direct invocation may not be available in every installation artifact.

## Related documentation

- [Installation and updates](installation.md)
- [Function overview](README.md)
- [Copy-Project source code](../src/Public/Copy-Project.ps1)