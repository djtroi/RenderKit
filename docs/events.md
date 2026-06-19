# Domain events

RenderKit now has an internal domain-event foundation for future automation,
background jobs, GUI notifications, cloud synchronization, and workflow triggers.

The event store is internal module state. No public event cmdlet is introduced in
this phase.

## Storage

Events are stored in `Events.json` below the platform-specific state root. With
`RENDERKIT_HOME`, the path is:

```text
$RENDERKIT_HOME/state/Events.json
```

The event store is governed by the `EventStore` artifact version in
`src/Resources/Schemas/ArtifactVersions.psd1`. Event Store vNext uses schema
version `1.1` while remaining readable from `1.0` stores.

## Event model

Each event contains:

- event id and compatibility alias;
- event type and event schema version;
- aggregate type, aggregate id, and optional aggregate version;
- UTC occurrence timestamp;
- correlation and causation ids;
- optional actor context supplied by a host;
- category (`Domain`, `Operational`, `Diagnostic`, or `Security`);
- retention marker;
- processing status (`Pending`, `Processed`, or `Failed`);
- processing attempts and optional structured last error;
- reserved integrity fields; and
- structured `data` with a `payload` compatibility alias.

## Current producer

The initial producer is project lifecycle status changes. Same-status lifecycle
no-ops do not emit events.

## Safety model

Events are append-only intent records for internal automation. The vNext
envelope reserves actor, category, retention, processing, and integrity fields
for future broker, worker, history, and synchronization phases. Future
background processors must treat events as at-least-once signals and make
handlers idempotent.