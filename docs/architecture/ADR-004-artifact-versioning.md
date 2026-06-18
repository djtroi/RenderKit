# ADR-004: Artifact and Business Versioning

- **Status:** Accepted
- **Date:** 2026-06-18
- **Decision owners:** RenderKit maintainers

## Context

RenderKit already has multiple version concepts: module version, project metadata schema, template version, and mapping version. Future requirements include project business revisions, template and mapping rollback, global migration plans, and status/workflow evolution.

A single version field cannot safely represent software compatibility, data shape, business revision, lifecycle concurrency, and event ordering.

## Decision

### Separate version dimensions

RenderKit distinguishes:

| Version | Purpose |
|---|---|
| `ModuleVersion` | Installed RenderKit software release. |
| `SchemaVersion` | Serialized data shape for one artifact type. |
| `ContentVersion` | User-visible linear revision of a template or mapping. |
| `ProjectVersion` | User-visible business revision of a project. |
| `StatusVersion` | Optimistic-concurrency counter for lifecycle changes. |
| `WorkflowVersion` | Version of a lifecycle/workflow definition. |
| `EventSchemaVersion` | Serialized event-envelope or payload format. |
| `AggregateVersion` | Ordered project event sequence. |

Technical schema versions remain primarily internal. Project, template, and mapping content versions are user-visible.

### Versioned artifact identity

Templates and mappings receive:

- immutable `ArtifactId`;
- technical `SchemaVersion`;
- user-visible integer `ContentVersion`.

Projects retain their immutable `ProjectId` and add a user-visible integer `ProjectVersion`.

### Linear integer revisions

User-visible revisions are monotonically increasing integers:

```text
1 -> 2 -> 3 -> 4
```

Semantic versioning is not used for business/content revision because the revision history is linear and user-facing.

### Immutable revision history

A rollback does not decrease or reuse a revision number.

If version 5 is current and the user restores the content of version 3, RenderKit creates version 6:

```text
1 -> 2 -> 3 -> 4 -> 5 -> 6
                         ^
                   content based on 3
```

Revision metadata records:

- artifact ID;
- new content version;
- base version;
- change type;
- timestamp;
- actor;
- optional reason.

Older revisions remain immutable.

### Schema catalog

A central trusted schema catalog defines, per artifact type:

- current schema version;
- minimum readable version;
- minimum writable version;
- supported migration steps.

Initial artifact types include:

- Config
- Registry
- Project
- Template
- Mapping
- Workflow
- Event
- Outbox

Hard-coded compatibility lists in individual services are replaced by this catalog over time.

### Compatibility outcomes

Schema checks return one of:

- `Current`
- `Readable`
- `UpgradeAvailable`
- `UpgradeRequired`
- `UnsupportedFutureVersion`

An older engine may read a newer artifact only when compatibility is explicitly declared. It must never write an unsupported future schema.

### Migration model

Migrations are explicit directed steps:

```text
Project 1 -> 2 -> 3
Template 1 -> 2
Mapping 1 -> 2
```

Each step:

1. validates the source schema;
2. creates a recovery backup;
3. transforms data;
4. sets the target schema;
5. validates the target;
6. atomically commits;
7. records a migration result.

Migration implementations are trusted module code. Artifact files never contain executable migration scripts.

### Upgrade policy

Default policy:

| Artifact | Policy |
|---|---|
| Config | Automatic with backup |
| Registry | Automatic with backup |
| Cache | Automatic rebuild |
| Project | Prompt or explicit policy |
| User template | Prompt |
| User mapping | Prompt |
| System template | Updated by module release |
| System mapping | Updated by module release |
| Event history | Prefer reader compatibility over rewriting |
| Outbox | Automatic with backup |

A global rollout migrates reachable registered projects and marks unreachable projects as pending. It does not fail the complete rollout because one project is offline.

### System and user artifacts

System templates and mappings are immutable installed resources and are updated only through a RenderKit release.

User templates and mappings are user-owned artifacts. Their migrations require backup, validation, and the configured upgrade policy. System resources never silently overwrite same-named user resources.

## Consequences

### Positive

- User-visible rollback has a clear linear history.
- Technical compatibility is independent of business revision.
- Global upgrade plans can be generated safely.
- Older engines cannot corrupt newer artifacts.

### Costs

- Revision storage and retention are required.
- Every artifact type needs schema validation.
- Migrations must remain available for supported upgrade paths.

## Public API boundary

Upgrade planning, upgrade execution, and artifact-version inspection are intended for later public exposure. Exact exported command names remain a product-owner decision.
