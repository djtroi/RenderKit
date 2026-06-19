# Changelog

## 1.0.0 - 2026-06-19

### Major

### Added
- Added architecture documentation for project identity and registry, project lifecycle, domain events and jobs, artifact versioning, cross-platform storage, security baseline, and the phased implementation plan.
- Added cross-platform user storage support and documentation for configuration, state, cache, and user data roots, including `RENDERKIT_HOME` overrides and legacy data preservation guidance.
- Added atomic JSON persistence helpers with file locking, backup restoration support, validation hooks, and transaction-style updates for RenderKit state files.
- Added a central artifact versioning catalog and compatibility service for project, registry, event, job, template, mapping, device, and configuration artifacts.
- Added internal project registry and lifecycle services for tracking known projects, reconciling moved/missing project folders, validating lifecycle status transitions, and emitting lifecycle events.
- Added internal domain-event storage, event-to-job automation subscriptions, durable job storage, job worker registration, and repair/health checks for RenderKit state.
- Added host-facing engine contracts with actor and operation contexts, correlation/causation id handling, stable `RenderKitResult` envelopes, registered error codes, and a machine-readable engine contract snapshot for broker/Electron handoff.
- Added engine facade operations for engine info/state, project read models, job creation/list/detail/cancellation/retry/progress/success/failure, event list/detail, event bridge invocation, job handler catalog, and worker tick orchestration.
- Added JobStore v1.1 worker primitives for queue names, priority, actor context, ownership, leases, heartbeats, stale-running-job recovery, retries, structured progress, structured errors, and terminal results.
- Added EventStore v1.1 fields for event id aliases, event schema version, category, retention, actor context, data/payload compatibility, processing attempts, structured last errors, and reserved integrity metadata.
- Added safe job handler metadata catalogs with handler ids, versions, descriptions, payload schema versions, capabilities, idempotency, progress support, and cancellation support without exposing executable scriptblocks.
- Added Pester coverage for storage, persistence, artifact versioning, project registry/lifecycle, repair, domain events, event-to-job automation, durable jobs, worker leases/heartbeat, handler catalog metadata, and engine facade contracts.

### Changed
- Changed JSON-reading and JSON-writing paths across storage, backup, device, mapping, template, project, export, and delivery services to use the new persistence helpers where appropriate.
- Changed bundled artifact compatibility metadata so EventStore and JobStore now use current schema version `1.1` while retaining compatibility with readable `1.0` stores.
- Changed project commands and import/export flows to update project registry entries and lifecycle state consistently through internal services.
- Changed event and job documentation to describe the vNext envelopes, worker semantics, bridge behavior, and host-facing engine contracts.
- Changed docs index pages to include storage, artifact versioning, project registry, project lifecycle, events, jobs, workers, automation, repair, and engine contracts.

### Fixed
- Fixed resilience of JSON state updates by introducing atomic write, lock, backup, and validation behavior for internal state files.
- Fixed host-facing project detail lookups so project registry read failures return stable `RK_STORAGE_UNAVAILABLE` result envelopes instead of leaking raw exceptions.
- Fixed PowerShell automatic-variable sensitivity in the engine project detail lookup by avoiding `$Matches`/`$matches` naming in new facade code.


## 0.3.9 - 2026-06-18

### Patch 

---


### Changed
- Documented PSResourceGet as the recommended installer and PowerShellGet as a compatibility-tested legacy path without treating a package-manager upgrade as a fix for server hash mismatches.
- Clarified that Windows PowerShell 5.1 remains a supported RenderKit runtime and that package hash or archive failures occur before the module runtime is loaded.
- Expanded installation troubleshooting with a Windows PowerShell 5.1 package-manager bootstrap and separate guidance for Gallery hash mismatches and their secondary Central Directory extraction errors.
- Changed PSGallery publishing to use `Publish-PSResource -Path` on the validated staged module so the official publisher creates the Gallery package instead of uploading the separately generated `dotnet pack` artifact.

### Fixed
- Fixed release builds after removal of the optional RenderKit logo asset by omitting icon metadata and package files when the image is not present.
- Improved `dotnet pack` failure reporting by preserving the native exit code, printing normal-verbosity output, including the generated nuspec in the exception, and uploading staging diagnostics from CI.

## 0.3.8 - 2026-06-16

### Patch 

---

### Added

- Added project lifecycle commands for removing, renaming, duplicating, importing, exporting, and sending RenderKit projects.
- Added `.rkit` manifest-only and `.rkitpkg` self-contained project export/import workflows with archive manifests, resource handling, conflict modes, optional hash verification, and safe relative-path validation.
- Added deliverable definitions to templates and a `Send-Project` workflow for preparing review or delivery packages as folders, ZIP files, or manifest-only outputs.
- Added `Add-RenderKitDeliverableToTemplate` for adding or updating reusable deliverable rules in user templates.
- Added project export and delivery services for manifest generation, archive creation, checksums, package metadata, and deliverable file selection.
- Added default deliverable presets for exports, review, and publish outputs in the bundled templates.
- Added docs Folder with detailed documentation for the public Cmdlets
- Added package validation that opens every generated `.nupkg`, reads every compressed entry, extracts the package, validates the manifest, imports the packaged module, verifies its exported functions, and records package hash and size information.
- Added pre-publication CI installation tests for PSResourceGet on PowerShell 7 and PowerShellGet 2.2.5 on Windows PowerShell 5.1.
- Added post-publication PSGallery smoke tests that download and validate the served archive, record its SHA-256 hash, retry Gallery discovery, and install the exact released version through both tested package-manager paths.

### Changed

- Updated bundled templates and mappings to schema version `1.1` so they can carry deliverable metadata consistently.
- Expanded the exported public command surface in the module manifest and module loader to include the new project lifecycle, import/export, deliverable, and sending commands.
- Improved project metadata handling so project operations can preserve identity where appropriate and create new metadata for duplicated/imported projects.
- Updated release automation to use current GitHub Actions references, ensure PSResourceGet and PSGallery are available before publishing, and prepare the local PSResourceGet store directory in CI.
- Modernized the README with badges, table of contents, quickstart, tutorial placeholders, GitHub-style callouts, architecture overview, and refreshed command examples.
- Updated release metadata and documentation references for version `0.3.8`.
- Updated README.md
- Documented PSResourceGet as the recommended installer and PowerShellGet as a compatibility-tested legacy path without treating a package-manager upgrade as a fix for server hash mismatches.
- Clarified that Windows PowerShell 5.1 remains a supported RenderKit runtime and that package hash or archive failures occur before the module runtime is loaded.
- Expanded installation troubleshooting with a Windows PowerShell 5.1 package-manager bootstrap and separate guidance for Gallery hash mismatches and their secondary Central Directory extraction errors.
- Changed PSGallery publishing to use `Publish-PSResource -Path` on the validated staged module so the official publisher creates the Gallery package instead of uploading the separately generated `dotnet pack` artifact.

### Fixed

- Fixed exported documentation coverage by listing the newly merged project lifecycle and delivery commands.
- Fixed release publishing robustness by registering PSGallery idempotently before `Publish-PSResource` runs.


## 0.3.7 - 2026-04-21

### Patch

--- 

### Added

- Added a reusable interactive import menu service in `RenderKit.ImportInteractiveMenuService.ps1` with keyboard navigation, paging, multi-select support, hotkeys, and context-aware menu screens

### Changed

- Changed `Import-Media` wizard mode to a menu-driven setup flow for project selection, source browsing, direct subfolder filtering, file selection, confirmation, transfer mode, and unassigned-file handling
- Changed `Select-RenderKitDriveCandidate` to use the same interactive menu service for a more consistent source-selection workflow

### Fixed

- Fixed wizard configuration binding so classification now reads `wizardConfig.Classify` correctly
- Fixed wizard transfer prompting so the transfer mode menu only appears when transfer was enabled during setup



## 0.3.6 - 2026-04-xx

### Patch

--- 

### Added

### Changed

### Fixed

- Fixes [#6](https://github.com/djtroi/RenderKit/issues/6) 
- Fixes [#7](https://github.com/djtroi/RenderKit/issues/7) - "return" in `New-RenderKitMapping` was missing
- Fixes [#8](https://github.com/djtroi/RenderKit/issues/8) - "return" in `New-RenderKitTemplate`was missing
- Fixes [#25](https://github.com/djtroi/RenderKit/issues/25) - Cross-machine backup locks are no longer treated as permanently active. Stale detection now falls back to lock file age when the originating process cannot be verified on a remote host.
- Fixes [#26](https://github.com/djtroi/RenderKit/issues/26) - Source project folder is no longer removed before manifest embedding completes. Source removal now runs as the final step after archive creation, integrity check, log injections and manifest embedding prevent data loss if a late-stage operation fails. 
- Fixes #34 - Merge Ticket of [#8](https://github.com/djtroi/RenderKit/issues/8) and [#7](https://github.com/djtroi/RenderKit/issues/7)
- Fixes #494 - PSScriptAnalyzer Warning
- Fixes #466 - PSScriptAnalyzer Warning
- Fixes #452 - PSScriptAnalyzer Warning
- Fixes #451 - PSScriptAnalyzer Warning
- Fixes #450 - PSScriptAnalyzer Warning
- Fixes #448 - PSScriptAnalyzer Warning
- Fixes #469 - PSScriptAnalyzer Warning
- Fixes #256 - PSScriptAnalyzer Warning
- Fixes #252 - PSScriptAnalyzer Warning
- Fixes #251 - PSScriptAnalyzer Warning
- Fixes #247 - PSScriptAnalyzer Warning
- Fixes #237 - PSScriptAnalyzer Warning
- Fixes #233 - PSScriptAnalyzer Warning
- Fixes #231 - PSScriptAnalyzer Warning
- Fixes #224 - PSScriptAnalyzer Warning
- Fixes #223 - PSScriptAnalyzer Warning
- Fixes #197 - PSScriptAnalyzer Warning
- Fixes #124 - PSScriptAnalyzer Warning
- Fixes #112 - PSScriptAnalyzer Warning





## 0.3.5 - 2026-04-11

### Patch

### Added

- Added `build/Build-RenderKitPackage.ps1` to stage a lean release artifact and generate a publishable `.nupkg`
- Added `build/Publish-RenderKit.ps1` to publish the staged package through `PSResourceGet`
- Added release output ignores for generated `artifacts/`

### Changed

- Switched the release packaging flow to a staged build so gallery packages no longer include repo-only content such as `.git`, workflows, or test files
- Bundled the published module into a single release `RenderKit.psm1` while keeping the source-split development layout
- Prepared gallery metadata and release notes for version `0.3.5`
- Made some small Code cleanups, scriptanalyzer Bypasses and added some Outputtypes

### Fixed

- Fixed a PSGallery packaging issue where system templates located under `src\Resources\Templates` were not found at runtime because the code only searched `Resources\Templates`. The Lookup is now robust and supports both layouts, including system mappings.
 Relevant Files: `RenderKit.StorageService.ps1`, `RenderKit.ImportService.ps1`
- Fixed a freezing / unresponsive Powershell window when transferring large files during Import-Media.
 Replaced `Copy-Item` with stream-based copying and continous progress updates (copy, source hash, staging hash), improving responsiveness and visibility during long operations.
 Relevant file: `RenderKit.ImportService.ps1`

## 0.3.4 - 2026-04-10

### Patch

### Changed

- Refactored the .psm1 file for robust dot sourcing

## 0.3.3 - 2026-04-04

### Patch

---

### Added

- Added OutputTypes to some Functions
- Added ShouldProcess functionalities to some Functions

### Changed

- Fixed the error that caused an error at loading the functions.

### Removed

- Removed some PluralNouns that make sense. Suppressed some others.

## 0.3.2 - 2026.04.02

### Patch

---

### Changed

- Fixed a minor error in  "FunctionsToExport" segment in the Manifest file.

## 0.3.1 - 2026-04-02

### Patch

---

### Removed

- Removed trailing white spaces in the code

## 0.3.0 – 2026-03-31

### Minor Release

---

### Added

#### Import-Media full workflow

- Added interactive import wizard mode when `Import-Media` is called without parameters
- Added parameter-driven scan/filter mode (`-ScanAndFilter`) with folder/date/wildcard criteria
- Added optional classification phase to route files by template/mapping rules
- Added optional transaction-safe transfer phase with hash verification (`SHA256`, `SHA1`, `MD5`)
- Added improved preview and selection flow for matched files

#### Drive detection and source selection

- Added include switches for fixed and unsupported filesystems
- Added interactive source candidate selection workflow
- Added whitelist integration for known source devices

#### Backup hardening

- Added ZIP archive creation to backup pipeline
- Added archive content integrity check against source file hash index
- Added backup log injection into archive
- Added backup manifest generation and persistence

---

### Changed

- Updated module manifest version to `0.3.0`
- Updated documentation and README examples for release `0.3.0`

---

### Removed

- Removed prerelease tag (`alpha`) from module manifest for the `0.3.0` release

---

### Fixed

- Stabilized backup flow around cleanup, integrity validation, and archive finalization output
- Improved import flow validation for invalid date ranges (`-FromDate` / `-ToDate`)

---

### Security

- No changes

## 0.2.0 – 2026-02-11

### Minor Release

---

### Added

#### Backup System

- Introduced `Backup-Project`
- Creates structured backups of RenderKit projects
- Cleans temporary files, proxy files and software artifacts (WIP) before backup
- ZIP packaging planned for future release

#### Project Metadata System

- Introduced `.renderkit` folder
- Added `project.json` containing:
  - Unique Project GUID
  - Project Name
  - Creation timestamp (ISO 8601)
  - Operating System
  - RenderKit version
  - Template name
  - Template source

#### Template Engine

- Added multiple project templates
- Introduced `New-Project -Template`
- Fallback to `default` template if specified template does not exist

#### Backup Locking

- Implemented `backup.lock` mechanism
- Prevents concurrent modifications during backup

#### Internal Improvements

- Added internal logging foundation (WIP)
- Added preparation for future Dry-Run functionality

---

### Changed

- Renamed `Template` folder to `Templates`
- Updated MIT License metadata

---

### Removed

- Removed all function aliases due to PowerShell resolution issues

---

### Fixed

- Fixed module version detection in `project.json`

---

### Deprecated

- None

---

### Security

- No changes

## 0.1.0 2026.01.29

### Added

- Added Function "New-Project"
- Added Function "Set-ProjectRoot"

### Changed

- Nothing

### Deprecated

- Nothing

### Removed

- Nothing

### Fixed

- Nothing

### Security

- Nothing
