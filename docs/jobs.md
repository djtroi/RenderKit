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
`src/Resources/Schemas/ArtifactVersions.psd1`.

## Job model

Each job contains:

- job id;
- job type;
- status (`Queued`, `Running`, `Succeeded`, `Failed`, or `Cancelled`);
- UTC timestamps for creation, updates, start, and completion;
- attempt counters;
- optional trigger event and correlation ids;
- optional last error; and
- a structured payload.

## Current scope

This phase provides durable internal queuing primitives only. Actual background
workers, event subscriptions, retry scheduling, cancellation, GUI notifications,
and cloud integrations remain separate phases.

Future workers must treat jobs as at-least-once work items and make execution
idempotent.