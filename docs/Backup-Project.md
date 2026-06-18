# Backup-Project

## Summary

Cleans a project according to a profile, creates a ZIP archive, verifies its contents, and writes a manifest.

## Syntax

```powershell
Backup-Project -ProjectName <string> [-Path <string>] [-Preset <string[]>] [-DestinationRoot <string>] [-KeepEmptyFolders <switch>] [-KeepSourceProject <switch>] [-DryRun <switch>]
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
| `-Preset` | `string[]` | No | `@("General")` | Cleanup profiles. |
| `-DestinationRoot` | `string` | No | – | Destination root directory. |
| `-KeepEmptyFolders` | `switch` | No | – | Keeps empty folders. |
| `-KeepSourceProject` | `switch` | No | – | Keeps the source project after the backup. |
| `-DryRun` | `switch` | No | – | Simulates the operation without making changes. |

## Usage

```powershell
Backup-Project -ProjectName "ClientA_2026" -DestinationRoot "E:\Backups" -KeepSourceProject
```

Before running the command, inspect its full help with `Get-Help Backup-Project -Full`. For commands that support `ShouldProcess`, use `-WhatIf` before making production changes.

## Output and side effects

The command may write status or result objects to the pipeline. Commands that perform writes can also change RenderKit configuration, templates, mappings, project files, or destination packages according to the selected parameters. Verify the operation using the returned paths and properties.

## Notes and safety

> [!IMPORTANT]
> Without `-KeepSourceProject`, the source project can be removed after a successful backup. Test the workflow with `-DryRun` first.

## Related documentation

- [Installation and updates](installation.md)
- [Function overview](README.md)
- [Backup-Project source code](../src/Public/Backup-Project.ps1)
