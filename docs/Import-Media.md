# Import-Media

## Summary

Runs the interactive or parameter-driven workflow for finding, filtering, classifying, and transferring media files.

## Syntax

```powershell
Import-Media [-SelectSource <switch>] [-IncludeFixed <switch>] [-IncludeUnsupportedFileSystem <switch>] [-ScanAndFilter <switch>] [-SourcePath <string>] [-FolderFilter <string[]>] [-FromDate <Nullable[datetime]>] [-ToDate <Nullable[datetime]>] [-Wildcard <string[]>] [-InteractiveFilter <switch>] [-PreviewCount <int>] [-AutoSelectAll <switch>] [-AutoConfirm <switch>] [-Classify <switch>] [-ProjectRoot <string>] [-TemplateName <string>] [-UnassignedHandling <string>] [-UnassignedFolderName <string>] [-Transfer <switch>] [-TransferHashAlgorithm <string>] [-TransferVerificationMode <string>] [-TransferProfile <string>] [-SmallFileThresholdMB <int>] [-SmallFileConcurrency <int>] [-LargeFileConcurrency <int>] [-VerifyConcurrency <int>] [-MaxInFlightMB <int>] [-TransferBufferSizeMB <int>] [-SourceDisposition <string>]
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
| `-TransferHashAlgorithm` | `string` | No | `"SHA256"` | Hash algorithm used when `-TransferVerificationMode Full` is selected. |
| `-TransferVerificationMode` | `string` | No | `"Fast"` | `Fast` uses the native file-copy path, checks completed staging length, and commits atomically. `Full` hashes the source while copying and independently hashes staging before commit. |
| `-TransferProfile` | `string` | No | `"Maximum"` | Scheduler profile. `Maximum` enables the throughput-oriented pipeline and adaptive copy concurrency. |
| `-SmallFileThresholdMB` | `int` | No | `64` | Largest file size assigned to the small-file scheduler. |
| `-SmallFileConcurrency` | `int` | No | `0` | Small-file worker count. `0` selects the profile default, up to four workers for `Maximum`. |
| `-LargeFileConcurrency` | `int` | No | `0` | Large-file copy worker count. `0` selects one copy stream; verification can still overlap the next copy. |
| `-VerifyConcurrency` | `int` | No | `0` | Independent staging read-back worker count. `0` selects up to four workers for `Maximum`, two for `Balanced`, or one for `Conservative`. |
| `-MaxInFlightMB` | `int` | No | `512` | Estimated resident buffer budget across copy and verification workers. Logical file size does not monopolize this budget. |
| `-TransferBufferSizeMB` | `int` | No | `8` | Buffer size used by copy and staging-verification streams. |
| `-SourceDisposition` | `string` | No | `"Keep"` | `Keep` copies and hash-verifies. Explicit `Move` performs rename-only transfer on the same Windows volume and rolls back if commit fails. |

## Usage

```powershell
Import-Media -ScanAndFilter -SourcePath "E:\DCIM" -Wildcard "*.mp4","*.mov" -Classify -Transfer -ProjectRoot "D:\Projects\ClientA" -TemplateName "default" -AutoSelectAll -AutoConfirm
```

For an explicit same-volume move:

```powershell
Import-Media -ScanAndFilter -SourcePath "D:\Cards\DCIM" -Classify -Transfer -ProjectRoot "D:\Projects\ClientA" -TemplateName "default" -AutoSelectAll -AutoConfirm -SourceDisposition Move
```

Before running the command, inspect its full help with `Get-Help Import-Media -Full`. For commands that support `ShouldProcess`, use `-WhatIf` before making production changes.

## Output and side effects

The command may write status or result objects to the pipeline. Transfer results distinguish physical copy, staging verification, and end-to-end measurements through `TransferCopiedBytes`, `TransferVerifiedBytes`, `TransferCopyAverageSpeedMBps`, `TransferVerificationAverageSpeedMBps`, and `TransferEndToEndAverageSpeedMBps`. `TransferAverageSpeedMBps` remains an alias for the end-to-end rate.

The default `Fast` pipeline uses the runtime's native file-copy path and avoids reading every destination file a second time. It validates that the staging file was completely written with the expected length and then atomically renames it to the reserved destination. `TransferCopiedBytes` records physical copy volume; `TransferVerifiedBytes` remains zero because `Fast` performs no content read-back.

Select `-TransferVerificationMode Full` when a second complete content pass is required. `Full` calculates the source hash inline during copy, independently reads and hashes staging, compares both hashes, and only then commits. This necessarily transfers substantially more data than Windows Explorer.

Copy and verification can overlap for files of any logical size. `MaxInFlightMB` now represents estimated active buffer residency rather than the complete sizes of admitted files, so a 38-GB file no longer blocks the next copy behind a 512-MB default budget. The adaptive copy limit remains bounded by the selected profile. Diagnostics include `TransferPeakCopyConcurrency`, `TransferPeakVerifyConcurrency`, `TransferPeakConcurrency`, `TransferConcurrencyAdjustments`, and `TransferPeakInFlightBytes`.

`-SourceDisposition Move` does not read or hash file contents: two same-volume metadata renames move the source through transaction staging to its final destination. Transactions report `TransferMethod=SameVolumeMove` and `VerificationMode=RenameIdentity`; physical copied and verified bytes remain zero. If final commit fails, RenderKit renames the staged file back to its original source path. Rollback outcomes are exposed through `TransferRolledBackFileCount`, `TransferRollbackFailedFileCount`, and each transaction's `RollbackStatus` and `RollbackError`.

Commands that perform writes can also change RenderKit configuration, templates, mappings, project files, or destination packages according to the selected parameters. Verify the operation using the returned paths and properties.

## Notes and safety

> [!IMPORTANT]
> Calling the command without parameters starts the wizard. Use automatic selection and confirmation only after verifying filters and destination paths.

> [!NOTE]
> The performance-oriented `Fast` default validates copy completion and file length but does not perform a second content read-back. Use `-TransferVerificationMode Full` when cryptographic source-to-staging verification is required.

> [!WARNING]
> `-SourceDisposition Move` removes successfully imported files from their source paths. It is rejected when source and destination are not on the same Windows volume; RenderKit never silently falls back to copy. If rollback itself fails, the staging directory is preserved and returned in `Transfer.TempRunRoot` for manual recovery.

## Related documentation

- [Installation and updates](installation.md)
- [Function overview](README.md)
- [Import-Media source code](../src/Public/Import-Media.ps1)
