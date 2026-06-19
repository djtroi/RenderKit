# Background jobs

RenderKit now has an internal job-store foundation for future asynchronous
workflows such as long-running delivery packaging, cloud upload, notifications,
maintenance, and event-driven automation.

No public job cmdlet is introduced in this phase.

## Storage

Jobs are stored in `Jobs.json` below the platform-specific state root. With
`RENDERKIT_HOME`, the path is:

```text
$RENDERKIT_HOME/state/Jobs.json
```

The job store is governed by the `JobStore` artifact version in
`src/Resources/Schemas/ArtifactVersions.psd1`. Job Store vNext uses schema
version `1.1` while remaining readable from `1.0` stores.

## Job model

Each job contains:

- job id;
- job type;
- job and payload schema versions;
- status (`Queued`, `Running`, `RetryScheduled`, `Succeeded`, `Failed`, or
  `Cancelled`);
- queue name and priority;
- UTC timestamps for creation, updates, start, completion, ownership, heartbeat,
  lease, retry, and cancellation;
- attempt counters;
- optional worker ownership and lease metadata;
- optional trigger event and correlation ids;
- optional requesting actor context supplied by a host;
- structured progress;
- optional structured last error;
- optional result; and
- a structured payload.


## Host-facing job operations

The internal engine facade now wraps durable job operations in `RenderKitResult`
envelopes for a future local broker. The reserved operations can:

- create jobs with host-supplied actor context;
- list and read job details;
- request cancellation;
- retry failed or retry-scheduled jobs;
- update structured progress; and
- mark jobs succeeded or failed with structured result/error data.

These operations remain internal and do not introduce public job cmdlets.

## Current scope

This phase provides durable internal queuing primitives only. The job model now
reserves broker- and GUI-ready fields for queue filtering, ownership, leases,
progress, retry scheduling, cancellation requests, structured errors, and host
actor context. Actual background worker lifecycle, event subscriptions, retry
scheduling policies, cancellation UX, GUI notifications, and cloud integrations
remain separate phases.

Future workers must treat jobs as at-least-once work items and make execution
idempotent.