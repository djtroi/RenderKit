# Artifact versioning

RenderKit keeps user-facing project versions separate from technical artifact
schema versions. The technical versions protect compatibility for persisted
projects, templates, mappings, registries, and manifests.

## Central policy

`src/Resources/Schemas/ArtifactVersions.psd1` is the authoritative catalog for
technical artifact versions. Each artifact declares:

- the version written by the current engine;
- the minimum and maximum readable versions; and
- the minimum and maximum writable versions.

The catalog is trusted module data. User-controlled files cannot register code
or modify migration behavior.

## Compatibility outcomes

The internal compatibility service returns one of these explicit states:

- `Current`: the artifact uses the current schema;
- `UpgradeAvailable`: it is safe to read and write, but a newer schema exists;
- `UpgradeRequired`: the current operation is not safe without migration; or
- `UnsupportedFutureVersion`: the artifact was created by a newer engine.

Future versions fail closed. RenderKit does not silently rewrite an artifact
whose schema it does not understand.

## Migrations

Migration functions are registered only by trusted module code. The migration
planner uses registered forward-only edges and selects the shortest available
path. Phase 3 provides registration and planning primitives; automatic
migration execution and rollout orchestration remain separate, explicit
features.

The initial runtime integration validates templates and mappings on read and
before write. No new public cmdlet is introduced by this foundation.
