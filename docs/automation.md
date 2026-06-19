# Event-to-job automation

RenderKit now includes an internal bridge that converts pending domain events
into durable background jobs through declarative subscriptions.

No public automation cmdlet is introduced in this phase.

## Subscription catalog

Subscriptions are stored as trusted module data in:

```text
src/Resources/Automation/EventJobSubscriptions.psd1
```

The initial subscription maps `ProjectLifecycleStatusChanged` events to
`ProjectLifecycleAutomation` jobs. This keeps the mapping extensible without
hard-coding event/job pairs inside project commands.

## Bridge behavior

The internal bridge:

1. reads pending domain events;
2. resolves enabled matching subscriptions;
3. creates a durable queued job per matching subscription;
4. avoids duplicate jobs for the same event and job type; and
5. marks handled events as processed.

## Current scope

This phase wires events to jobs only. It does not execute jobs, retry failed
work, subscribe external integrations, or expose public cmdlets. Those remain
separate phases.