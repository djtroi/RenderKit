# Job workers

RenderKit now includes an internal job-worker foundation. Workers execute queued
jobs by resolving trusted in-module handlers for each job type.

No public worker cmdlet is introduced in this phase.

## Handler registry

Handlers are registered with trusted scriptblocks in module code plus safe
metadata such as handler id, version, description, payload schema, idempotency,
progress/cancellation support, and required capabilities. Job payloads remain
data only; persisted jobs do not contain executable code. The handler catalog
returns metadata for hosts without exposing executable scriptblocks.

The first default handler is `ProjectLifecycleAutomation`, registered as
`RenderKit.ProjectLifecycleAutomation`, which currently acts as a safe no-op
placeholder for future lifecycle automation.

## Execution model

The internal worker:

1. recovers stale running jobs whose leases have expired;
2. atomically starts a lease for a queued job for a worker id;
3. records worker ownership, claim time, heartbeat time, lease deadline, and
   attempt count;
4. executes the registered handler;
5. marks the job `Succeeded` on success;
6. requeues failed jobs while retry attempts remain; and
7. marks the job `Failed` after the maximum attempts are exhausted.

Worker hosts can renew leases with heartbeat updates. If a worker process exits
without completing a job, a future worker tick can return the stale running job
to `Queued` so it can be claimed again.

## Current scope

This phase provides trusted local execution primitives plus local worker
ownership, lease, heartbeat, stale recovery, handler catalog metadata, and one-shot worker tick behavior.
Scheduling policies, parallel worker orchestration, cancellation UX,
notifications, cloud uploads, and GUI-visible job administration remain separate
phases.