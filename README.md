# RenderKit

![GitHub Release](https://img.shields.io/github/v/release/djtroi/RenderKit?label=release)
![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/RenderKit?label=PowerShell%20Gallery)
![Downloads](https://img.shields.io/powershellgallery/dt/RenderKit)
[![CI/CD Pipeline](https://github.com/djtroi/RenderKit/actions/workflows/quality-gate.yml/badge.svg)](https://github.com/djtroi/RenderKit/actions/workflows/quality-gate.yml)

**RenderKit** is a PowerShell toolkit for repeatable media-production project workflows: create project structures, manage templates and mappings, import camera media, verify transfers, package deliverables, export/import projects, and keep local workflow state auditable.

Current repository version: **1.0.0**. RenderKit supports **Windows PowerShell 5.1** and **PowerShell 7+**.

## Table of Contents

- [What is RenderKit?](#what-is-renderkit)
- [Quickstart](#quickstart)
- [Why RenderKit Exists](#why-renderkit-exists)
- [Common Workflows](#common-workflows)
- [Core Features](#core-features)
- [Architecture](#architecture)
- [Documentation](#documentation)
- [Public Functions](#public-functions)
- [Third-Party Components](#third-party-components)
- [Maintainer Release Workflow](#maintainer-release-workflow)
- [Roadmap](#roadmap)

## What is RenderKit?

RenderKit helps editors and media teams standardize the repetitive parts of a production pipeline. Instead of manually creating folders, remembering naming conventions, sorting camera files, building delivery packages, and creating backup archives by hand, RenderKit gives you composable commands for the full lifecycle of a project.

Use it to:

- define reusable project templates, folder structures, deliverables, and media mappings;
- create consistent editing project folders with metadata;
- detect media drives and pick source folders interactively;
- scan, filter, classify, and transfer media into the right destinations;
- copy, rename, remove, import, export, and send projects;
- back up projects with manifests, integrity checks, and archive workflows;
- keep local RenderKit state in platform-appropriate user storage with versioned artifacts;
- list discovered projects quickly and refresh the overview from indexed search roots when needed. 

## Quickstart

### 1. Install RenderKit

Recommended installer for current PowerShell environments:

```powershell
Install-PSResource -Name RenderKit -Scope CurrentUser -Repository PSGallery
Import-Module RenderKit
```

Compatibility-tested legacy installer:

```powershell
Install-Module -Name RenderKit -Scope CurrentUser -Repository PSGallery
Import-Module RenderKit
```

If `Install-PSResource` is not available yet, install PSResourceGet first:

```powershell
Install-Module -Name Microsoft.PowerShell.PSResourceGet -Scope CurrentUser
```

See [installation and update instructions](docs/installation.md) for local checkout installs, updates, verification commands, and troubleshooting.

### 2. Create your project root

```powershell
New-Item -ItemType Directory -Path "D:\Editing_Projects" -Force
Set-ProjectRoot -Path "D:\Editing_Projects"
```

### 3. Create a project from a template

```powershell
New-Project -Name "ClientA_2026" -Template "youtube"
```

### 4. Import media interactively

```powershell
Import-Media
```

### 5. Import media with parameters

```powershell
Import-Media `
  -ScanAndFilter `
  -SourcePath "E:\DCIM" `
  -FolderFilter "100EOSR" `
  -Wildcard "*.mp4","*.mov" `
  -Classify `
  -Transfer `
  -ProjectRoot "D:\Editing_Projects\ClientA_2026" `
  -TemplateName "youtube" `
  -TransferHashAlgorithm SHA256
```

### Tutorial placeholders

GIF walkthroughs are planned for future README updates:

| Tutorial | Preview |
| --- | --- |
| Install and first project | _GIF coming soon: `docs/assets/tutorial-install.gif`_ |
| Interactive media import | _GIF coming soon: `docs/assets/tutorial-import.gif`_ |
| Backup and archive workflow | _GIF coming soon: `docs/assets/tutorial-backup.gif`_ |

> [!WARNING]
> RenderKit can copy, archive, package, and optionally remove project data depending on the command and parameters you choose. Test new workflows with `-WhatIf` or `-DryRun` where available and verify your source, destination, and project-root paths before running production operations.

## Why RenderKit Exists

Video projects tend to fail in quiet, boring ways: inconsistent folder names, forgotten camera cards, copied files without hashes, missing delivery folders, unclear package contents, and archives that cannot be audited later. RenderKit exists to make those operational details explicit, repeatable, and scriptable.

The goal is not to replace your editor, NLE, DAM, or backup strategy. RenderKit focuses on the glue around them: the project scaffolding, import discipline, transfer safety, delivery packaging, local state, and metadata that make handoffs and long-term storage easier.

## Common Workflows

### Interactive import workflow

Run a scan → filter → selection → classification → transfer pipeline from one command:

_GIF coming soon: `docs/assets/tutorial-import.gif`_

```powershell
Import-Media
```

### Drive detection and whitelisting

```powershell
Get-RenderKitDriveCandidate
Select-RenderKitDriveCandidate -IncludeFixed
Add-RenderKitDeviceWhitelistEntry -FromMountedVolumes
Get-RenderKitDeviceWhitelist
```

### Project lifecycle operations

```powershell
Rename-Project -ProjectName "ClientA_2026" -NewName "ClientA_Final_2026" -WhatIf
Copy-Project -ProjectName "ClientA_Final_2026" -NewName "ClientA_Copy_2026" -DryRun
Remove-Project -ProjectName "ClientA_Copy_2026" -DryRun
```

### Export, import, and delivery packaging

```powershell
Export-Project -ProjectRoot "D:\Editing_Projects\ClientA_2026" -DestinationPath "E:\Transfer\ClientA_2026.rkit" -Mode ManifestOnly
Export-Project -ProjectRoot "D:\Editing_Projects\ClientA_2026" -DestinationPath "E:\Transfer\ClientA_2026.rkitpkg" -Mode SelfContained
Import-Project -Path "E:\Transfer\ClientA_2026.rkitpkg" -DestinationRoot "D:\Editing_Projects"
Send-Project -ProjectRoot "D:\Editing_Projects\ClientA_2026" -DestinationPath "E:\Delivery\ClientA-review.zip" -DeliveryRule "review" -PackageMode Zip
```

### Production-ready backup pipeline

```powershell
Backup-Project -ProjectName "ClientA_2026"
Backup-Project -ProjectName "ClientA_2026" -Profile DaVinci -DryRun
Backup-Project -ProjectName "ClientA_2026" -DestinationRoot "E:\Backups" -KeepSourceProject
```

### Template, mapping, and deliverable management

```powershell
New-RenderKitTemplate -Name "client-delivery"
Add-FolderToTemplate -TemplateName "client-delivery" -FolderName "01_Footage"
New-RenderKitMapping -Name "camera-media"
Add-RenderKitTypeToMapping -MappingName "camera-media" -Extension ".mp4" -TargetFolder "01_Footage"
Add-RenderKitMappingToTemplate -TemplateName "client-delivery" -MappingName "camera-media"
Add-RenderKitDeliverableToTemplate -TemplateName "client-delivery" -Id "review" -Name "Review Files" -SourceFolder "03_Deliverables" -Recursive -DefaultPackage
```

## Core Features

- **Project lifecycle commands** for creating, copying, renaming, removing, importing, exporting, sending, and backing up projects.
- **Template and mapping tools** for reusable project folders, logical media types, and deliverable rules.
- **Interactive import wizard** with drive/source selection, filtering, classification, transfer mode selection, and unassigned-file handling.
- **Transfer safety** through hash verification and transaction-style media import workflows.
- **Export and delivery formats** including manifest-only `.rkit`, self-contained `.rkitpkg`, folder deliveries, ZIP deliveries, and manifest outputs.
- **Cross-platform user storage** for configuration, state, cache, and user data roots, including `RENDERKIT_HOME` overrides.
- **Media metadata foundations** for cached file metadata, template application, versioned rollback, and MediaInfo-based inspection.
- **Atomic JSON persistence** with locking, backup restoration, validation hooks, and transaction-style state updates.
- **Versioned internal artifacts** for project, registry, discovery, search-index, event, job, template, mapping, device, and configratuion data.
- **Internal project registry, discovery, and lifecycle services** for known project tracking, indexed project discovery, duplicate-id conflict preparation, moved/missing project reconciliation, status transitions, and lifecycle events. 
- **Versioned internal artifacts** for project, registry, event, job, template, mapping, device, and configuration data.
- **Internal project registry and lifecycle services** for known project tracking, moved/missing project reconciliation, status transitions, and lifecycle events.
- **Domain events, durable jobs, automation, and worker primitives** for future host integrations and asynchronous workflows.
- **Host-facing engine contracts** with stable result envelopes, registered error codes, operation contexts, and contract snapshots.

## Architecture

- [ADR-001: Project Identity and Local Registry](docs/architecture/ADR-001-project-identity-and-registry.md)
- [ADR-002: Project Lifecycle State Machine](docs/architecture/ADR-002-project-lifecycle.md)
- [ADR-003: Domain Events, Durable Jobs, and Automation](docs/architecture/ADR-003-domain-events-and-jobs.md)
- [ADR-004: Artifact and Business Versioning](docs/architecture/ADR-004-artifact-versioning.md)
- [ADR-005: Cross-Platform Storage and Path Handling](docs/architecture/ADR-005-cross-platform-storage.md)
- [ADR-006: Local Engine Security Baseline](docs/architecture/ADR-006-security-baseline.md)
- [Architecture implementation plan](docs/architecture/phase-implementation-plan.md)

## Documentation

Detailed usage documentation is available in [`docs/README.md`](docs/README.md). It includes:

- installation and update instructions for PSResourceGet and PowerShellGet;
- a guided first-run workflow;
- one consistently structured Markdown reference page per implemented public function;
- parameter, safety, output, and usage guidance for every documented command;
- technical documentation for storage, artifact versioning, project registry, project discovery, project lifecycle, events, jobs, workers, automation, repair checks, and engine contracts.

Key technical documents:

- [Cross-Platform User Storage](docs/storage.md)
- [Artifact Versioning](docs/artifact-versioning.md)
- [Project Registry](docs/project-registry.md)
- [Project Lifecycle](docs/project-lifecycle.md)
- [Domain Events](docs/events.md)
- [Background Jobs](docs/jobs.md)
- [Event-to-Job Automation](docs/automation.md)
- [Job Workers](docs/job-workers.md)
- [Engine Contracts](docs/engine-contracts.md)
- [Repair and Health Checks](docs/repair.md)

## Public Functions

### Project lifecycle

- [`Set-ProjectRoot`](docs/Set-ProjectRoot.md)
- [`New-Project`](docs/New-Project.md)
- [`Get-Project`](docs/Get-Project.md)
- [`Copy-Project`](docs/Copy-Project.md)
- [`Rename-Project`](docs/Rename-Project.md)
- [`Remove-Project`](docs/Remove-Project.md)
- [`Import-Project`](docs/Import-Project.md)
- [`Export-Project`](docs/Export-Project.md)
- [`Send-Project`](docs/Send-Project.md)

### Template and mapping setup

- [`New-RenderKitTemplate`](docs/New-RenderKitTemplate.md)
- [`Add-FolderToTemplate`](docs/Add-FolderToTemplate.md)
- [`Add-RenderKitDeliverableToTemplate`](docs/Add-RenderKitDeliverableToTemplate.md)
- [`New-RenderKitMapping`](docs/New-RenderKitMapping.md)
- [`Add-RenderKitTypeToMapping`](docs/Add-RenderKitTypeToMapping.md)
- [`Add-RenderKitMappingToTemplate`](docs/Add-RenderKitMappingToTemplate.md)

### Import and source detection

- [`Import-Media`](docs/Import-Media.md)
- [`Get-RenderKitDriveCandidate`](docs/Get-RenderKitDriveCandidate.md)
- [`Select-RenderKitDriveCandidate`](docs/Select-RenderKitDriveCandidate.md)
- [`Get-RenderKitDeviceWhitelist`](docs/Get-RenderKitDeviceWhitelist.md)
- [`Add-RenderKitDeviceWhitelistEntry`](docs/Add-RenderKitDeviceWhitelistEntry.md)

### Backup

- [`Backup-Project`](docs/Backup-Project.md)

Check the commands exported by your installed module:

```powershell
Get-Command -Module RenderKit
Get-Help <FunctionName> -Full
Get-Help <FunctionName> -Examples
```

## Third-Party Components

RenderKit metadata extraction uses MediaInfo / MediaInfoLib for media file
inspection. RenderKit distributions that bundle MediaInfo binaries include the
required MediaArea attribution and BSD-style license notice in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

Bundled MediaInfo assets are staged below
`src/Resources/ThirdParty/MediaInfo/<runtime-id>/` so RenderKit can resolve a
known binary before falling back. MediaInfoLib 26.01 is bundled natively for
Windows x64/ARM64, macOS x64/ARM64, and Linux x64. Linux ARM64 deliberately
uses external native, host, or CLI resolution because no distribution-neutral
26.01 binary is available. Native load/read failures continue through the
configured host and CLI candidates instead of disabling metadata extraction.

Resolver overrides:

- `RENDERKIT_MEDIAINFO_LIBRARY`: absolute path to a native MediaInfo library.
- `RENDERKIT_MEDIAINFO_HOST`: absolute path to an isolated metadata host.
- `RENDERKIT_MEDIAINFO_PATH`: absolute path to a MediaInfo CLI executable.

Bundled asset provenance and SHA-256 hashes are recorded in
`src/Resources/ThirdParty/MediaInfo/manifest.json`. Maintainers can reproduce
the verified binary drop with
`pwsh ./build/Sync-RenderKitMediaInfoAssets.ps1`.

MediaInfo is developed by MediaArea.net SARL. See
<https://mediaarea.net/MediaInfo> and
<https://mediaarea.net/en/MediaInfo/License>.

RenderKit also bundles ExifTool 13.59 for metadata reads and embedded metadata
writes. Windows x86/x64 use the official self-contained executable packages;
macOS and Linux use the official portable Perl distribution. ExifTool does
not expose a native shared-library integration comparable to MediaInfoLib, so
its supported application/CLI interface is the primary backend.

ExifTool resolver overrides:

- `RENDERKIT_EXIFTOOL_PATH`: ExifTool-compatible executable to prefer.
- `RENDERKIT_EXIFTOOL_HOST`: metadata host implementing
  `<host> exiftool run -- <arguments>`.
- `RENDERKIT_EXIFTOOL_PERL`: Perl interpreter for the bundled portable
  macOS/Linux program.

The normal order is explicit CLI, bundled ExifTool, configured host, then
`exiftool` on `PATH`. Windows ARM64 uses host/system fallback because upstream
does not publish a native ARM64 executable for this release. Provenance and
hashes are recorded under `src/Resources/ThirdParty/ExifTool/`; maintainers can
reproduce the verified payload with
`pwsh ./build/Sync-RenderKitExifToolAssets.ps1`.

ExifTool is developed by Phil Harvey and distributed under the same terms as
Perl. See <https://exiftool.org/>.

## Maintainer Release Workflow

Run the test/build helper used by the repository:

```powershell
pwsh ./build/Invoke-RenderKitTests.ps1
```

Build a clean release artifact:

```powershell
pwsh ./build/Build-RenderKitPackage.ps1
```

Validate a package or local install before publication:

```powershell
pwsh ./build/Test-RenderKitPackage.ps1
pwsh ./build/Test-RenderKitLocalInstall.ps1
```

Publish the staged module to PowerShell Gallery:

```powershell
pwsh ./build/Publish-RenderKit.ps1 -Repository PSGallery -ApiKey '<APIKEY>'
```

Post-publication smoke tests can be run with:

```powershell
pwsh ./build/Test-RenderKitGalleryInstall.ps1 -Version '<VERSION>'
```

> [!NOTE]
> The release workflow publishes the validated staged module through `Publish-PSResource -Path`; the PowerShell Gallery creates the served package.

## Roadmap

Near-term work is tracked through the architecture implementation plan and changelog. Current foundations include storage, persistence, artifact versioning, registry/lifecycle state, domain events, durable jobs, automation, workers, repair checks, and engine contracts. Future README updates can replace the tutorial placeholders above with GIF walkthroughs and expand host/Electron handoff examples as those integrations mature.
