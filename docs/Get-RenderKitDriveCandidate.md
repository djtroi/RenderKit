# Get-RenderKitDriveCandidate

## Summary

Discovers and scores mounted drives as potential media sources.

## Syntax

```powershell
Get-RenderKitDriveCandidate [-IncludeFixed <switch>] [-IncludeUnsupportedFileSystem <switch>] [-DisableInteractiveFallback <switch>]
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
| `-DisableInteractiveFallback` | `switch` | No | – | Controls the corresponding command behavior. |

## Usage

```powershell
Get-RenderKitDriveCandidate -IncludeFixed | Format-Table
```

Before running the command, inspect its full help with `Get-Help Get-RenderKitDriveCandidate -Full`. For commands that support `ShouldProcess`, use `-WhatIf` before making production changes.

## Output and side effects

The command may write status or result objects to the pipeline. Commands that perform writes can also change RenderKit configuration, templates, mappings, project files, or destination packages according to the selected parameters. Verify the operation using the returned paths and properties.

## Notes and safety

> [!IMPORTANT]
> Fixed drives and unsupported file systems are included only when the corresponding switches are specified.

## Related documentation

- [Installation and updates](installation.md)
- [Function overview](README.md)
- [Get-RenderKitDriveCandidate source code](../src/Public/Get-RenderKitDriveCandidate.ps1)