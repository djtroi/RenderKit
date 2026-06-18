# Send-Project

## Summary

Collects template-defined deliverables and creates a folder, ZIP archive, or manifest.

## Syntax

```powershell
Send-Project -ProjectRoot <string> -DestinationPath <string> [-DeliveryRule <string>] [-AllDeliverables <switch>] [-MappingId <string[]>] [-TypeName <string[]>] [-IncludeExtension <string[]>] [-ExcludePattern <string[]>] [-PackageMode <string>] [-CompressionLevel <string>] [-HashAlgorithm <string[]>] [-IncludeMd5 <switch>] [-PassThru <switch>]
```

## Prerequisites

- RenderKit is installed and imported in the current PowerShell session.
- All source and destination paths used by the command are accessible.
- The current user has sufficient permissions for write or delete operations.

## Parameters

| Parameter | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `-ProjectRoot` | `string` | Yes | – | Full path to the project directory. |
| `-DestinationPath` | `string` | Yes | – | Destination path for the manifest, package, or delivery. |
| `-DeliveryRule` | `string` | No | – | ID of a deliverable rule. |
| `-AllDeliverables` | `switch` | No | – | Uses all deliverable rules in the template. |
| `-MappingId` | `string[]` | No | – | Mapping ID or list of mapping IDs used as a filter. |
| `-TypeName` | `string[]` | No | – | Logical media type. |
| `-IncludeExtension` | `string[]` | No | – | File extensions to include. |
| `-ExcludePattern` | `string[]` | No | – | Patterns to exclude. |
| `-PackageMode` | `string` | No | `'Zip'` | Output format for the delivery. |
| `-CompressionLevel` | `string` | No | `'Optimal'` | Compression level. |
| `-HashAlgorithm` | `string[]` | No | `@('SHA256')` | Algorithms used to generate checksums. |
| `-IncludeMd5` | `switch` | No | – | Adds MD5 checksums. |
| `-PassThru` | `switch` | No | – | Returns the result object to the pipeline. |

## Usage

```powershell
Send-Project -ProjectRoot "D:\Projects\ClientA" -DestinationPath "E:\Delivery\ClientA-review.zip" -DeliveryRule "review" -PackageMode Zip
```

Before running the command, inspect its full help with `Get-Help Send-Project -Full`. For commands that support `ShouldProcess`, use `-WhatIf` before making production changes.

## Output and side effects

The command may write status or result objects to the pipeline. Commands that perform writes can also change RenderKit configuration, templates, mappings, project files, or destination packages according to the selected parameters. Verify the operation using the returned paths and properties.

## Notes and safety

> [!IMPORTANT]
> Review the template deliverable rules. If no files match, the resulting package can be empty.

## Related documentation

- [Installation and updates](installation.md)
- [Function overview](README.md)
- [Send-Project source code](../src/Public/Send-Project.ps1)