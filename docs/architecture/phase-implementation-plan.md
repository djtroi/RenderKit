# RenderKit Architecture Implementation Plan

## Purpose

This plan turns the accepted Phase 0 decisions into incremental engineering phases. It deliberately separates cross-platform persistence, project discovery, lifecycle, jobs, events, and global migration so each layer can be tested before the next layer depends on it.

Public PowerShell command names are not assigned by this plan. The product owner decides every exported command name before implementation of the relevant public API.

## Architectural sequence

```text
Cross-platform storage
-> atomic persistence
-> artifact compatibility
-> project registry
-> project resolver
-> registry repair
-> lifecycle integration
-> lifecycle schema and state machine
-> domain events
-> event history
-> durable jobs and outbox
-> safe automation
-> global upgrades and rollout
```

## Phase 0: Architecture decisions

### Deliverables

- [ADR-001: Project Identity and Local Registry](ADR-001-project-identity-and-registry.md)
- [ADR-002: Project Lifecycle State Machine](ADR-002-project-lifecycle.md)
- [ADR-003: Domain Events, Durable Jobs, and Automation](ADR-003-domain-events-and-jobs.md)
- [ADR-004: Artifact and Business Versioning](ADR-004-artifact-versioning.md)
- [ADR-005: Cross-Platform Storage and Path Handling](ADR-005-cross-platform-storage.md)
- [ADR-006: Local Engine Security Baseline](ADR-006-security-baseline.md)

### Exit criteria

- Identity, registry, repair, lifecycle, event, versioning, storage, and security decisions are accepted.
- Public capabilities are classified as immediate, internal, or deferred.
- Exact exported command names remain reserved for product-owner approval.

## Phase 1: Cross-platform storage foundation

### Work

1. Consolidate all user-storage lookup in the private storage service.
2. Add semantic paths for configuration, state, cache, and user data.
3. Add Windows, Linux/XDG, and macOS-native resolution.
4. Add a `RENDERKIT_HOME` test/portable override.
5. Replace direct `$env:APPDATA` access in config and device services.
6. Add centralized directory creation and permission handling.
7. Add a path service for native absolute paths, safe child paths, and portable relative paths.

### Tests

- Windows PowerShell 5.1 path resolution.
- PowerShell 7 on Windows, Linux, and macOS.
- XDG override and fallback behavior.
- macOS Application Support and Cache paths.
- isolated test state using `RENDERKIT_HOME`.
- relative-path and traversal rejection.

### Exit criteria

- Domain and public services do not resolve application storage directly.
- Tests do not write to the developer's real profile.
- Existing config remains readable or has a controlled migration path.

## Phase 2: Atomic persistence and locking

### Work

1. Implement bounded exclusive file locks.
2. Implement defensive JSON reads with size, parse, and schema errors.
3. Implement same-directory temporary writes.
4. Validate temporary content before commit.
5. Preserve the last valid backup.
6. Add platform-safe replace/rename fallbacks.
7. Add recovery behavior that never silently replaces corruption with empty state.

### Tests

- concurrent writers;
- interrupted writes;
- invalid JSON;
- unknown future schema;
- read-only storage;
- stale lock handling;
- backup recovery;
- file-system replacement fallbacks.

### Exit criteria

- Registry, config, job, and outbox stores can share one persistence foundation.

## Phase 3: Artifact-version foundation

### Work

1. Define artifact types and compatibility results.
2. Add the trusted schema catalog.
3. Implement compatibility checks.
4. Introduce migration-step registration.
5. Replace hard-coded template compatibility checks.
6. Keep module version separate from all artifact versions.

### Tests

- current, readable, upgradeable, required-upgrade, and future schemas;
- directed migration chains;
- refusal to write unsupported future schemas.

### Exit criteria

- Every new persisted format declares an artifact type and schema version.

## Phase 4: Project Registry 1.0

### Work

1. Define and validate the registry schema.
2. Store records by immutable project ID.
3. Support duplicate case-insensitive names.
4. Store native absolute paths and availability.
5. Reserve cached lifecycle and project-version fields.
6. Add register, update, list, lookup, tombstone, and validation operations.
7. Use atomic locked transactions.

### Tests

- duplicate names;
- duplicate IDs;
- same path with conflicting IDs;
- unavailable paths;
- invalid metadata;
- concurrent registry updates;
- backup recovery.

### Exit criteria

- Registry storage is stable before public project commands depend on it.

## Phase 5: Unified project resolver

### Work

1. Define one project-context object.
2. Resolve by explicit root, project ID, and project name.
3. Add legacy explicit/default-root fallback.
4. Verify local metadata and ID on every resolution.
5. Report name ambiguity and identity mismatch with stable error codes.
6. Update last-seen and availability cache.
7. Apply auto-registration policy for explicit valid roots.

### Tests

- unique and ambiguous names;
- rename and move identity preservation;
- unavailable volume;
- metadata mismatch;
- future project schema;
- explicit path precedence.

### Exit criteria

- Existing project commands can migrate to one resolver without changing business behavior.

## Phase 6: Registry repair

### Work

1. Implement discovery against configured and explicit roots.
2. Add a separately enabled suitable-local-volume scan.
3. Exclude unsafe virtual roots and remote mounts by default.
4. Do not follow symbolic links by default.
5. Build a repair plan without mutation.
6. Register newly discovered valid projects during apply.
7. Recover moved paths only with explicit apply intent.
8. Report duplicate identity conflicts.
9. Support confirmed missing-entry tombstones.

### Tests

- external moves;
- new valid projects;
- duplicate IDs;
- permission failures;
- symlink cycles;
- scan cancellation;
- `WhatIf`;
- no mutation during discovery.

### Exit criteria

- Repair returns a structured report suitable for CLI and GUI consumers.

## Phase 7: Existing command integration

### Integration order

1. project creation;
2. project import;
3. project copy;
4. project rename;
5. project removal;
6. backup;
7. export;
8. delivery/send;
9. media import.

### Rules

- Registry updates occur only after the authoritative operation succeeds.
- `WhatIf` and dry-run operations produce no durable registry, state, or event changes.
- Rename updates by project ID.
- Copy registers a new ID.
- Remove creates a tombstone only after successful removal.
- Read operations may update last-seen state.

### Exit criteria

- All project-aware commands use the unified resolver.
- Commands accept future name/ID/root parameter sets without duplicating lookup logic.

## Phase 8: Project schema with lifecycle

### Work

1. Define the new project schema.
2. Add workflow ID/version, lifecycle status, status version, actor, timestamp, and reason.
3. Add migration from legacy projects to `Unknown`.
4. Back up and validate every migrated metadata file.
5. Update registry lifecycle cache after successful migration.

### Tests

- new project starts `Draft`;
- legacy project becomes `Unknown`;
- migration is idempotent;
- future schemas remain untouched;
- failed migration restores the last valid file.

### Exit criteria

- Lifecycle state can be read consistently before state-changing commands are exposed.

## Phase 9: Lifecycle state machine

### Work

1. Implement declarative workflow loading and validation.
2. Implement the accepted transition matrix.
3. Implement reason policies and trusted validators.
4. Add project-scoped locking and expected-status-version checks.
5. Implement no-op behavior.
6. Implement creation, media-import activation, restore/new-import, copy, archive, and deletion rules.
7. Return structured transition results.

### Tests

- every allowed and denied transition;
- terminal-state protection;
- concurrent transition attempts;
- required reasons;
- copy start-status restrictions;
- media import with zero, partial, and successful transfers;
- deletion override.

### Exit criteria

- No service writes lifecycle fields directly.
- Public status capabilities are ready for product-owner naming.

## Phase 10: Domain-event core

### Work

1. Define the event envelope and catalog.
2. Implement event factories and validation.
3. Add event IDs, aggregate versions, actors, correlation, and causation.
4. Add category and retention metadata.
5. Reserve integrity fields for future hash chaining.
6. Ensure imported events are inert.

### Tests

- serialization and validation;
- duplicate event IDs;
- aggregate ordering;
- unknown future event schema;
- imported-event isolation.

### Exit criteria

- Lifecycle and project operations can produce durable event records without executing handlers.

## Phase 11: Project event history

### Work

1. Add project-local JSONL history.
2. Implement locked append and streaming reads.
3. Recover from an incomplete last record.
4. Add event filters and retention processing.
5. Add copy provenance and export/import filtering.
6. Add history consistency checks and repair.

### Tests

- concurrent append;
- incomplete final line;
- copied project provenance;
- domain-only export;
- diagnostic-event exclusion;
- no replay of imported history.

### Exit criteria

- History is queryable without being the source of current project state.

## Phase 12: Durable jobs and outbox

### Work

1. Define job schema, states, ownership, lease, progress, cancellation, and retry.
2. Implement pending, processed, and dead-letter outbox stores.
3. Implement idempotency records.
4. Implement handler registration for trusted engine handlers.
5. Implement one-shot job and outbox processing functions.
6. Add crash recovery and retry limits.

### Initial handlers

- update registry lifecycle cache;
- update recovered/moved paths;
- maintain removal tombstones;
- submit archive work;
- emit notification-ready events.

### Tests

- worker crash and reclaim;
- duplicate delivery;
- handler idempotency;
- retry and dead letter;
- cancellation;
- stale lease;
- committed business state surviving secondary-handler failure.

### Exit criteria

- A GUI or service can host a worker without relying on in-memory module lifetime.

## Phase 13: Safe workflow automation

### Work

1. Define declarative triggers, conditions, and allow-listed actions.
2. Add workflow validation and versioning.
3. Propagate correlation and causation.
4. Add recursion and loop limits.
5. Integrate secure credential references.
6. Prepare a stable format for a future visual editor.

### Tests

- unknown action rejection;
- no arbitrary-code execution;
- loop detection;
- repeated event idempotency;
- credential non-disclosure;
- state changes routed through commands.

### Exit criteria

- Workflows can be created by a GUI without embedding executable code.

## Phase 14: Global upgrade and rollout

### Work

1. Build structured upgrade plans.
2. Apply config, registry, outbox, project, template, and mapping migrations by policy.
3. Mark unavailable projects as pending.
4. Add lazy migration when pending projects become available.
5. Add revision rollback as a new linear revision.
6. Produce machine-readable rollout reports.

### Tests

- mixed artifact versions;
- unavailable projects;
- interrupted rollout;
- rollback-to-new-revision;
- user versus system artifacts;
- future-schema refusal;
- `WhatIf`.

### Exit criteria

- Upgrades are deterministic, recoverable, and suitable for CLI and GUI use.

## Public API approval gates

Before each public-capability implementation:

1. document the capability and parameter sets;
2. propose two or three PowerShell-compliant command names;
3. obtain product-owner selection;
4. add command help and documentation;
5. add the approved name to module exports;
6. add compatibility aliases only when explicitly approved.

Immediate public capabilities are:

- list registered projects;
- explicitly register a project;
- repair the registry;
- validate projects/registry entries;
- read project lifecycle status;
- request lifecycle transitions;
- list allowed lifecycle transitions;
- read project history.

Deferred public capabilities include job/outbox administration, upgrade management, artifact-version inspection, and workflow administration.

## Cross-cutting quality gates

Every phase must maintain:

- Windows PowerShell 5.1 compatibility where the module contract requires it;
- PowerShell 7 tests on Windows, Linux, and macOS;
- no direct UI dependencies in domain services;
- structured return objects and stable error codes;
- `ShouldProcess` for mutating public operations;
- no durable changes during `WhatIf` or dry run;
- no executable code loaded from data artifacts;
- no credentials in persisted general-purpose JSON;
- documentation in English.