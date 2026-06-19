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
`src/Resources/Schemas/ArtifactVersions.psd1`.

## Event model

Each event contains:

- event id;
- event type;
- aggregate type and aggregate id;
- UTC occurrence timestamp;
- correlation and causation ids;
- processing status (`Pending`, `Processed`, or `Failed`); and
- a structured payload.

## Current producer

The initial producer is project lifecycle status changes. Same-status lifecycle
no-ops do not emit events.

## Safety model

Events are append-only intent records for internal automation. Handlers are not
implemented in this phase. Future background processors must treat events as
at-least-once signals and make handlers idempotent.