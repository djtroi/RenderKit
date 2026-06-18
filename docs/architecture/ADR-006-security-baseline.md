# ADR-006: Local Engine Security Baseline

- **Status:** Accepted
- **Date:** 2026-06-18
- **Decision owners:** RenderKit maintainers

## Context

RenderKit is intended to become a commercial engine used by a local GUI and potentially by SaaS workers. It processes untrusted paths, project packages, metadata, workflows, registry state, remote integrations, and large media files.

Formal compliance certification is not an immediate requirement. ISO 27001 may become a later organizational goal, so the initial architecture must avoid preventable security debt.

## Decision

RenderKit adopts a commercial defense-in-depth baseline for the local engine without claiming formal regulatory or ISO certification.

### Data is never executable code

RenderKit does not execute PowerShell, script blocks, expressions, or migration scripts loaded from:

- projects;
- templates;
- mappings;
- workflows;
- events;
- registry files;
- imported packages.

Declarative documents may reference allow-listed action or validator IDs implemented by trusted installed code.

### Input and path validation

- All external input is validated at service boundaries.
- Literal paths are used for file-system operations.
- Project names cannot inject absolute paths or traversal.
- Archive extraction prevents zip-slip/path-escape attacks.
- Relative paths are normalized and verified to remain within the intended root.
- Symbolic links and reparse points receive explicit handling for destructive operations.
- Input files, JSON depth, record counts, and payload sizes use reasonable limits.

### Identity validation

- Registry entries are untrusted caches.
- Project-local metadata is re-read before mutation.
- Registry and metadata project IDs must match.
- Name and path equality never replace ID validation.
- Unknown future schemas are never overwritten.

### Persistence and concurrency

- State writes are atomic and validated.
- File locks have bounded timeouts.
- Project lifecycle uses optimistic concurrency.
- Recovery backups preserve the last valid state.
- Partial or corrupt files are not silently replaced with empty defaults.

### Permissions and secrets

- User state is stored in user-private locations.
- RenderKit does not require elevated privileges for normal operation.
- Config, registry, projects, events, and workflows do not contain credentials.
- Credentials are accessed through an abstract secure credential provider.
- Logs and telemetry do not expose credentials or tokens.
- Absolute paths are included in normal logs only when operationally necessary and in debug logs only when debug output is enabled.

### Network behavior

- The local engine performs no implicit network access.
- Remote calls require an explicit configured provider or workflow.
- Timeouts, retry limits, and cancellation are mandatory.
- TLS certificate validation is not disabled.
- Remote responses are treated as untrusted input.

### Events, jobs, and workflows

- Event handlers are allow-listed and versioned.
- Handlers are idempotent.
- Imported historical events never trigger active automation.
- Correlation and causation IDs support loop detection.
- Retry exhaustion moves work to dead letter.
- Job ownership prevents multiple workers from silently committing the same result.
- Workflow files cannot embed arbitrary code or plaintext credentials.

### Import, export, and integrity

- Import validates manifest schema and safe relative paths before extraction.
- Hash verification is available for project content and resources.
- Portable exports exclude absolute paths by default.
- Event history is designed to support future hash chaining.
- Formal signatures may be added later but are not part of the initial baseline.

### Actor and audit context

Mutating operations support structured context:

- actor type;
- actor ID when available;
- display name when policy permits;
- UTC timestamp;
- RenderKit version;
- correlation/request ID;
- reason code and text where applicable.

Machine name and other personal or infrastructure data are not recorded by default unless required by configured diagnostics or a future compliance policy.

### GUI and SaaS boundary

Authentication and user management may be implemented by a future GUI or SaaS host, but authorization cannot rely only on UI hiding.

The engine boundary is designed to accept an authorization/actor context so a host can enforce:

- tenant isolation;
- permissions;
- least privilege;
- request traceability.

Server-side systems additionally require secure transport, encryption at rest, secret management, rate limiting, tenant isolation, and supply-chain controls. Those controls are outside the initial local-engine implementation but must not be blocked by its data model.

### Supply chain

Future commercial distribution should include:

- signed releases;
- dependency review;
- reproducible or controlled builds where practical;
- vulnerability scanning;
- protected release credentials;
- update authenticity verification.

## Deferred compliance

ISO 27001 may be considered later. It is an organizational information-security management system, not a feature that the module can implement by itself.

The initial design preserves useful foundations:

- structured security events;
- actor and operation IDs;
- controlled secrets;
- documented security defaults;
- clear trust boundaries;
- migration and retention policies.

## Consequences

### Positive

- High-risk code-execution and path attacks are addressed early.
- Local, GUI, and SaaS deployments can share secure domain behavior.
- Future compliance work is not blocked by opaque state or missing identity.

### Costs

- Providers and workflows require validation and allow-listing.
- Security-sensitive operations need more structured context and tests.
- Some convenience behaviors, such as implicit network access or arbitrary scripts, are intentionally disallowed.