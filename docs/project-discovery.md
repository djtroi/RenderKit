# Project discovery and search index

RenderKit keeps two internal state artifacts to make project overview reads fast
while still allowing projects to exist outside the configured project root.

## State files

With `RENDERKIT_HOME` set, the files live below:

```text
$RENDERKIT_HOME/state/ProjectSearchIndex.json
$RENDERKIT_HOME/state/DiscoveredProjects.json
```

`ProjectSearchIndex.json` stores paths that are worth scanning. These entries are
hints, not projects. `DiscoveredProjects.json` stores validated project overview
entries that `Get-Project` can read without walking the file system.

## Search index

The search index records normalized absolute paths with metadata such as:

- entry kind (`CurrentProjectRoot`, `PreviousProjectRoot`, `ProjectPath`,
  `ProjectParentPath`, or `CustomPath`);
- source command or process;
- priority;
- recursive scan flag;
- enabled flag;
- last scan timestamp;
- last scan status and error; and
- hit count.

`Set-ProjectRoot` indexes the newly configured root as `CurrentProjectRoot` and,
when a previous root exists, keeps the old root as `PreviousProjectRoot`.
`New-Project` indexes explicitly supplied absolute project paths and their parent
folders after successful project creation.

## Discovery behavior

Internal discovery scans enabled search-index entries, detects project candidates
by finding `.renderkit` folders, and validates the project metadata before adding
or refreshing entries in `DiscoveredProjects.json`.

Validation requires:

- a `.renderkit/project.json` metadata file;
- readable JSON;
- `tool` set to `RenderKit`;
- a non-empty project id; and
- a non-empty project name.

Discovery records scan diagnostics for missing or scanned roots and skips
reparse points to avoid symlink/junction loops. Scans are bounded by maximum
depth and maximum directory count per root.

## Discovered project overview

Discovered project entries contain project identity, root path, metadata path,
availability, source commands/processes, validation status, conflict status, and
whether the project lives inside the configured project root. `Get-Project` reads
this overview by default.

## Conflict preparation

If multiple discovered roots claim the same project id, RenderKit marks the
entries with `DuplicateProjectId` and stores conflict details for a future
`Repair-Project` workflow. RenderKit does not silently choose one duplicate over
another.