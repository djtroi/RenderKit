# Add-RenderKitDeliverableToTemplate

## Summary

Creates or updates a reusable deliverable rule in a user template.

## Syntax

```powershell
Add-RenderKitDeliverableToTemplate -TemplateName <string> -Id <string> [-Name <string>] -SourceFolder <string[]> [-Recursive <switch>] [-MappingId <string[]>] [-TypeName <string[]>] [-IncludeExtension <string[]>] [-ExcludePattern <string[]>] [-DefaultPackage <switch>]
```

## Prerequisites

- RenderKit is installed and imported in the current PowerShell session.
- All source and destination paths used by the command are accessible.
- The current user has sufficient permissions for write or delete operations.

## Parameters

| Parameter | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `-TemplateName` | `string` | Yes | – | Name of the user template. |
| `-Id` | `string` | Yes | – | Unique identifier of the rule. |
| `-Name` | `string` | No | – | Display name or name of the new object. |
| `-SourceFolder` | `string[]` | Yes | – | One or more source folders relative to the project root. |
| `-Recursive` | `switch` | No | – | Includes subfolders. |
| `-MappingId` | `string[]` | No | – | Mapping ID or list of mapping IDs used as a filter. |
| `-TypeName` | `string[]` | No | – | Logical media type. |
| `-IncludeExtension` | `string[]` | No | – | File extensions to include. |
| `-ExcludePattern` | `string[]` | No | – | Patterns to exclude. |
| `-DefaultPackage` | `switch` | No | – | Marks the rule for the default package. |

## Usage

```powershell
Add-RenderKitDeliverableToTemplate -TemplateName "client" -Id "review" -Name "Review Files" -SourceFolder "Exports/Review" -Recursive -IncludeExtension ".mp4" -DefaultPackage
```

Before running the command, inspect its full help with `Get-Help Add-RenderKitDeliverableToTemplate -Full`. For commands that support `ShouldProcess`, use `-WhatIf` before making production changes.

## Output and side effects

The command may write status or result objects to the pipeline. Commands that perform writes can also change RenderKit configuration, templates, mappings, project files, or destination packages according to the selected parameters. Verify the operation using the returned paths and properties.

## Notes and safety

> [!IMPORTANT]
> An existing rule with the same ID is replaced. Use `-WhatIf` to preview the intended change.

## Related documentation

- [Installation and updates](installation.md)
- [Function overview](README.md)
- [Add-RenderKitDeliverableToTemplate source code](../src/Public/Add-RenderKitDeliverableToTemplate.ps1)