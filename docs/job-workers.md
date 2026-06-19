# Job workers

RenderKit now includes an internal job-worker foundation. Workers execute queued
jobs by resolving trusted in-module handlers for each job type.

No public worker cmdlet is introduced in this phase.

## Handler registry

Handlers are registered with trusted scriptblocks in module code. Job payloads
remain data only; persisted jobs do not contain executable code.

The first default handler is `ProjectLifecycleAutomation`, which currently acts
as a safe no-op placeholder for future lifecycle automation.

## Execution model

The internal worker:

1. resolves a queued job;
2. marks it `Running` and increments attempts;
3. executes the registered handler;
4. marks the job `Succeeded` on success;
5. requeues failed jobs while retry attempts remain; and
6. marks the job `Failed` after the maximum attempts are exhausted.

## Current scope

This phase provides trusted local execution primitives only. Scheduling,
parallel workers, cancellation UX, notifications, cloud uploads, and GUI-visible
job status remain separate phases.