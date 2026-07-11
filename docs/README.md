# RenderKit Documentation

This documentation covers installation, updates, and every public RenderKit
function. The [complete command reference](public-functions.md) covers the full
exported surface; high-impact workflows also have focused guides with examples,
state semantics, and safety notes.

## Getting started

1. [Install or update RenderKit](installation.md)
2. Configure a project root: [`Set-ProjectRoot`](Set-ProjectRoot.md)
3. Create a project: [`New-Project`](New-Project.md)
4. Import media: [`Import-Media`](Import-Media.md)
5. Back up or deliver a project: [`Backup-Project`](Backup-Project.md), [`Send-Project`](Send-Project.md)

RenderKit user storage follows platform conventions. See
[Cross-Platform User Storage](storage.md) for Windows, Linux, macOS, XDG, and
portable/test override locations.

Technical schema compatibility is governed by the
[Artifact Versioning](artifact-versioning.md) foundation.
Internal project-name resolution is backed by the
[Project Registry](project-registry.md). Fast project overview reads and refresh
scans are documented in [Project Discovery and Search Index](project-discovery.md).
[Project Lifecycle](project-lifecycle.md).
Internal automation signals are documented in [Domain Events](events.md).
Asynchronous work is backed by [Background Jobs](jobs.md).
Event-to-job wiring is documented in [Event-to-Job Automation](automation.md).
Trusted worker execution is documented in [Job Workers](job-workers.md).
Host-facing engine contracts are documented in [Engine Contracts](engine-contracts.md).
Internal health checks are documented in [Repair and Health Checks](repair.md).

## Project management

- [`Set-ProjectRoot`](Set-ProjectRoot.md) – Configure the default project root
- [`New-Project`](New-Project.md) – Create a project from a template
- [`Get-Project`](Get-Project.md) – List projects known to RenderKit
- [`Copy-Project`](Copy-Project.md) – Copy a project with a new identity
- [`Rename-Project`](Rename-Project.md) – Rename a project while preserving its ID
- [`Remove-Project`](Remove-Project.md) – Remove a project
- [`Export-Project`](Export-Project.md) – Create a project manifest or self-contained package
- [`Import-Project`](Import-Project.md) – Import a project manifest or package
- [`Send-Project`](Send-Project.md) – Package deliverables for handoff or review
- [`Backup-Project`](Backup-Project.md) – Clean, archive, and verify a project

## Templates and mappings

- [`New-RenderKitTemplate`](New-RenderKitTemplate.md)
- [`Add-FolderToTemplate`](Add-FolderToTemplate.md)
- [`Add-RenderKitMappingToTemplate`](Add-RenderKitMappingToTemplate.md)
- [`Add-RenderKitDeliverableToTemplate`](Add-RenderKitDeliverableToTemplate.md)
- [`New-RenderKitMapping`](New-RenderKitMapping.md)
- [`Add-RenderKitTypeToMapping`](Add-RenderKitTypeToMapping.md)

## Media import and drive detection

- [`Import-Media`](Import-Media.md)
- [`Get-RenderKitDriveCandidate`](Get-RenderKitDriveCandidate.md)
- [`Select-RenderKitDriveCandidate`](Select-RenderKitDriveCandidate.md)
- [`Get-RenderKitDeviceWhitelist`](Get-RenderKitDeviceWhitelist.md)
- [`Add-RenderKitDeviceWhitelistEntry`](Add-RenderKitDeviceWhitelistEntry.md)

## Metadata

- [Metadata workflow and commands](metadata.md)
- [Dublin Core / XMP integration](dublin-core-xmp-integration-slices.md)
- [BWF, iXML, ID3, and Matroska integration](audio-container-metadata-integration-slices.md)

## Clients and publishing

- [Client registry](client-registry.md)
- [Publishing schedule](publishing.md)

## Backup and background work

- [Backup operations and job control](backup-operations.md)
- [Background jobs](jobs.md)
- [Job workers](job-workers.md)

## Complete command surface

- [All 61 exported functions](public-functions.md)

## PowerShell help

```powershell
Get-Command -Module RenderKit
Get-Help <FunctionName> -Full
Get-Help <FunctionName> -Examples
```
