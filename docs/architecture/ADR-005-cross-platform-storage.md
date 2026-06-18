# ADR-005: Cross-Platform Storage and Path Handling

- **Status:** Accepted
- **Date:** 2026-06-18
- **Decision owners:** RenderKit maintainers

## Context

RenderKit supports Windows PowerShell and PowerShell Core and is intended to run on Windows, Linux, and macOS. Persistent application data cannot rely directly on `%APPDATA%`, Windows drive letters, backslashes, or one universal case-sensitivity rule.

The project registry, configuration, cache, outbox, migration state, and future job state need stable semantic storage locations.

## Decision

### Central storage service

All engine components obtain paths through a central storage service. Public commands and domain services must not read platform environment variables directly.

Semantic storage kinds are:

- `Configuration`
- `State`
- `Cache`
- `UserData`

The service provides child paths for config, registry, jobs, outbox, logs, user templates, user mappings, and migration state.

### Location precedence

Location selection follows:

1. explicit RenderKit test/portable override;
2. explicitly configured XDG environment variable where applicable;
3. native platform convention;
4. safe user-home fallback.

An environment variable such as `RENDERKIT_HOME` may redirect all user storage for tests, CI, sandboxing, and portable installations.

### Default platform locations

#### Windows

```text
Configuration: %APPDATA%\RenderKit
State:         %LOCALAPPDATA%\RenderKit
Cache:         %LOCALAPPDATA%\RenderKit\cache
```

#### Linux

```text
Configuration: ${XDG_CONFIG_HOME:-$HOME/.config}/renderkit
State:         ${XDG_STATE_HOME:-$HOME/.local/state}/renderkit
Cache:         ${XDG_CACHE_HOME:-$HOME/.cache}/renderkit
```

#### macOS

Explicit XDG variables are respected when supplied. Otherwise:

```text
Configuration/State: $HOME/Library/Application Support/RenderKit
Cache:               $HOME/Library/Caches/RenderKit
```

### Data classification

- Configuration stores user choices and policy.
- State stores the local registry, outbox, jobs, tombstones, and migration state.
- Cache stores reconstructable indexes and scan results.
- Project-owned portable state remains under `<ProjectRoot>/.renderkit`.

Absolute project paths are stored only in machine-local state, not as authoritative project metadata.

### Path representation

- Registry root paths are absolute and use native platform representation.
- Portable relative paths in manifests, archives, templates, and mappings use `/`.
- Relative paths are never persisted as registry roots.
- Display paths are kept separately from comparison keys.
- Project ID remains the final identity check.

### Case sensitivity

Logical project names use ordinal case-insensitive comparison on all platforms.

Physical paths do not use unconditional lowercase normalization:

- Windows is usually case-insensitive;
- Linux is usually case-sensitive;
- macOS volume behavior varies.

Path comparison is centralized and conservative. String equality is never sufficient to prove project identity.

### Path safety

The path service validates:

- absolute versus relative input;
- `.` and `..` traversal;
- invalid file names;
- reserved Windows names where relevant;
- directory separators in project names;
- symbolic links and reparse points;
- path containment for extraction and copy operations;
- inaccessible or unavailable volumes.

Symbolic links are not followed during broad repair scans by default.

### Atomic persistence

Persistent JSON writes use:

1. an exclusive file lock with timeout;
2. reload inside the lock;
3. a temporary file in the destination directory;
4. flush and close;
5. parse/schema validation of the temporary file;
6. backup of the last valid file;
7. same-file-system rename or platform-safe replacement;
8. lock release in `finally`.

The implementation must provide a fallback when one platform or file system does not support a preferred replacement primitive.

### Permissions

Storage uses the current user's private application directories and never requires administrator/root privileges.

On Unix-like systems, state directories should use user-only permissions where supported. Compatibility with Windows PowerShell 5.1 means optional APIs must be feature-detected rather than called unconditionally.

### Network and provider storage

Local file paths, NAS/SAN paths, and future cloud/object storage have different capabilities. The engine therefore models provider operations rather than assuming every backend supports:

- atomic rename;
- operating-system trash;
- file locks;
- directories;
- case-insensitive paths.

Deletion modes may include:

- `Trash`
- `SoftDelete`
- `Archive`
- `Permanent`
- `ProviderDefault`

## Consequences

### Positive

- Registry and engine state work consistently on all supported platforms.
- CI can isolate state with one override.
- Future storage providers can be added without changing domain rules.
- Portable project metadata does not become tied to one machine path.

### Costs

- Path behavior must be tested per platform.
- Atomic-write and locking fallbacks are required.
- Some storage providers need capability-specific implementations.