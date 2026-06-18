# ADR-001: Project Identity and Local Registry

- **Status:** Accepted
- **Date:** 2026-06-18
- **Decision owners:** RenderKit maintainers

## Context

RenderKit projects may be created at arbitrary file-system locations. Existing commands can often resolve a project only by combining a project name with an explicitly supplied path or the configured default project root. This limits automation because commands such as export, delivery, backup, rename, and removal cannot reliably locate every project by name.

RenderKit also needs to support Windows, Linux, and macOS, removable media, local volumes, NAS/SAN paths, and future cloud-backed project catalogs.

## Decision

### Project identity

Every project has an immutable GUID named `ProjectId`. The ID, not the project name or path, is the authoritative identity.

- Rename and move operations preserve the ID.
- Restore operations preserve the ID when they restore the same project identity.
- Copy and clone operations create a new ID.
- A manually copied folder that duplicates an existing ID creates an identity conflict.
- RenderKit never resolves a duplicate-ID conflict by timestamps, path order, or other heuristics.
- A user must decide which copy keeps the original identity and whether another copy receives a new identity.

### Project names

Project names are mutable display attributes.

- Duplicate names are allowed.
- Logical name comparison is case-insensitive on every platform and uses ordinal semantics.
- Original casing is preserved for display.
- If a name resolves to multiple registered projects, name-only resolution fails and requires a project ID or explicit path.
- File-system path comparison remains platform and volume aware; logical project-name comparison must not be reused for physical path comparison.

### Sources of authority

The project-local metadata file remains authoritative:

```text
<ProjectRoot>/.renderkit/project.json
```

It owns the project ID, name, lifecycle state, project revision, schema version, and other portable project metadata.

The local registry is a machine-local index and cache. It stores:

- project ID;
- last known name;
- absolute native root path;
- cached project schema and lifecycle information;
- availability;
- registration and last-seen timestamps.

Every resolved registry entry must be verified against the project-local metadata before it is trusted.

### Registry scope

The registry is:

- per user;
- local to one machine;
- stored through the cross-platform storage service;
- not automatically synchronized between machines.

A future cloud project catalog is a separate abstraction. It may store tenant-visible identity, permissions, and business metadata, but it must not replace the machine-local path registry.

### Automatic registration

Automatic registration of an explicitly supplied valid project path is configurable and enabled by default.

Registration occurs only after:

1. canonical path resolution;
2. directory existence validation;
3. successful metadata parsing;
4. supported-schema validation;
5. confirmation that the metadata belongs to RenderKit;
6. valid project-ID validation;
7. duplicate-ID and path-conflict checks.

### Availability

Registry availability is technical state and is separate from project lifecycle status.

Initial availability values are:

- `Available`
- `Unavailable`
- `MetadataMissing`
- `MetadataInvalid`
- `IdentityMismatch`

An unavailable project remains registered because removable media, network storage, or mounted volumes may become available again.

### Tombstones

General manual deregistration is not supported.

A tombstone may replace an active registry entry when:

- RenderKit physically deletes the project; or
- a repair/cleanup operation explicitly confirms that a long-term missing project should be retired.

A tombstone retains, at minimum, the project ID, last known name and lifecycle status, removal timestamp, actor, and reason.

## Resolution order

The internal resolver uses deterministic precedence:

1. explicit project root;
2. explicit project ID;
3. project name through the registry;
4. explicit legacy base path;
5. configured default project root as a compatibility fallback.

An explicit path is never silently replaced by a registry path.

## Repair behavior

Repair follows a plan/apply workflow:

```text
Discover -> Validate -> Correlate by ProjectId -> Build Plan -> Apply -> Verify
```

Search behavior:

- configured project roots are searched by default;
- callers may add explicit search roots;
- a separate explicit high-cost mode may scan suitable local volumes;
- remote and network paths are searched only when explicitly supplied;
- symbolic links are not followed by default;
- virtual file systems and unsafe roots are excluded;
- discovery never mutates the registry directly.

Valid unregistered projects are included in the repair plan and are registered during the apply phase. A project found at a new path updates the registry only when the caller explicitly applies recovered locations.

If one project ID is found at multiple paths, repair reports `DuplicateProjectIdentity` and takes no automatic action.

## Security requirements

- Registry paths are untrusted input and are always revalidated.
- The metadata project ID must equal the registry project ID.
- Project names must not permit path traversal or absolute-path injection.
- Writes require locking, atomic replacement, validation, and recovery backups.
- Registry files must use user-private permissions where the platform supports them.
- Registry files must not contain credentials or secrets.
- Unknown future schemas are never overwritten by an older engine.

## Consequences

### Positive

- Commands can locate projects without requiring paths in normal cases.
- Renames and moves do not change project identity.
- Repair can recover externally moved projects safely.
- The design supports future GUI and cloud catalogs without coupling local paths to cloud identity.

### Costs

- Name-only resolution may require ambiguity errors.
- Registry writes need concurrency control and recovery.
- Duplicate IDs require an explicit user decision.
- A separate repair and cleanup lifecycle is required.

## Public API boundary

The capabilities to list, explicitly register, repair, and validate registered projects will be public. Project resolution remains an internal shared service used by public commands.

All exported PowerShell command names remain subject to explicit product-owner approval and are not defined by this ADR.