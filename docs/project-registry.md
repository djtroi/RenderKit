# Project registry

RenderKit stores an internal project registry in the state storage root. The
registry lets internal services resolve a project by name even when the project
was created outside the configured default project root.

The registry is not a public database API. It is an implementation detail used
by the engine to support future path-free workflows such as delivery, export,
backup, repair, status, and event automation.

## Location

The registry is stored as `Projects.json` below the platform-specific state
root. When `RENDERKIT_HOME` is set, the registry lives at:

```text
$RENDERKIT_HOME/state/Projects.json
```

## Schema

The registry uses technical artifact version `ProjectRegistry` from
`src/Resources/Schemas/ArtifactVersions.psd1`. Entries contain:

- project id;
- project name;
- absolute root path;
- optional user-facing project version;
- metadata file path;
- existence marker; and
- last update timestamp.

## Update points

The registry is updated internally after project create, copy, rename, lookup,
and removal operations. Users do not manually deregister projects. Stale entries
are handled by the internal repair service, which marks missing paths rather
than trusting registry data blindly.

## Safety

Registry entries are hints, not authority. RenderKit still validates that the
referenced folder exists and that the project metadata is valid before returning
a project from the resolver.