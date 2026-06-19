# Engine contracts for local hosts

RenderKit exposes internal contract primitives for a future local broker, worker
runtime, Electron desktop client, and SaaS-compatible host boundary. These
contracts keep authentication, roles, sessions, and transport concerns outside
the PowerShell engine while giving hosts stable metadata for requests and
responses.

No public cmdlet is introduced in this phase.

## Boundary

The RenderKit engine owns domain validation and durable state changes. A local
host or broker owns:

- users, roles, permissions, and sessions;
- local IPC such as named pipes or Unix domain sockets;
- worker process lifetime;
- GUI policy decisions;
- audit-log persistence outside domain events; and
- NLE adapter orchestration.

Hosts pass an actor and operation context into engine operations. The engine may
persist that context on future jobs and domain events, but it does not
authenticate users or calculate permissions.

## Result envelope

Every broker-facing engine operation should return a `RenderKitResult` shape:

- `success`;
- `data`;
- `warnings`;
- `error`;
- `correlationId`;
- `causationId`;
- `actor`; and
- `timestampUtc`.

Errors use a registered `RenderKitError` with a stable code, category, message,
optional details, and UTC occurrence timestamp.

## Initial error codes

The initial broker contract reserves these error codes:

- `RK_VALIDATION_FAILED`
- `RK_NOT_FOUND`
- `RK_CONFLICT`
- `RK_LOCK_TIMEOUT`
- `RK_STORAGE_UNAVAILABLE`
- `RK_SCHEMA_UNSUPPORTED`
- `RK_JOB_NOT_FOUND`
- `RK_JOB_INVALID_STATE`
- `RK_JOB_HANDLER_NOT_FOUND`
- `RK_OPERATION_CANCELLED`
- `RK_ACCESS_CONTEXT_MISSING`
- `RK_INTERNAL_ERROR`

## Actor context

The actor context is supplied by the host and may include:

- actor id;
- actor type (`User`, `System`, `Worker`, `Integration`, or `Service`);
- display name;
- source;
- a roles snapshot for diagnostics;
- session id;
- correlation id; and
- causation id.

Roles are diagnostic context only inside the engine. Authorization remains a
host responsibility.

## Operation context

The operation context wraps the actor, operation name, source, metadata,
correlation id, causation id, and creation timestamp. Mutating host-facing
operations should require an actor context before they call domain services.

## Initial facade catalog

The initial internal facade catalog reserves these broker-facing operation names:

- `GetRenderKitEngineContractSnapshot`
- `GetRenderKitEngineInfo`
- `GetRenderKitEngineState`
- `GetRenderKitProjectList`
- `GetRenderKitProjectDetail`
- `GetRenderKitJobList`
- `GetRenderKitJobDetail`
- `GetRenderKitJobHandlerCatalog`
- `NewRenderKitEngineJob`
- `RequestRenderKitEngineJobCancellation`
- `RetryRenderKitEngineJob`
- `UpdateRenderKitEngineJobProgress`
- `SetRenderKitEngineJobSucceeded`
- `SetRenderKitEngineJobFailed`
- `InvokeRenderKitWorkerTick`
- `GetRenderKitEventList`
- `GetRenderKitEventDetail`
- `InvokeRenderKitEventBridge`

The current module attaches these contracts to concrete job, worker, event,
engine-state, project read-model, and host-handoff operations.

## Engine and project read-model facade

The concrete read-model operations now expose engine capability metadata, state
health, project summaries, and project detail views through `RenderKitResult`
envelopes. These operations are designed for a local broker or Electron GUI and
do not require engine-side authorization; the host remains responsible for user
permissions and presentation policy.

## Job operation facade

The first concrete facade operations wrap durable job creation, reads,
cancellation requests, retry requests, progress updates, and terminal success or
failure updates in `RenderKitResult` envelopes. Mutating operations accept an
actor context supplied by the local broker and persist that actor on job request
metadata where appropriate.

## Event operation facade

The event facade wraps event history reads and event-to-job bridge invocation in
`RenderKitResult` envelopes. Event reads are non-mutating and support the same
filters as the internal event store. Bridge invocation is mutating, requires an
actor context from the host, and returns processed event ids plus created job
metadata for GUI or worker-runtime reconciliation.

## Host handoff contract snapshot

`GetRenderKitEngineContractSnapshot` returns a machine-readable contract bundle
for a local broker or separate Electron repository. It includes the host/engine
boundary, active event/job schema versions, result-envelope fields, actor-context
fields, facade operations, stable error codes, and handoff notes. The snapshot is
read-only and intentionally keeps users, roles, sessions, transport, and audit
policy assigned to the host runtime rather than the PowerShell engine.