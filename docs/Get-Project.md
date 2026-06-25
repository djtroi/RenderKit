# Get-Project

Lists projects from the RenderKit discovered project overview.

`Get-Project` is intentionally cheap by default: it reads the persisted
`DiscoveredProjects.json` overview and does not scan the file system. Use
`-Refresh` when you want RenderKit to run internal discovery from the project
search index before returning the table.

## Syntax

```powershell
Get-Project [-AvailableOnly] [-Refresh]
```

## Parameters

### `-AvailableOnly`

Returns only projects whose last discovered availability marker is `true` in the
discovered project overview. This parameter does not perform live path checks.

### `-Refresh`

Runs the internal project discovery service before output. Discovery reads the
internal project search index, looks for `.renderkit` project markers, validates
project metadata, updates scan diagnostics, and refreshes the discovered project
overview.

## Output

The command returns table-friendly project summary objects with these fields:

- `Name`
- `Id`
- `Available`
- `Version`
- `RootPath`
- `MetadataPath`
- `Location` (`ProjectRoot` or `CustomPath`)
- `IsInsideConfiguredProjectRoot`
- `ValidationStatus`
- `ConflictStatus`
- `UpdatedAtUtc`

## Examples

```powershell
Get-Project
```

Lists all projects currently present in the discovered project overview.

```powershell
Get-Project -AvailableOnly | Format-Table
```

Lists only projects marked available in the discovered project overview.

```powershell
Get-Project -Refresh
```

Runs internal discovery from indexed search roots and then lists the refreshed
project overview.

## Notes

The project overview is backed by RenderKit state, not by a public database API.
If a project appears with `Location` set to `CustomPath`, it was discovered or
created outside the currently configured project root. Duplicate project IDs are
surfaced through `ConflictStatus` so a future repair workflow can resolve them.