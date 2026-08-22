# Job workers

RenderKit includes a job-worker foundation for trusted local execution. Workers
execute queued jobs by resolving trusted in-module handlers for each job type.
The public `Start-RenderKitJobWorker` cmdlet hosts that execution locally while
higher-level products remain responsible for worker-pool orchestration.

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

A worker:

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

## Queue and targeted workers

Normal workers preserve the queue contract: priority is evaluated first and
jobs with the same priority are claimed in creation order.

```powershell
Start-RenderKitJobWorker -JobType BackupProject -QueueName backup -RunOnce
```

Orchestrators can bind a one-shot worker to a specific queued job by supplying
`-JobId` together with `-RunOnce`:

```powershell
Start-RenderKitJobWorker `
    -WorkerId 'worker-01' `
    -JobId $jobId `
    -JobType BackupProject `
    -QueueName backup `
    -RunOnce
```

A targeted worker only claims the requested job when its job type and queue
match. Other queued jobs remain untouched. Omitting `-JobId` keeps the existing
queue behavior unchanged.

## Product boundary

RenderKit owns the durable job model, handler execution, leases, heartbeats,
retries, progress, cancellation state, and worker identity. Products embedding
RenderKit can build worker discovery, process lifecycle, pool sizing,
capability-aware scheduling, and local or remote dispatch on top of these
primitives without changing the standalone command behavior.

The current scope is local execution. Distributed worker registration,
transport security, remote scheduling, and server-side fleet management remain
higher-level orchestration concerns.
