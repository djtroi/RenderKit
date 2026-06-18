# Import-Media

## Summary

Runs the interactive or parameter-driven workflow for finding, filtering, classifying, and transferring media files.

## Syntax

```powershell
Import-Media [-SelectSource <switch>] [-IncludeFixed <switch>] [-IncludeUnsupportedFileSystem <switch>] [-ScanAndFilter <switch>] [-SourcePath <string>] [-FolderFilter <string[]>] [-FromDate <Nullable[datetime]>] [-ToDate <Nullable[datetime]>] [-Wildcard <string[]>] [-InteractiveFilter <switch>] [-PreviewCount <int>] [-AutoSelectAll <switch>] [-AutoConfirm <switch>] [-Classify <switch>] [-ProjectRoot <string>] [-TemplateName <string>] [-UnassignedHandling <string>] [-UnassignedFolderName <string>] [-Transfer <switch>] [-TransferHashAlgorithm <string>]
```

## Prerequisites

- RenderKit is installed and imported in the current PowerShell session.
- All source and destination paths used by the command are accessible.
- The current user has sufficient permissions for write or delete operations.

## Parameters

| Parameter | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `-SelectSource` | `switch` | No | – | Starts interactive source selection. |
| `-IncludeFixed` | `switch` | No | – | Includes fixed drives. |
| `-IncludeUnsupportedFileSystem` | `switch` | No | – | Includes file systems that are unsupported by default. |
| `-ScanAndFilter` | `switch` | No | – | Enables parameter-driven scanning and filtering. |
| `-SourcePath` | `string` | No | – | Source directory to scan. |
| `-FolderFilter` | `string[]` | No | – | Filters direct child folders of the source. |
| `-FromDate` | `Nullable[datetime]` | No | – | Lower bound for the modification date. |
| `-ToDate` | `Nullable[datetime]` | No | – | Upper bound for the modification date. |
| `-Wildcard` | `string[]` | No | – | File name patterns such as `*.mov`. |
| `-InteractiveFilter` | `switch` | No | – | Enables interactive refinement of the result set. |
| `-PreviewCount` | `int` | No | `30` | Maximum number of items displayed in the preview. |
| `-AutoSelectAll` | `switch` | No | – | Automatically selects all matches. |
| `-AutoConfirm` | `switch` | No | – | Automatically confirms the selection. |
| `-Classify` | `switch` | No | – | Classifies files using the selected template and mappings. |
| `-ProjectRoot` | `string` | No | – | Full path to the project directory. |
| `-TemplateName` | `string` | No | – | Name of the user template. |
| `-UnassignedHandling` | `string` | No | `"Prompt"` | Controls how unassigned files are handled. |
| `-UnassignedFolderName` | `string` | No | `"TO SORT"` | Destination folder for unassigned files. |
| `-Transfer` | `switch` | No | – | Transfers the selected files. |
| `-TransferHashAlgorithm` | `string` | No | `"SHA256"` | Hash algorithm used to verify the transfer. |

## Usage

```powershell
Import-Media -ScanAndFilter -SourcePath "E:\DCIM" -Wildcard "*.mp4","*.mov" -Classify -Transfer -ProjectRoot "D:\Projects\ClientA" -TemplateName "default" -AutoSelectAll -AutoConfirm
```

Before running the command, inspect its full help with `Get-Help Import-Media -Full`. For commands that support `ShouldProcess`, use `-WhatIf` before making production changes.

## Output and side effects

The command may write status or result objects to the pipeline. Commands that perform writes can also change RenderKit configuration, templates, mappings, project files, or destination packages according to the selected parameters. Verify the operation using the returned paths and properties.

## Notes and safety

> [!IMPORTANT]
> Calling the command without parameters starts the wizard. Use automatic selection and confirmation only after verifying filters and destination paths.

## Related documentation

- [Installation and updates](installation.md)
- [Function overview](README.md)
- [Import-Media source code](../src/Public/Import-Media.ps1)