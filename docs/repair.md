# Repair and health checks

RenderKit now has an internal repair foundation for storage and durable engine
state.

No public repair cmdlet is introduced in this phase.

## Scope

The internal repair service checks:

- semantic storage roots;
- project registry readability;
- project registry entries against the filesystem;
- event store readability; and
- job store readability.

It can optionally attempt JSON backup restoration for corrupted stores when the
caller enables restore mode.

## Safety model

Repair treats durable state as recoverable metadata, not as authority. Project
registry repair reconciles entries with the filesystem and marks missing project
paths as not existing. It does not delete user projects.

Future public repair commands should provide clear dry-run and confirmation
semantics before making destructive changes.