# ADR-003: Domain Events, Durable Jobs, and Automation

- **Status:** Accepted
- **Date:** 2026-06-18
- **Decision owners:** RenderKit maintainers

## Context

RenderKit needs to react to project lifecycle changes and long-running work. A representative scenario is generating a large delivery package in the background, allowing the user to continue working, then uploading or moving the result and notifying the user after completion.

In-process PowerShell events, runspaces, and background jobs are not a reliable durable architecture because they normally end with the hosting PowerShell process. RenderKit is intended to become a stateless engine used by a GUI, local worker, or SaaS host.

## Decision

### Commands, jobs, and events are distinct

- A **command** expresses an intention and may fail.
- A **job** tracks durable execution of long-running work.
- A **domain event** records a fact that has already occurred.

Example:

```text
Create delivery command
-> durable delivery job
-> worker creates and verifies package
-> DeliveryPackageCreated event
-> upload/move handler
-> notification handler
```

An event does not detect job completion. The worker that successfully commits the result emits the completion event.

### Current state plus event history

RenderKit does not initially use full event sourcing.

- `.renderkit/project.json` stores current authoritative project state.
- a project-local append-oriented event history stores business history;
- a durable outbox stores events awaiting handler processing;
- operational logs remain diagnostic data.

Normal project reads do not replay the complete event history.

### Event envelope

Every event uses a versioned envelope:

```json
{
  "eventId": "e83286c4-b87e-48a4-9b50-f912f3260683",
  "eventType": "ProjectStatusChanged",
  "eventSchemaVersion": 1,
  "occurredAtUtc": "2026-06-18T11:30:00Z",
  "aggregateType": "Project",
  "aggregateId": "1b26912d-c989-46d3-9d0d-e21cddcc86ee",
  "aggregateVersion": 3,
  "correlationId": "947e3eba-99df-42cc-8185-a9de97ec9401",
  "causationId": null,
  "actor": {
    "type": "User",
    "id": null,
    "name": "alice"
  },
  "data": {},
  "integrity": {
    "algorithm": null,
    "previousHash": null,
    "hash": null
  }
}
```

Event IDs provide deduplication. Correlation and causation IDs provide workflow tracing and loop detection. Aggregate versions provide ordering.

### Initial event types

The first event catalog includes:

- `ProjectCreated`
- `ProjectRegistered`
- `ProjectImported`
- `ProjectCopied`
- `ProjectRenamed`
- `ProjectMoved`
- `ProjectStatusChanged`
- `ProjectArchived`
- `ProjectRemoved`
- `ProjectBackupCompleted`
- `ProjectBackupFailed`
- `DeliveryJobCompleted`
- `DeliveryJobFailed`

Specialized events may be added only when they provide a stable contract beyond filtering a generic event.

### Event categories and retention

Events are categorized as:

- `Domain`
- `Operational`
- `Diagnostic`
- `Security`

Domain events are retained with the project indefinitely. Operational and diagnostic retention is configurable. Diagnostic events are excluded from exports by default. Security events use a separate retention policy and are not treated as disposable debug output.

### Project-local history

The default history location is:

```text
<ProjectRoot>/.renderkit/events/events.jsonl
```

JSON Lines allows append-oriented storage, streaming reads, and recovery when the last record is incomplete.

Imported historical events are inert history. They are never automatically added to the active outbox and never re-trigger automation.

When a project is copied:

- the new project starts a new active history;
- it emits `ProjectCreatedFromCopy` or equivalent provenance data;
- source history may optionally be included as read-only provenance;
- source events are not rewritten to the new project ID.

### Outbox

The state storage contains durable outbox areas:

```text
outbox/pending
outbox/processed
outbox/dead-letter
```

Handlers are at-least-once consumers and must be idempotent. The idempotency key is based on event ID and handler ID.

After a configurable retry limit, failed processing moves to dead letter with attempt count, handler ID, last error, and timestamps.

### Handler behavior

Critical consistency work is synchronous:

- authoritative project state;
- registry cache consistency;
- durable event/outbox creation.

Secondary effects are normally asynchronous:

- uploads;
- notifications;
- remote integrations;
- expensive validation;
- nonessential report generation.

A secondary-handler failure does not roll back an already committed business state. It records technical health, schedules retry, and may eventually dead-letter.

Handlers may request project changes only by submitting a command through the lifecycle or application service. They may not mutate metadata directly.

### Loop prevention

Automation propagates correlation and causation IDs and enforces:

- event-ID deduplication;
- no-op status transitions;
- maximum command/event depth;
- idempotent handlers;
- explicit permission for handlers that may submit state-changing commands.

### Durable jobs

Initial job states are:

- `Pending`
- `Running`
- `Succeeded`
- `Failed`
- `Cancelled`
- `RetryScheduled`

Job state is technical execution state and is separate from project lifecycle.

Workers claim jobs atomically and use a lease or equivalent ownership mechanism. Long-running jobs persist progress and can recover from process termination.

### Engine and host separation

The RenderKit PowerShell module is a request-oriented engine. It can:

- validate and submit jobs;
- claim and execute one unit of work;
- persist progress and results;
- emit events;
- process outbox entries;
- return structured results.

A durable host is responsible for process lifetime:

- GUI process;
- separate local worker;
- Windows service;
- systemd user service;
- macOS LaunchAgent;
- container worker;
- SaaS worker.

The core engine never assumes that an imported PowerShell module will remain running.

### Workflow automation

Future user workflows are declarative and suitable for a visual editor. Workflow data may select registered triggers, conditions, and allow-listed actions, but it may not contain arbitrary executable PowerShell.

Credentials are referenced through a secure credential provider and are never embedded in workflow documents.

## Consequences

### Positive

- Long-running work survives GUI and shell lifetimes.
- Events support reliable automation and history.
- The same engine can run locally or in SaaS workers.
- Failures can be retried without reverting successful business state.

### Costs

- Persistent job, event, and idempotency stores are required.
- Workers require ownership, retry, and cancellation semantics.
- At-least-once delivery requires handler discipline.

## Public API boundary

Project history will be publicly queryable. Job, pending-event, dead-letter, retry, and workflow-management capabilities are planned for later public exposure.

All exported PowerShell command names require separate product-owner approval.