# 0.3.5 - 2026-04-11

## Patch

## Added

- Added `build/Build-RenderKitPackage.ps1` to stage a lean release artifact and generate a publishable `.nupkg`
- Added `build/Publish-RenderKit.ps1` to publish the staged package through `PSResourceGet`
- Added release output ignores for generated `artifacts/`

## Changed

- Switched the release packaging flow to a staged build so gallery packages no longer include repo-only content such as `.git`, workflows, or test files
- Bundled the published module into a single release `RenderKit.psm1` while keeping the source-split development layout
- Prepared gallery metadata and release notes for version `0.3.5`
- Made some small Code cleanups, scriptanalyzer Bypasses and added some Outputtypes

## Fixed

- Fixed a PSGallery packaging issue where system templates located under `src\Resources\Templates` were not found at runtime because the code only searched `Resources\Templates`. The Lookup is now robust and supports both layouts, including system mappings.
 Relevant Files: `RenderKit.StorageService.ps1`, `RenderKit.ImportService.ps1`
- Fixed a freezing / unresponsive Powershell window when transferring large files during Import-Media.
 Replaced `Copy-Item` with stream-based copying and continous progress updates (copy, source hash, staging hash), improving responsiveness and visibility during long operations.
 Relevant file: `RenderKit.ImportService.ps1`

# 0.3.4 - 2026-04-10

## Patch

## Changed

- Refactored the .psm1 file for robust dot sourcing

# 0.3.3 - 2026-04-04

## Patch

---

## Added

- Added OutputTypes to some Functions
- Added ShouldProcess functionalities to some Functions

## Changed

- Fixed the error that caused an error at loading the functions.

## Removed

- Removed some PluralNouns that make sense. Suppressed some others.

# 0.3.2 - 2026.04.02

## Patch

---

## Changed

- Fixed a minor error in  "FunctionsToExport" segment in the Manifest file.

# 0.3.1 - 2026-04-02

## Patch

---

## Removed

- Removed trailing white spaces in the code

# 0.3.0 – 2026-03-31

## Minor Release

---

## Added

### Import-Media full workflow

- Added interactive import wizard mode when `Import-Media` is called without parameters
- Added parameter-driven scan/filter mode (`-ScanAndFilter`) with folder/date/wildcard criteria
- Added optional classification phase to route files by template/mapping rules
- Added optional transaction-safe transfer phase with hash verification (`SHA256`, `SHA1`, `MD5`)
- Added improved preview and selection flow for matched files

### Drive detection and source selection

- Added include switches for fixed and unsupported filesystems
- Added interactive source candidate selection workflow
- Added whitelist integration for known source devices

### Backup hardening

- Added ZIP archive creation to backup pipeline
- Added archive content integrity check against source file hash index
- Added backup log injection into archive
- Added backup manifest generation and persistence

---

## Changed

- Updated module manifest version to `0.3.0`
- Updated documentation and README examples for release `0.3.0`

---

## Removed

- Removed prerelease tag (`alpha`) from module manifest for the `0.3.0` release

---

## Fixed

- Stabilized backup flow around cleanup, integrity validation, and archive finalization output
- Improved import flow validation for invalid date ranges (`-FromDate` / `-ToDate`)

---

## Security

- No changes

# 0.2.0 – 2026-02-11

## Minor Release

---

## Added

### Backup System

- Introduced `Backup-Project`
- Creates structured backups of RenderKit projects
- Cleans temporary files, proxy files and software artifacts (WIP) before backup
- ZIP packaging planned for future release

### Project Metadata System

- Introduced `.renderkit` folder
- Added `project.json` containing:
  - Unique Project GUID
  - Project Name
  - Creation timestamp (ISO 8601)
  - Operating System
  - RenderKit version
  - Template name
  - Template source

### Template Engine

- Added multiple project templates
- Introduced `New-Project -Template`
- Fallback to `default` template if specified template does not exist

### Backup Locking

- Implemented `backup.lock` mechanism
- Prevents concurrent modifications during backup

### Internal Improvements

- Added internal logging foundation (WIP)
- Added preparation for future Dry-Run functionality

---

## Changed

- Renamed `Template` folder to `Templates`
- Updated MIT License metadata

---

## Removed

- Removed all function aliases due to PowerShell resolution issues

---

## Fixed

- Fixed module version detection in `project.json`

---

## Deprecated

- None

---

## Security

- No changes

# 0.1.0 2026.01.29

## Added

- Added Function "New-Project"
- Added Function "Set-ProjectRoot"

## Changed

- Nothing

## Deprecated

- Nothing

## Removed

- Nothing

## Fixed

- Nothing

## Security

- Nothing
