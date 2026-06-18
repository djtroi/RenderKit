# Select-RenderKitDriveCandidate

## Summary

Opens the interactive selector for detected media drives.

## Syntax

```powershell
Select-RenderKitDriveCandidate [-IncludeFixed <switch>] [-IncludeUnsupportedFileSystem <switch>]
```

## Prerequisites

- RenderKit is installed and imported in the current PowerShell session.
- All source and destination paths used by the command are accessible.
- The current user has sufficient permissions for write or delete operations.

## Parameters

| Parameter | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `-IncludeFixed` | `switch` | No | – | Includes fixed drives. |
| `-IncludeUnsupportedFileSystem` | `switch` | No | – | Includes file systems that are unsupported by default. |

## Usage

```powershell
Select-RenderKitDriveCandidate -IncludeFixed
```

Before running the command, inspect its full help with `Get-Help Select-RenderKitDriveCandidate -Full`. For commands that support `ShouldProcess`, use `-WhatIf` before making production changes.

## Output and side effects

The command may write status or result objects to the pipeline. Commands that perform writes can also change RenderKit configuration, templates, mappings, project files, or destination packages according to the selected parameters. Verify the operation using the returned paths and properties.

## Notes and safety

> [!IMPORTANT]
> This command requires an interactive console. Use `Get-RenderKitDriveCandidate` for automation.

## Related documentation

- [Installation and updates](installation.md)
- [Function overview](README.md)
- [Select-RenderKitDriveCandidate source code](../src/Public/Select-RenderKitDriveCandidate.ps1)
