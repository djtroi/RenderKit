# Export-Project

## Summary

Exports a project as a lightweight manifest or a self-contained project package.

## Syntax

```powershell
Export-Project -ProjectRoot <string> -DestinationPath <string> [-Mode <string>] [-CompressionMethod <string>] [-CompressionLevel <string>] [-HashAlgorithm <string[]>] [-IncludeMd5 <switch>] [-IncludeAbsolutePaths <switch>]
```

## Prerequisites

- RenderKit is installed and imported in the current PowerShell session.
- All source and destination paths used by the command are accessible.
- The current user has sufficient permissions for write or delete operations.

## Parameters

| Parameter | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `-ProjectRoot` | `string` | Yes | – | Full path to the project directory. |
| `-DestinationPath` | `string` | Yes | – | Destination file path for the manifest/package, or an existing destination directory. Directory destinations create `<ProjectRootName>.rkit` for `ManifestOnly` exports and `<ProjectRootName>.rkitpkg` for `SelfContained` exports. |
| `-Mode` | `string` | No | `'ManifestOnly'` | Export mode. |
| `-CompressionMethod` | `string` | No | `'Zip'` | Compression method. |
| `-CompressionLevel` | `string` | No | `'Optimal'` | Compression level. |
| `-HashAlgorithm` | `string[]` | No | `@('SHA256')` | Algorithms used to generate checksums. |
| `-IncludeMd5` | `switch` | No | – | Adds MD5 checksums. |
| `-IncludeAbsolutePaths` | `switch` | No | – | Includes absolute paths in the manifest. |

## Usage

```powershell
Export-Project -ProjectRoot "D:\Projects\ClientA" -DestinationPath "E:\Transfer" -Mode ManifestOnly
```

Exports `D:\Projects\ClientA` to `E:\Transfer\ClientA.rkit`.


Before running the command, inspect its full help with `Get-Help Export-Project -Full`. For commands that support `ShouldProcess`, use `-WhatIf` before making production changes.

## Output and side effects

The command may write status or result objects to the pipeline. Commands that perform writes can also change RenderKit configuration, templates, mappings, project files, or destination packages according to the selected parameters. Verify the operation using the returned paths and properties.

## Notes and safety

> [!IMPORTANT]
> `ManifestOnly` references project content; `SelfContained` includes the files in a portable package.

## Related documentation

- [Installation and updates](installation.md)
- [Function overview](README.md)
- [Export-Project source code](../src/Public/Export-Project.ps1)