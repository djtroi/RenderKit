# Import-Project

## Summary

Imports a RenderKit manifest or self-contained project package into a destination directory.

## Syntax

```powershell
Import-Project -Path <string> -DestinationRoot <string> [-ProjectName <string>] [-TransferMode <string>] [-VerifyHash <switch>] [-ConflictAction <string>]
```

## Prerequisites

- RenderKit is installed and imported in the current PowerShell session.
- All source and destination paths used by the command are accessible.
- The current user has sufficient permissions for write or delete operations.

## Parameters

| Parameter | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `-Path` | `string` | Yes | – | Source path or package path, depending on the command. |
| `-DestinationRoot` | `string` | Yes | – | Destination root directory. |
| `-ProjectName` | `string` | No | – | Name of the project. |
| `-TransferMode` | `string` | No | `'Copy'` | Imports by copying files or by creating a link-only project. |
| `-VerifyHash` | `switch` | No | – | Verifies available hash values during import. |
| `-ConflictAction` | `string` | No | `'Error'` | Controls how destination conflicts are handled. |

## Usage

```powershell
Import-Project -Path "E:\Transfer\ClientA.rkitpkg" -DestinationRoot "D:\Projects" -VerifyHash
```

Before running the command, inspect its full help with `Get-Help Import-Project -Full`. For commands that support `ShouldProcess`, use `-WhatIf` before making production changes.

## Output and side effects

The command may write status or result objects to the pipeline. Commands that perform writes can also change RenderKit configuration, templates, mappings, project files, or destination packages according to the selected parameters. Verify the operation using the returned paths and properties.

## Notes and safety

> [!IMPORTANT]
> Use `ConflictAction` to determine whether existing files cause an error, are skipped, or are overwritten.

## Related documentation

- [Installation and updates](installation.md)
- [Function overview](README.md)
- [Import-Project source code](../src/Public/Import-Project.ps1)