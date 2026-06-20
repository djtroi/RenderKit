# Get-Project

Lists the projects known to the RenderKit project registry.

RenderKit already keeps a system-wide project registry in the state storage
root. `Get-Project` exposes that registry as a public command so users can see
which projects RenderKit knows about without providing a project path.

## Syntax

```powershell
Get-Project [-AvailableOnly] [-Refresh]
```

## Parameters

### `-AvailableOnly`

Returns only projects whose registered root path currently exists.

### `-Refresh`

Rechecks all registered project root paths before output and persists the
updated availability markers in the registry.

## Output

The command returns table-friendly project summary objects with these fields:

- `Name`
- `Id`
- `Available`
- `Version`
- `RootPath`
- `MetadataPath`
- `UpdatedAtUtc`

## Examples

```powershell
Get-Project
```

Lists all projects known to RenderKit, including unavailable projects on
disconnected drives or offline shares.

```powershell
Get-Project -AvailableOnly | Format-Table
```

Lists only currently available projects in table form.

```powershell
Get-Project -Refresh
```

Refreshes availability markers before listing projects.