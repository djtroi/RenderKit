# ADR-002: Project Lifecycle State Machine

- **Status:** Accepted
- **Date:** 2026-06-18
- **Decision owners:** RenderKit maintainers

## Context

RenderKit needs a project lifecycle that can drive future automation, reporting, GUI workflows, and state-dependent behavior. A free-form status string would not provide reliable transition rules, concurrency control, or event semantics.

Lifecycle state must remain distinct from technical availability, migration state, health, and background-job state.

## Decision

### Lifecycle statuses

The initial lifecycle contains:

| Status | Meaning | Terminal |
|---|---|---:|
| `Unknown` | A legacy or recovered project whose business state is not known. | No |
| `Draft` | A new project that has not entered active production. | No |
| `Active` | A project in active production. | No |
| `InReview` | A project in a review or feedback phase. | No |
| `Approved` | A project or defined project revision has been approved. | No |
| `Delivered` | A project or deliverable has been marked as delivered. | No |
| `Archived` | A project has completed its final archive workflow. | Yes |
| `Cancelled` | A project has been cancelled. | Yes |

`Unknown` is reserved for migration and recovery. New projects never start in `Unknown`, and the status does not trigger normal business automation until it is classified.

### Transition matrix

The accepted transitions are:

```text
Unknown   -> Draft, Active, InReview, Approved, Delivered, Archived, Cancelled
Draft     -> Active, Cancelled
Active    -> InReview, Archived, Cancelled
InReview  -> Active, Approved, Cancelled
Approved  -> Active, InReview, Delivered, Cancelled
Delivered -> Active, InReview, Approved, Archived
Archived  -> no transitions
Cancelled -> no transitions
```

`Archived` and `Cancelled` projects may be copied or cloned, but they may not be reactivated. The resulting copy is a new project identity.

A transition to the current status is a no-op:

- metadata is not changed;
- the lifecycle version is not incremented;
- no domain event is emitted;
- no automation is invoked.

### Declarative workflow definition

Status and transition rules are loaded from a versioned declarative workflow definition rather than being scattered through conditional statements.

The definition includes:

- stable status IDs;
- initial and terminal flags;
- allowed transitions;
- reason policies;
- trusted validator identifiers;
- optional required operation data.

Data files may reference only validators registered by trusted RenderKit code. They must never contain executable PowerShell or arbitrary script blocks.

### Lifecycle metadata

Project metadata stores the current state and optimistic-concurrency version:

```json
{
  "lifecycle": {
    "workflowId": "renderkit.default",
    "workflowVersion": 1,
    "status": "Active",
    "statusVersion": 3,
    "changedAtUtc": "2026-06-18T11:30:00Z",
    "changedBy": {
      "type": "System",
      "id": null,
      "name": "RenderKit"
    },
    "reason": {
      "code": "ImportMediaCompleted",
      "text": "At least one media file was imported successfully."
    }
  }
}
```

`statusVersion` is a monotonically increasing integer used for optimistic concurrency, cache freshness, and event ordering. It is independent of project revision and schema version.

### Actors

Status changes may be requested by:

- users;
- trusted RenderKit workflows;
- migrations;
- future declarative automation;
- future external integrations.

Every actor uses the same state machine. Internal workflows and integrations may not edit lifecycle fields directly.

### Reason policies

Each transition defines one of:

- `Forbidden`
- `Optional`
- `Required`
- `SystemGenerated`

Initial defaults include:

- successful media import: system-generated reason;
- cancellation: required reason;
- reverting an approved or delivered project: required reason;
- deletion override: required reason;
- archiving: system-generated completion reason plus optional user text.

Reasons use a stable code and optional human-readable text.

## Operation-specific lifecycle rules

### Project creation

New projects start in `Draft`.

### Media import

`Draft` becomes `Active` after at least one media file has been transferred successfully. Starting a scan, classifying files, or completing a run with no successful transfer does not activate the project.

### Project import

Import distinguishes:

- **Restore:** preserves project identity, lifecycle status, and business revision.
- **New import:** creates a new working identity and starts in `Active`.

### Copy or clone

A copy receives a new project ID. Its default status is `Active`. A caller may explicitly choose only:

- `Draft`
- `Active`

Source identity, status, and revision may be retained as provenance metadata.

### Backup and archive

A normal backup never changes lifecycle status.

Archiving is a multi-step workflow:

```text
archive requested
-> archive job created
-> archive produced and verified
-> status changed to Archived
-> ProjectArchived event emitted
```

The project is not committed to the terminal `Archived` state until the required archive has completed and passed verification.

### Delivery

Creating a delivery package does not itself set `Delivered`. Delivery completion requires an explicit business operation or configured workflow policy.

### Deletion

Normal deletion is allowed only for:

- `Archived`
- `Cancelled`

An explicit override may delete a project in any lifecycle status. The override requires:

- an explicit override option;
- a required reason;
- actor information;
- high-impact confirmation through `ShouldProcess`;
- no active mutating job, unless a separate force workflow first cancels and settles those jobs;
- a tombstone and removal event.

## Concurrency

Mutating lifecycle operations acquire a project-scoped lock and verify an expected `statusVersion`. A stale writer receives a structured concurrent-modification error and must reload the project.

## Extensibility

The initial lifecycle is built in, but the format is versioned so later workflow profiles may add statuses and transitions. Custom workflows must be validated, must not execute code from data files, and must define migration behavior before they replace an existing workflow version.

## Consequences

### Positive

- Status-dependent automation has deterministic rules.
- GUI and SaaS clients can display allowed actions.
- Terminal states are protected.
- Concurrent status changes cannot silently overwrite each other.

### Costs

- Status changes require a lifecycle service rather than direct property assignment.
- Workflow changes require migration and compatibility policies.
- Long-running transitions such as archive require job orchestration.

## Public API boundary

Capabilities to read status, request status changes, and list allowed transitions will be public. Exact exported PowerShell command names are decided separately by the product owner.