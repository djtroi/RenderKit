# Public function reference

This page lists all 67 functions exported by the RenderKit 1.2.0 manifest.
Use `Get-Command <name> -Syntax` for the exact installed syntax and
`Get-Help <name> -Full` for parameter metadata.

## Projects and delivery

| Function | Purpose |
| --- | --- |
| `Set-ProjectRoot` | Configure the default project root. |
| `New-Project` | Create a project from a RenderKit template. |
| `Get-Project` | Read discovered projects and optionally refresh discovery. |
| `Copy-Project` | Copy a project and assign the copy a new identity. |
| `Rename-Project` | Rename a project while preserving its identity. |
| `Remove-Project` | Remove a project through the guarded lifecycle workflow. |
| `Export-Project` | Export a manifest-only or self-contained project package. |
| `Import-Project` | Import a RenderKit manifest or package. |
| `Send-Project` | Build a folder, ZIP, or manifest deliverable. |

## Templates, mappings, media import, and devices

| Function | Purpose |
| --- | --- |
| `New-RenderKitTemplate` | Create a project template. |
| `Import-RenderKitTemplate` | Import a complete template with explicit conflict handling. |
| `Export-RenderKitTemplate` | Export a system or user template document. |
| `Test-RenderKitTemplate` | Validate a stored template and its artifact version. |
| `Add-FolderToTemplate` | Add a folder node to a template. |
| `Add-RenderKitDeliverableToTemplate` | Add or update a deliverable rule. |
| `New-RenderKitMapping` | Create a media mapping. |
| `Import-RenderKitMapping` | Import a complete mapping with explicit conflict handling. |
| `Export-RenderKitMapping` | Export a system or user mapping document. |
| `Test-RenderKitMapping` | Validate a stored mapping and its artifact version. |
| `Add-RenderKitTypeToMapping` | Add a logical media type and extensions to a mapping. |
| `Add-RenderKitMappingToTemplate` | Attach a mapping to a template. |
| `Import-Media` | Scan, filter, classify, and transfer source media. |
| `Get-RenderKitDriveCandidate` | Enumerate candidate source volumes. |
| `Select-RenderKitDriveCandidate` | Select a source volume interactively. |
| `Get-RenderKitDeviceWhitelist` | Read trusted device identities. |
| `Add-RenderKitDeviceWhitelistEntry` | Add trusted volume/device entries. |

## Metadata

| Function | Purpose |
| --- | --- |
| `Get-RenderKitMetadataFieldRegistry` | Query canonical field definitions. |
| `Test-RenderKitMetadataFieldValue` | Validate a value against a field definition. |
| `Get-Metadata` | Read effective, raw, cached, and provenance metadata. |
| `Add-Metadata` | Create a versioned metadata change for one field. |
| `Update-MetadataCache` | Refresh metadata for a project. |
| `Rollback-Metadata` | Restore an earlier file version or reverse a batch. |
| `Export-Metadata` | Export project/file metadata and optional history. |
| `Import-Metadata` | Apply an exported metadata document with conflict handling. |
| `New-MetadataTemplate` | Create a reusable metadata template. |
| `Get-MetadataTemplate` | Read metadata templates and optional fields. |
| `Add-MetadataTemplateField` | Add a field to a metadata template. |
| `Set-MetadataTemplateField` | Replace a field value in a metadata template. |
| `Add-MetadataTemplate` | Apply a metadata template to files or a project. |

See the [metadata workflow](metadata.md) for state and adapter semantics.

## Clients and publishing

| Function | Purpose |
| --- | --- |
| `Get-RenderKitClient` | List/search clients or read private detail by ID. |
| `New-RenderKitClient` | Create a validated client record. |
| `Set-RenderKitClient` | Update/archive a client with optimistic concurrency. |
| `Get-RenderKitPublication` | Read a publication or query an overlapping time range. |
| `New-RenderKitPublication` | Create a publishing schedule record. |
| `Set-RenderKitPublication` | Update a publication with lifecycle validation and optimistic concurrency. |

## Backup profiles, adapters, and operations

| Function | Purpose |
| --- | --- |
| `Backup-Project` | Plan, run, or enqueue a project backup. |
| `Get-BackupJob` | Read or watch BackupProject jobs. |
| `Pause-BackupJob` | Pause an active backup job. |
| `Resume-BackupJob` | Resume a paused backup job. |
| `Stop-BackupJob` | Request backup cancellation. |
| `Resume-BackupProjectJob` | Resume a BackupProject engine job. |
| `Suspend-BackupProjectJob` | Suspend a BackupProject engine job. |
| `Stop-BackupProjectJob` | Stop a BackupProject engine job. |
| `Get-BackupConfigProfile` | Read built-in or user backup profiles. |
| `New-BackupConfigProfile` | Create a user backup profile. |
| `Set-BackupConfigProfile` | Update a profile with generation checks. |
| `Update-BackupConfigProfile` | Upgrade stored profiles to the current schema. |
| `Remove-BackupConfigProfile` | Remove user backup profiles. |
| `Test-BackupConfigProfile` | Validate stored, imported, or draft profile data. |
| `Export-BackupConfigProfile` | Export a user profile. |
| `Import-BackupConfigProfile` | Import a profile with explicit conflict behavior. |
| `Get-BackupAdapter` | Query registered backup adapters. |
| `Register-BackupAdapter` | Register a trusted adapter implementation. |
| `Remove-BackupAdapter` | Remove registered adapters. |

## Generic jobs and workers

| Function | Purpose |
| --- | --- |
| `Get-RenderKitJobStatus` | Query durable jobs and optional log tails. |
| `Start-RenderKitJobWorker` | Run a foreground, one-shot, or detached worker. |
| `Get-RenderKitJobWorkerStatus` | Inspect worker state and optional logs. |

