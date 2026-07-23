# RenderKit

![GitHub Release](https://img.shields.io/github/v/release/djtroi/RenderKit?label=release)
![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/RenderKit?label=PowerShell%20Gallery)
![Downloads](https://img.shields.io/powershellgallery/dt/RenderKit)
[![Quality Gate](https://github.com/djtroi/RenderKit/actions/workflows/quality-gate.yml/badge.svg)](https://github.com/djtroi/RenderKit/actions/workflows/quality-gate.yml)

**RenderKit** is a free and open-source PowerShell toolkit for video editors, media creators, and small production teams who want repeatable project folders, safer media imports, simple delivery packages, and auditable backups.

Current repository version: **1.1.1**. RenderKit supports **Windows PowerShell 5.1** and **PowerShell 7+**.

RenderKit is currently the workflow/engine foundation for a future local-first MAM/DAM-style tool. Think of it as the practical workflow layer around your editing software: project setup, ingest discipline, transfer checks, packaging, and backup structure.

---

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
- 
## Why RenderKit exists

Video projects often become messy for boring reasons:

* every project folder looks slightly different;
* footage gets copied manually without verification;
* delivery folders are inconsistent;
* backups are hard to audit later;
* client/project handoffs are improvised every time;
* small teams need structure, but not another expensive platform.

RenderKit tries to solve that with a local, scriptable, transparent workflow toolkit.

The goal is simple:

> Make media-production project workflows repeatable, inspectable, and safe — without locking users into a paid platform.

---

## Who this is for

RenderKit is currently useful for:

* solo video editors;
* YouTubers and content creators with recurring project structures;
* small production teams;
* freelancers handling client projects;
* editors who like predictable folders and safe ingest workflows;
* technically comfortable users who do not mind using PowerShell.

RenderKit is probably **not** for you yet if you need:

* a polished desktop GUI today;
* thumbnail browsing;
* visual metadata panels;
* cloud team collaboration;
* NLE plugin integration;
* enterprise asset-management permissions;
* a full replacement for a professional MAM/DAM system.

Those areas may come later, but the current focus is the workflow foundation.

---

## What RenderKit can do

### Project setup

Create consistent project folders from reusable templates.

```powershell
Set-ProjectRoot -Path "D:\Editing_Projects"

New-Project -Name "ClientA_2026" -Template "youtube"
```

---

### Media import

Scan, filter, classify, and transfer source media into the right project folders.

```powershell
Import-Media
```

Or run it with explicit parameters:

```powershell
Import-Media `
  -ScanAndFilter `
  -SourcePath "E:\DCIM" `
  -FolderFilter "100EOSR" `
  -Wildcard "*.mp4","*.mov" `
  -Classify `
  -Transfer `
  -ProjectRoot "D:\Editing_Projects\ClientA_2026" `
  -TemplateName "youtube"
```

---

### Transfer safety

RenderKit can import media through transaction-style staging workflows instead of simply dragging files into a folder.

Depending on the selected mode and version, RenderKit can:

* copy into a temporary staging location;
* validate transfer completion;
* perform hash-based verification when required;
* commit the file into the final destination only after validation;
* preserve source files by default;
* expose transfer metrics for copy, verification, and end-to-end throughput.

This is designed for workflows where “I think I copied everything” is not good enough.

---

### Templates and media mappings

Define reusable project structures and map media types to folders.

```powershell
New-RenderKitTemplate -Name "client-delivery"

Add-FolderToTemplate `
  -TemplateName "client-delivery" `
  -FolderName "01_Footage"

New-RenderKitMapping -Name "camera-media"

Add-RenderKitTypeToMapping `
  -MappingName "camera-media" `
  -Extension ".mp4" `
  -TargetFolder "01_Footage"

Add-RenderKitMappingToTemplate `
  -TemplateName "client-delivery" `
  -MappingName "camera-media"
```

This makes it possible to reuse the same structure across projects instead of rebuilding folders by hand every time.

---

### Delivery packages

Prepare files for review, publishing, handoff, or archiving.

```powershell
Send-Project `
  -ProjectRoot "D:\Editing_Projects\ClientA_2026" `
  -DestinationPath "E:\Delivery\ClientA-review.zip" `
  -DeliveryRule "review" `
  -PackageMode Zip
```

RenderKit can help keep deliverables structured and repeatable instead of manually collecting files at the end of a project.

---

### Export and import projects

Export project metadata or create self-contained project packages.

```powershell
Export-Project `
  -ProjectRoot "D:\Editing_Projects\ClientA_2026" `
  -DestinationPath "E:\Transfer\ClientA_2026.rkit" `
  -Mode ManifestOnly
```

```powershell
Export-Project `
  -ProjectRoot "D:\Editing_Projects\ClientA_2026" `
  -DestinationPath "E:\Transfer\ClientA_2026.rkitpkg" `
  -Mode SelfContained
```

```powershell
Import-Project `
  -Path "E:\Transfer\ClientA_2026.rkitpkg" `
  -DestinationRoot "D:\Editing_Projects"
```

---

### Backups

Create project backups with structured manifests and integrity-oriented workflows.

```powershell
Backup-Project -ProjectName "ClientA_2026"
Backup-Project -ProjectName "ClientA_2026" -Preset DaVinci -DryRun
Backup-Project -ProjectName "ClientA_2026" -DestinationRoot "E:\Backups" -KeepSourceProject
```

### Read, write, and roll back metadata

```powershell
Get-Metadata -Path '.\footage\interview.wav' -IncludeMetadata
Add-Metadata -Path '.\footage\interview.wav' -Field Title -Value 'Interview A'
$change = Add-Metadata -Path '.\footage\interview.wav' -Field Creator -Value 'Camera Unit'
Rollback-Metadata -Path '.\footage\interview.wav' -Version ($change.MetadataVersion - 1)
```

Use `-XmpSidecar` when an XMP sidecar is required and `-NoEmbedded` when only
the RenderKit metadata store should change. See the [metadata workflow](docs/metadata.md).

### Clients and publishing schedules

```powershell
$client = New-RenderKitClient -DisplayName 'Example Studio' -Tag 'priority'
$publication = New-RenderKitPublication `
  -Title 'Launch trailer' `
  -StartUtc '2026-08-01T16:00:00+00:00' `
  -TimeZone 'Europe/Berlin' `
  -ClientId $client.id `
  -ClientNameSnapshot $client.displayName

Get-RenderKitPublication `
  -FromUtc '2026-08-01T00:00:00+00:00' `
  -ToUtc '2026-09-01T00:00:00+00:00'
```

### Template, mapping, and deliverable management

```powershell
Install-PSResource -Name RenderKit -Scope CurrentUser -Repository PSGallery
Import-Module RenderKit
```

## Core Features

- **Project lifecycle commands** for creating, copying, renaming, removing, importing, exporting, sending, and backing up projects.
- **Template and mapping tools** for reusable project folders, logical media types, and deliverable rules.
- **Interactive import wizard** with drive/source selection, filtering, classification, transfer mode selection, and unassigned-file handling.
- **Transfer safety** through hash verification and transaction-style media import workflows.
- **Export and delivery formats** including manifest-only `.rkit`, self-contained `.rkitpkg`, folder deliveries, ZIP deliveries, and manifest outputs.
- **Cross-platform user storage** for configuration, state, cache, and user data roots, including `RENDERKIT_HOME` overrides.
- **Media metadata workflows** for native-first inspection, embedded or XMP-sidecar writes, templates, import/export, cached reads, provenance, history, and rollback.
- **Client and publishing registries** with stable IDs, validation, status lifecycles, and optimistic concurrency.
- **Atomic JSON persistence** with locking, backup restoration, validation hooks, and transaction-style state updates.
- **Versioned internal artifacts** for project, registry, discovery, search-index, event, job, template, mapping, device, client, publishing, metadata, and configuration data.
- **Internal project registry, discovery, and lifecycle services** for indexed discovery, duplicate-ID conflict reporting, moved/missing project reconciliation, status transitions, and lifecycle events.
- **Domain events, durable jobs, automation, and worker primitives** for host integrations and asynchronous workflows.
- **Host-facing engine contracts** with stable result envelopes, registered error codes, operation contexts, and contract snapshots.

## Architecture

- [ADR-001: Project Identity and Local Registry](docs/architecture/ADR-001-project-identity-and-registry.md)
- [ADR-002: Project Lifecycle State Machine](docs/architecture/ADR-002-project-lifecycle.md)
- [ADR-003: Domain Events, Durable Jobs, and Automation](docs/architecture/ADR-003-domain-events-and-jobs.md)
- [ADR-004: Artifact and Business Versioning](docs/architecture/ADR-004-artifact-versioning.md)
- [ADR-005: Cross-Platform Storage and Path Handling](docs/architecture/ADR-005-cross-platform-storage.md)
- [ADR-006: Local Engine Security Baseline](docs/architecture/ADR-006-security-baseline.md)

## Documentation

Detailed usage documentation is available in [`docs/README.md`](docs/README.md). It includes:

- installation and update instructions for PSResourceGet and PowerShellGet;
- a guided first-run workflow;
- a complete [public-function reference](docs/public-functions.md), plus detailed pages for the main workflows;
- parameter, safety, output, and usage guidance for state-changing command families;
- technical documentation for metadata, clients, publishing, backup/jobs, storage, versioning, project lifecycle, events, workers, automation, repair checks, and engine contracts.

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
- [Metadata Workflow](docs/metadata.md)
- [Client Registry](docs/client-registry.md)
- [Publishing Schedule](docs/publishing.md)
- [Backup Operations and Jobs](docs/backup-operations.md)
- [All Public Functions](docs/public-functions.md)

## Public Functions

The [complete public-function reference](docs/public-functions.md) lists every
command exported by the 1.1.0 manifest. Detailed workflow documentation is
grouped by [projects](docs/project-lifecycle.md), [metadata](docs/metadata.md),
[clients](docs/client-registry.md), [publishing](docs/publishing.md), and
[backup/jobs](docs/backup-operations.md).

Check the commands exported by your installed module:

```powershell
Get-Command -Module RenderKit
Get-Help <FunctionName> -Full
Get-Help <FunctionName> -Examples
```

## IPTC metadata

RenderKit maps the IPTC Core 1.5 and IPTC Extension 1.9 properties represented
by its canonical metadata registry through the bundled ExifTool adapter. The
map is versioned at `src/Resources/Metadata/iptc-field-map.json` and follows
IPTC Photo Metadata Standard 2025.1.

Reads prefer the current XMP representation and use legacy IIM or EXIF tags as
explicit fallbacks. Multiple values remain arrays; RenderKit does not guess
list boundaries from commas or other punctuation. Image writes update the
compatible XMP and IIM/EXIF representations, and default-language XMP writes
preserve any other language alternatives.

Extension structures remain object lists. Scalar compatibility fields are only
projected when a single unambiguous value exists; otherwise the structured
value and a conflict are retained. Digital Source Type and PLUS release-status
values use explicit canonical-value-to-URI mappings.

```powershell
Add-Metadata -Path '.\photo.png' -Field Headline -Value 'Product launch'
Add-Metadata -Path '.\photo.png' -Field Keywords -Value @('press', 'launch')
Add-Metadata `
    -Path '.\photo.png' `
    -Field DigitalSourceType `
    -Value TrainedAlgorithmicMedia

Get-Metadata `
    -Path '.\photo.png' `
    -Field Headline, Keywords `
    -IncludeMetadata
```

Templates and batches use the same map. `Export-Metadata` includes an explicit
IPTC profile and `Import-Metadata` restores it without flattening repeated or
structured values.

## Dublin Core / XMP

RenderKit's Dublin Core application profile maps eight DCMES 1.1 elements to
semantically equivalent registry fields in the XMP `dc` namespace. The
remaining seven standard elements are recorded as explicitly unmapped instead
of being guessed from narrower internal, technical, or IPTC fields.

Repeated contributors, creators, and subjects remain arrays. The scalar
Language and Publisher registry fields use an explicit first-non-empty profile
constraint when an external XMP packet contains multiple values.

```powershell
Add-Metadata -Path '.\asset.png' -Field Contributor -Value @('Editor One', 'Editor Two')
Add-Metadata -Path '.\asset.png' -Field Publisher -Value 'RenderKit Press'
Add-Metadata -Path '.\asset.png' -Field Subject -Value @('architecture', 'design')
```

The wider XMP namespace, sidecar, broker/catalog, Studio, and production
workflow boundaries are tracked in
[`docs/dublin-core-xmp-integration-slices.md`](docs/dublin-core-xmp-integration-slices.md).

## BWF, iXML, ID3 and Matroska

RenderKit reads these four audio/container profiles through versioned,
declarative maps. BEXT and iXML values come from RIFF/WAVE, ID3 tags retain
their version-group precedence, and Matroska segment tags remain distinct from
audio/video track metadata. Structured track, picture, lyric, and chapter
values remain objects rather than flattened strings.

BWF and iXML writes use RenderKit's native RIFF/RF64 chunk writer. ID3 writes
use the bundled, hash-verified TagLibSharp runtime and write ID3v2.4.
Matroska writes use bundled `mkvpropedit`/`mkvextract` for preserved global
tags, first-of-type track headers, and canonical chapter trees. Each writer
works on an atomic same-directory copy and verifies semantic readback before
replacement. The remaining broker/Studio work is tracked in
[`docs/audio-container-metadata-integration-slices.md`](docs/audio-container-metadata-integration-slices.md).

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

TagLibSharp 2.3.0 provides ID3v2.4 frame reads and writes. MKVToolNix 99.0
provides Matroska tag, track-header, and chapter reads and writes. Their pinned
hashes and licenses are recorded below `src/Resources/ThirdParty/`; the
MKVToolNix corresponding source archive is included with the module. RenderKit
bundles the complete MKVToolNix runtime for Windows x64. Ubuntu and macOS use
the same fully tested adapter through a native system installation:

```bash
# Ubuntu
sudo apt-get update && sudo apt-get install --yes mkvtoolnix

# macOS with Homebrew
brew install mkvtoolnix
```

The resolver requires both `mkvpropedit` and `mkvextract`. Their locations can
also be supplied with `RENDERKIT_MKVTOOLNIX_ROOT`,
`RENDERKIT_MKVPROPEDIT_PATH`, and `RENDERKIT_MKVEXTRACT_PATH`.

## Maintainer Release Workflow

Some workflows are naturally more useful on Windows-based editing systems, but the module is designed with cross-platform storage and path handling in mind.

---

## Quick start

### 1. Install and import RenderKit

```powershell
Install-PSResource -Name RenderKit -Scope CurrentUser -Repository PSGallery
Import-Module RenderKit
```

### 2. Create or select your editing root

```powershell
New-Item -ItemType Directory -Path "D:\Editing_Projects" -Force
Set-ProjectRoot -Path "D:\Editing_Projects"
```

### 3. Create a project

```powershell
New-Project -Name "ClientA_2026" -Template "youtube"
```

### 4. Import media

```powershell
Import-Media
```

### 5. Back up the project

```powershell
Backup-Project -ProjectName "ClientA_2026"
```

---

## Common commands

Check all exported RenderKit commands:

```powershell
Get-Command -Module RenderKit
```

Open full help for a command:

```powershell
Get-Help Import-Media -Full
```

Show examples:

```powershell
Get-Help Import-Media -Examples
```

---

## Safety notes

RenderKit can create, copy, package, archive, and remove project data depending on the command and parameters you choose.

Before using RenderKit on real client work:

* test your workflow with sample folders;
* use `-WhatIf` or `-DryRun` where available;
* verify source and destination paths;
* keep an independent backup strategy;
* do not treat any tool as your only copy of important footage.

RenderKit is designed to make workflows safer and more repeatable, but you are still responsible for verifying your production storage and backup process.

---

## Current status

RenderKit is usable, but still evolving.

The current focus is:

* project lifecycle workflows;
* media import and transfer safety;
* reusable templates and mappings;
* package/export/import workflows;
* backup manifests and auditability;
* local state foundations for future GUI or host integrations.

Planned or future areas may include:

* a user-friendly desktop interface;
* richer metadata workflows;
* preview and thumbnail workflows;
* deeper media catalog features;
* NLE integration;
* proxy/transcode workflows;
* team-oriented collaboration features.

---

## Feedback wanted

RenderKit is being built to solve real media-production workflow problems.

If you are a video editor, content creator, post-production technician, or media manager, feedback is very welcome.

Useful feedback includes:

* How do you structure your editing projects?
* What always goes wrong during media ingest?
* What would you want verified during file transfer?
* How do you package review files or final deliveries?
* What metadata would actually help you?
* What would make this useful for a small production team?
* What would you expect from a lightweight MAM/DAM-style tool?

You can share feedback by opening a GitHub issue or starting a discussion around your workflow pain points.

---

## License

RenderKit is released under the MIT License.

Near-term work is tracked in the changelog and repository issues. Current foundations include storage, persistence, artifact versioning, registry/lifecycle state, metadata, clients, publishing schedules, domain events, durable jobs, automation, workers, repair checks, and engine contracts. Future README updates can replace the tutorial placeholders above with GIF walkthroughs and expand host/Electron handoff examples as those integrations mature.
