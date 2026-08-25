# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

### Changed

- **RS-1571:** Harden project manifest parsing (#108). (`99c8ba0`)
- **RS-1571:** Keep current 1.1.8 import implementation. (`9fbce8c`)
- **RS-1571:** Remove superseded duplicate manifest parser. (`c76d895`)
- **RS-1571:** Resolve duplicate manifest-security test. (`1be8a61`)
- **RS-1571:** Resolve 1.1.8 import conflict. (`7a82802`)
- **RS-1571:** Cover project manifest parser limits. (`1215b93`)
- **RS-1571:** Route project imports through secure manifest parser. (`24294b3`)
- **RS-1571:** Add bounded secure project manifest reader. (`7de895d`)
- **RS-1571:** Keep backup cleanup off reparse targets (#119). (`5d1d067`)
- **RS-1571:** Bound JSON reads on the opened stream (#118). (`fd8a1b8`)
- **RS-1571:** Bound metadata subprocess resources (#117). (`5749967`)
- **RS-1571:** Bound backup process diagnostics (#120). (`1233417`)
- **RS-1571:** Contain project paths within search roots (#115). (`dfd1d4b`)
- **RS-1571:** Restrict MediaInfo native library discovery (#114). (`b4c4724`)
- **RS-1571:** Harden legacy process argument quoting (#113). (`6f04876`)
- **RS-1571:** Bound project archive extraction (#111). (`27e37d8`)
- **RS-1571:** Contain import traversal within the selected source (#110). (`a11d8bf`)
- **RS-1571:** Reject reparse-point sources during project export (#109). (`db033f3`)
- **RS-1576:** Fix backup adapter error contract (#122). (`840ef36`)
- **RS-1571:** Constrain imported project roots to destination (#107). (`61a194d`)
- **RS-1571:** Harden project archive manifest parsing (#106). (`d909479`)

### Deprecated

### Removed

### Fixed

### Security

## [1.1.7] - 2026-08-23

RenderKit 1.1.7 adds targeted one-shot worker orchestration for host integrations
while preserving the existing standalone priority/FIFO worker behavior.

### Changed

- **RS-1563:** Added optional `-JobId` targeting to `Start-RenderKitJobWorker` for `-RunOnce` workers so higher-level orchestrators can bind a worker dispatch to one specific queued job without consuming an older queue entry first.
- Targeted claims are performed atomically and require matching queued status, job type, and queue name while retaining the existing lease, heartbeat, retry, cancellation, worker-state, and diagnostic logging behavior.
- Added regression coverage for queue/type mismatches, running/cancelled/terminal targets, duplicate execution prevention, and concurrent cross-process claims against the same target job.
- Omitting `-JobId` keeps the existing queue worker behavior unchanged; no persisted schema changes are introduced by this release.

## [1.1.6] - 2026-08-22

RenderKit 1.1.6 is a filesystem-compatibility patch release focused on reliable
read access to packaged resources from protected installation locations.

### Fixed

- **RS-1552:** Fixed provider-specific JSON reads failing against valid read-only packaged resources under protected installation locations such as `C:\Program Files`. JSON reads now use provider-neutral .NET file APIs, preserve retry, size-limit and validation behavior, and report access/I/O failures separately from malformed JSON.

## [1.1.5] - 2026-08-14

RenderKit 1.1.5 is a patch release focused on runtime safety, durable job execution,
cross-platform correctness, backup reliability, and release-pipeline safeguards.
The public command surface and persisted job/event schemas remain unchanged.

### Changed

- **RS-1512:** Event-to-job bridge deduplication now evaluates the duplicate condition and appends the new job inside the same JobStore transaction. Concurrent bridge invocations therefore cannot pass a separate read-before-write check and enqueue duplicate work for the same idempotent trigger.
- **RS-1513:** Worker diagnostic logging is now strictly best-effort, including failures while resolving the default log path. Diagnostic I/O and warning behavior can no longer change worker control flow, even when callers use terminating warning preferences.
- **RS-1514:** Backup lock ownership now uses portable runtime machine/user identity and treats legacy or unverifiable ownership conservatively on shared paths instead of assuming that an unknown lock belongs to the local host.
- **RS-1516:** Backup manifests and background-job audit metadata now use portable runtime identity. Missing `requestedBy.user` and `requestedBy.machine` values are filled without mutating caller-owned context objects or overwriting explicitly supplied audit fields.
- **RS-1520:** Release publishing is now serialized and gated by the successful Quality Gate for the exact `main` push SHA. Package build, local installer validation, secrets/version/changelog preflight, GitHub Packages publication, PowerShell Gallery publication, and Gallery installation validation all complete before the GitHub Release is created as the final visible success marker. Existing release versions are never overwritten.

### Fixed

- **RS-1508:** Fixed parallel backup workers invoking PowerShell script blocks from `Process.ErrorDataReceived` callbacks on thread-pool threads without an available PowerShell runspace. Redirected stderr is drained asynchronously without cross-thread PowerShell callbacks while stdout remains available for FFmpeg progress streaming.
- **RS-1511:** Fixed generic worker completion and retry handling overwriting a job state that a handler had already persisted deliberately. Handler-owned states remain authoritative on both normal return and exception paths; generic success/retry behavior applies only while the job is still `Running`.
- **RS-1514:** Fixed stale backup-lock detection and takeover races. Foreign or machine-less locks are no longer evaluated using local PIDs, and stale ownership is verified and replaced through the same exclusive file handle so a slower contender cannot remove a freshly acquired lock.
- **RS-1515:** Fixed worker crash recovery interpreting foreign or legacy shared worker state as a dead local process. PID liveness checks and `CrashDetected` recovery are now performed only when persisted state explicitly identifies the current host.
- **RS-1517:** Fixed import project discovery constructing `.renderkit/project.json` with an embedded Windows path separator. Physical metadata paths are now resolved from native path segments on Windows, Linux, and macOS.
- **RS-1518:** Fixed private backup failure paths emitting a secondary PowerShell `ErrorRecord` immediately before throwing the canonical terminating exception. Persistent diagnostics remain available without creating duplicate error representations that can mask the primary failure in hosted PowerShell environments.
- **RS-1519:** Fixed the Windows PowerShell 5.1 FFmpeg hardware-probe fallback relying on modern process argument/termination APIs and incomplete legacy command-line quoting. The fallback now handles whitespace, empty arguments, quotes, backslashes, timeout termination, and redirected diagnostics without changing the modern PowerShell 7 path.

## [1.1.4] - 2026-08-07

### Fixed

- Fixed stale release-version assertions and README metadata left at `1.1.2` after the `1.1.3` release cut.
- Fixed release-documentation validation to recognize the canonical Keep a Changelog heading format (`## [version]`).

## [1.1.3] - 2026-07-31

### Added

- Added RS-798/RS-799 worker capability discovery for local and registered
  backup workers, including per-worker CPU, GPU, FFmpeg, and encoder support.
- Added per-worker backup-profile execution results with eligible worker IDs,
  compatibility states, and CPU-fallback reporting without preventing users
  from storing structurally valid custom profiles.
- Added RS-1204 machine-readable and documented RenderKit file-format
  definitions for the ZIP-based `.rkit` and `.rkitpkg` project archives.

### Changed

- RS-1204 project exports now always append the canonical `.rkit` or
  `.rkitpkg` extension when another extension is requested, normalize canonical
  extension casing, and continue returning the effective output path.
- RS-798/RS-799 hardware validation now evaluates every available worker
  independently and preserves offline worker registrations for heterogeneous
  future worker pools.

### Fixed

- Fixed RS-1129 automatic encoder selection treating an FFmpeg encoder as
  usable when the installed GPU cannot execute it. Hardware encoders are now
  probed with a real one-frame encode at supported dimensions and safely fall
  back to a compatible CPU encoder.

## [1.1.2] - 2026-07-23

### Added

- Added public template and mapping import, export, and whole-document
  validation commands with atomic persistence and explicit `Error`,
  `Overwrite`, and `Rename` conflict handling.
- Added structured resource mutation, export, and validation results suitable
  for PowerShell automation, CI workflows, and external hosts.

### Fixed

- Reject media transfers into terminal `Archived` or `Cancelled` projects
  before scanning or copying begins, and avoid reporting already committed
  files as failed when a concurrent lifecycle update cannot be persisted.
- Made the fast import copy path cancellable between buffered writes, removed
  partial staging files on interruption, and reported in-flight staging bytes
  so callers can display live transfer progress for large files.
- Streamed measured scan, selection, classification, transfer, finalization,
  and metadata-extraction progress through PowerShell hosts.
- Corrected media classification and preview scaling calculations.
- Fixed normal backups with `-KeepSourceProject` incorrectly assigning the
  terminal `Archived` lifecycle status; legacy backup-generated archive
  transitions are now interpreted as their preceding status.

## [1.1.1] - 2026-07-23

### Fixed

- Fixed a regression where `Import-Media` could fail with
  `Resolve-RenderKitMappingFileName` not being recognized after loading the
  module.
- Restored the internal mapping filename resolver to maintain compatibility
  across the import pipeline.
- Fixed mapping template resolution so mapping identifiers are consistently
  normalized to their corresponding `.json` files before loading.

## [1.1.0] - 2026-07-11

### Added

- Added the public metadata workflow: `Get-Metadata`, `Add-Metadata`,
  `Rollback-Metadata`, `Import-Metadata`, `Export-Metadata`,
  `Update-MetadataCache`, metadata templates, canonical registry queries, and
  field-value validation.
- Added versioned metadata history and batch rollback, explicit conflict
  handling, provenance, embedded-write results, and optional XMP sidecar
  creation for supported Dublin Core/XMP fields.
- Added versioned backup configuration profiles, profile import/export and
  migration, adapter registration, durable BackupProject job controls,
  worker/status commands, report generation, retry/resume behavior, and
  system-resource scheduling constraints.
- Added a versioned, module-owned `ClientRegistry` in `Clients.json` with
  atomic transactions, schema validation, backup behavior, stable IDs,
  bounded contacts/addresses/tags/notes, archive-first lifecycle, and
  optimistic revisions.
- Added `Get-RenderKitClient`, `New-RenderKitClient`, and
  `Set-RenderKitClient` for global client discovery and lifecycle management.
- Added paged client summary/detail/create/update engine operations with stable
  validation, access-context, not-found, conflict, and storage errors. List
  summaries intentionally omit contact details and other personal data.
- Added focused registry, public-command, engine-operation, actor-guard, and
  stale-revision regression coverage.
- Added the client registry to the standard state health and optional
  backup-restoration diagnostics.
- Added a versioned `PublishingSchedule` registry with UTC range queries,
  explicit time zones, validated status transitions, stable relationship
  snapshots, optimistic revisions, and `Get-RenderKitPublication`,
  `New-RenderKitPublication`, and `Set-RenderKitPublication`.
- Added publishing list/detail/create/update engine operations with stable
  actor, validation, not-found, conflict, and storage result envelopes.
- Added versioned BWF, iXML, ID3, and Matroska read profiles with complete
  registry-field coverage through explicit mappings or documented unmapped
  decisions.
- Added typed BEXT/iXML/ID3/Matroska normalization for dates, times, booleans,
  track/disc pairs, 64-bit iXML timestamps, and structured track lists.
- Added a versioned Dublin Core/XMP application profile covering all 15 DCMES
  elements as eight semantic mappings and seven explicit unmapped decisions.
- Added Dublin Core/XMP integration slices for qualified terms, standard XMP
  namespaces, sidecars, provenance, interactive editing, and production
  workflows.
- Added a versioned IPTC Core 1.5 and Extension 1.9 field map with deterministic
  XMP/IIM precedence, structured values, controlled vocabularies, and embedded
  read/write coverage.
- Added IPTC profile import/export, template and batch support, provenance,
  conflict/state modeling, catalog synchronization, and reference-image smokes.
- Bundled MediaInfoLib 26.01 native readers for Windows x64/ARM64, macOS
  x64/ARM64, and Linux x64, with pinned source and file hashes plus preserved
  upstream licenses.
- Added a reproducible MediaInfo asset sync script that rejects archive and
  extracted-file integrity mismatches.
- Bundled ExifTool 13.59 for Windows x86/x64 and as the official portable Perl
  distribution for macOS/Linux, with pinned upstream archive checksums,
  per-file hashes, and preserved license material.
- Added a reproducible ExifTool asset sync script and resolver coverage for
  explicit, bundled, metadata-host, and system-CLI execution.
- Bundled hash-verified TagLibSharp 2.3.0 assemblies and LGPL license material
  for native ID3v2.4 reads and writes on Windows PowerShell and PowerShell 7.
- Added atomic ID3v2.4 writes for scalar and repeated text, URL and TXXX
  frames, APIC artwork, USLT/SYLT lyrics, and CHAP/CTOC chapters, with native
  semantic readback and preservation tests for unrelated frames.
- Bundled hash-verified MKVToolNix 99.0 `mkvpropedit` and `mkvextract`
  runtimes, complete notices, and corresponding source for Windows x64, with
  environment/system resolution on other platforms.
- Added atomic Matroska writes for preserved global SimpleTags, first-of-type
  audio/video track headers, stereo layout, and structured chapters, plus
  native tag/chapter readback and provenance.

### Changed

- Ubuntu and macOS quality-gate runners now install their native MKVToolNix
  packages and execute the complete Matroska write/read integration suite
  through the existing system-runtime resolver; Windows x64 continues to use
  the bundled hash-verified runtime.
- Updated the module manifest and Gallery release notes for version `1.1.0`.
- Expanded README and documentation coverage for all exported commands,
  metadata backends, client/publishing state, and backup job operations; removed
  obsolete command-export guidance and invalid command examples.
- ID3 adapter capabilities now route supported audio writes through the
  bundled TagLibSharp backend while retaining ExifTool as the broad fallback
  reader.
- Embedded writes now compose compatible Dublin Core/XMP and IPTC profile tags
  without falling back to language-destructive unqualified XMP writes.
- Dublin Core repeated values remain lists, while scalar registry fields apply
  an explicit first-non-empty application-profile constraint.
- IPTC Core list fields now retain true repeated values during ExifTool writes,
  and default-language XMP updates preserve other language alternatives.
- IPTC Extension structures remain object lists; ambiguous scalar projections
  now emit conflicts instead of silently selecting an arbitrary value.
- MediaInfo metadata reads now prefer bundled native libraries and retain the
  existing host/CLI failover when a native library is unsupported or fails at
  load/read time. Linux ARM64 is explicitly modeled as an external fallback
  runtime instead of claiming an unavailable generic bundled binary.
- ExifTool reads and embedded writes now share one bundled-first resolver and
  fail over at runtime through a configured metadata host and system ExifTool.

### Fixed

- Fixed atomic JSON candidate validation on Ubuntu and macOS by reading hidden
  dot-prefixed temporary files with explicit hidden-file access.
- Fixed stale-job recovery on Windows PowerShell 5.1 by using a compatible UTC
  `DateTimeStyles` combination.
- Fixed Windows PowerShell 5.1 unwrapping single IPTC structure values and
  ExifTool's one-record JSON array differently from PowerShell 7, which had
  dropped creator-contact and XMP-sidecar fields.
- Fixed ambiguous IPTC Extension structures omitting the canonical field from
  detailed results; the field is now explicitly `$null` while conflict
  candidates remain available.
- Fixed XMP-sidecar follow-up writes omitting whether the sidecar was newly
  created from their public embedded-write result.
- Fixed the ID3 preservation regression test losing collection shape when a
  single private frame was emitted through the PowerShell pipeline.
- Fixed the isolated engine contract snapshot test by loading and initializing
  the artifact-version catalog required by the client and publishing schema
  fields, and added assertions for both fields.
- Fixed ExifTool field normalization on Windows PowerShell 5.1 by unwrapping
  the first JSON result object instead of retaining it inside a one-item array.
- Fixed successful structured ExifTool imports being reported as failures by
  Windows PowerShell 5.1 when ExifTool writes its status line to stderr.
  
## [1.0.1] - 2026-07-01

### Patch

### Fixed

- Fixed `Import-Media` interactive menu option construction so Boolean parameters no longer receive accidental `System.Object[]` values.
- Fixed interactive menu rendering in PowerShell 7 and added numbered `Read-Host` fallback input for Visual Studio Code, Windows PowerShell ISE, and hosts without raw key support.
- Optimized transaction-safe media transfers by calculating the source hash during the copy pass instead of reading every source file a second time, and added separate copy, verification, and end-to-end throughput metrics.
- Added a PowerShell 5.1-compatible small/large-file scheduler. The default `Maximum` profile prefers up to four byte-bounded parallel workers for small files while keeping large transfers on one stream by default.
- Split transfer execution into independent copy and staging-verification workers so read-back verification can overlap the next copy, with an adaptive copy-worker limit and an in-flight byte budget covering both pipeline stages.
- Added explicit `-SourceDisposition Move` for rename-only same-volume imports on Windows, including commit rollback to the original source path and preserved staging diagnostics when rollback fails.
- Fixed large files monopolizing the complete in-flight budget until read-back verification completed. Pipeline admission now accounts for estimated resident buffers rather than logical file size.
- Added `-TransferVerificationMode Fast|Full`. The default `Fast` mode uses the native file-copy path with staging-length validation and atomic commit, while `Full` retains independent SHA read-back verification.

## [1.0.0] - 2026-06-19

### Major

### Added

- Added internal project search index and discovered-project overview state for fast `Get-Project`reads and indexed discovery refreshes.
- Added internal project discovery that scans indexed roots for `.renderkit`markers, validates metadata, updates discovery diagnostics, and prepares duplicate-project-id conflict details for future repair workflows
- Added new Cmdlet: Get-Project. The command returns table-friendly project summary objects with these fields:
- Added architecture documentation for project identity and registry, project lifecycle, domain events and jobs, artifact versioning, cross-platform storage, security baseline, and the phased implementation plan.
- Added cross-platform user storage support and documentation for configuration, state, cache, and user data roots, including `RENDERKIT_HOME` overrides and legacy data preservation guidance.
- Added atomic JSON persistence helpers with file locking, backup restoration support, validation hooks, and transaction-style updates for RenderKit state files.
- Added a central artifact versioning catalog and compatibility service for project, registry, event, job, template, mapping, device, client, publishing, metadata, and configuration artifacts.
- Added internal project registry and lifecycle services for tracking known projects, reconciling moved/missing project folders, validating lifecycle status transitions, and emitting lifecycle events.
- Added internal domain-event storage, event-to-job automation subscriptions, durable job storage, job worker registration, and repair/health checks for RenderKit state.
- Added host-facing engine contracts with actor and operation contexts, correlation/causation id handling, stable `RenderKitResult` envelopes, registered error codes, and a machine-readable engine contract snapshot for broker/Electron handoff.
- Added engine facade operations for engine info/state, project read models, job creation/list/detail/cancellation/retry/progress/success/failure, event list/detail, event bridge invocation, job handler catalog, and worker tick orchestration.
- Added JobStore v1.1 worker primitives for queue names, priority, actor context, ownership, leases, heartbeats, stale-running-job recovery, retries, structured progress, structured errors, and terminal results.
- Added EventStore v1.1 fields for event id aliases, event schema version, category, retention, actor context, data/payload compatibility, processing attempts, structured last errors, and reserved integrity metadata.
- Added safe job handler metadata catalogs with handler ids, versions, descriptions, payload schema versions, capabilities, idempotency, progress support, and cancellation support without exposing executable scriptblocks.
- Added Pester coverage for storage, persistence, artifact versioning, project registry/lifecycle, repair, domain events, event-to-job automation, durable jobs, worker leases/heartbeat, handler catalog metadata, and engine facade contracts.
- Added `Update-RenderKitDiscoveredProjectAvailability`, which refreshes every stored discovered project’s `available` flag from the current filesystem state and updates timestamps when availability changes.
- Added actor-context guards before `Update-RenderKitEngineJobProgress`, `Set-RenderKitEngineJobSucceeded`, and `Set-RenderKitEngineJobFailed` can mutate job state; missing actor context now returns `RK_ACCESS_CONTEXT_MISSING` before any job mutation happens.
- Added regression coverage to verify progress/succeeded/failed mutations without actor context are rejected and leave the running job unchanged.
- Added a guard that rejects paths containing no usable folder name, preventing empty JSON folder nodes from being written.
- Added regression coverage for the reported leading-backslash case, verifying the resulting template starts directly with `test1`, then `test2`, then `test3`.
- Added `Write-RenderKitLogFileEntry`, which recreates the log directory and log file if missing before appending, and converts remaining write failures into warnings instead of letting logging break commands like `Remove-Project`.
- Added regression coverage for the reported case: initialize project logging, delete `renderkit.log`, then write another log entry without throwing and verify the file is recreated.

### Changed

- Changed `Get-Project`to read `DiscoveredProjects.json`by default and to run internal indexed discovery only when `-Refresh`is supplied.
- Changed `Get-Project` to return discovered project summary objects directly so callers and tests can access properties without receiving formatting records.
- Changed `Set-ProjectRoot`and `New-Project`to feed the project search index so current roots, previous roots, explicit absolute project paths, and parant folders can be discovered efficiently.
- Changed JSON-reading and JSON-writing paths across storage, backup, device, mapping, template, project, export, and delivery services to use the new persistence helpers where appropriate.
- Changed bundled artifact compatibility metadata so EventStore and JobStore now use current schema version `1.1` while retaining compatibility with readable `1.0` stores.
- Changed project commands and import/export flows to update project registry entries and lifecycle state consistently through internal services.
- Changed event and job documentation to describe the vNext envelopes, worker semantics, bridge behavior, and host-facing engine contracts.
- Changed docs index pages to include storage, artifact versioning, project registry, project lifecycle, events, jobs, workers, automation, repair, and engine contracts.
- Changed `Export-Project` parameter handling: `Export-Project` nor correctly detects if the second parameter `-DestinationPath`is an existing directory or a path ending with a `/` or `\`. In these cases it atuomatically generates the default filename `<ProjectName>.rkit` for ManifestOnly or `<ProjectName>.rkitpkg` for SelftContained inside that folder, instead of strictly expecting a file path.

### Fixed

- Fixed resilience of JSON state updates by introducing atomic write, lock, backup, and validation behavior for internal state files.
- Fixed host-facing project detail lookups so project registry read failures return stable `RK_STORAGE_UNAVAILABLE` result envelopes instead of leaking raw exceptions.
- Fixed PowerShell automatic-variable sensitivity in the engine project detail lookup by avoiding `$Matches`/`$matches` naming in new facade code.
- Fixed `Import-Project` path handling so quoted user input is normalized, supported archive paths are validated, and accidentally swapped destination/archive arguments can be recovered.
- Fixed `Remove-Project` success logging after project deletion by clearing stale logging state when the active log target points inside the removed project.
- Fixed project registry upsert filtering so it replaces only the exact same `id` + `rootPath` entry, instead of dropping entries that share only the same project ID or only the same root path. This preserves duplicate-ID registry entries at different roots so conflict/repair flows can see them
- Fixed `Add-FolderToTemplate` path handling by filtering out empty path segments after splitting on `/` or `\`, so inputs like `\test1\test2\test3` no longer create a template folder node with an empty `Name`.
- Fixed access denied error on directory export. Fixed an issue where passing an existing folder (e.g. `C:\install`) caused `ZipFile.Open()` to mistakenly attempt to open the directory as a file. Project roots located directly under root directories or second-level paths are no longer artifically blocker by RenderKit, as long as Windows/ACL write permissions are met. 
- Fixed project logging so `Write-RenderKitLog` no longer calls `Add-Content` directly against a potentially deleted `renderkit.log`; it now routes file writes through `Write-RenderKitLogFileEntry`.
- Fixed the debug-level comparison typo so debug entries are written when `-Level Debug` is used.

## [0.3.9] - 2026-06-18

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

## [0.3.8] - 2026-06-16

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

## [0.3.7] - 2026-04-21

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

## [0.3.6] - 2026-04-xx

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

## [0.3.5] - 2026-04-11

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

## [0.3.4] - 2026-04-10

### Patch

### Changed

- Refactored the .psm1 file for robust dot sourcing

## [0.3.3] - 2026-04-04

### Patch

---

### Added

- Added OutputTypes to some Functions
- Added ShouldProcess functionalities to some Functions

### Changed

- Fixed the error that caused an error at loading the functions.

### Removed

- Removed some PluralNouns that make sense. Suppressed some others.

## [0.3.2] - 2026.04.02

### Patch

---

### Changed

- Fixed a minor error in  "FunctionsToExport" segment in the Manifest file.

## [0.3.1] - 2026-04-02

### Patch

---

### Removed

- Removed trailing white spaces in the code

## [0.3.0] - 2026-03-31

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

## [0.2.0] - 2026-02-11

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

## [0.1.0] - 2026.01.29

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
