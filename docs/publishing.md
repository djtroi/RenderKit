# Publishing schedule

RenderKit 1.1.0 stores planned publications in the versioned
`PublishingSchedule` artifact. Records have stable GUIDs, UTC timestamps, an
explicit display time zone, snapshots of related names, and an integer
revision for optimistic concurrency.

## Create and query publications

```powershell
$publication = New-RenderKitPublication `
    -Title 'Launch trailer' `
    -Status Scheduled `
    -StartUtc '2026-08-01T16:00:00+00:00' `
    -TimeZone 'Europe/Berlin' `
    -ProjectId 'd876bd0a-9234-45c1-9dc9-86f5ccbaba20' `
    -ProjectNameSnapshot 'Launch Campaign' `
    -ChannelProvider YouTube

Get-RenderKitPublication -Id $publication.id
Get-RenderKitPublication `
    -FromUtc '2026-08-01T00:00:00+00:00' `
    -ToUtc '2026-09-01T00:00:00+00:00' `
    -Status Scheduled
```

`StartUtc`, `EndUtc`, and range boundaries require ISO-8601 values with an
explicit `Z` or numeric offset. Range queries use overlap semantics: a record
is returned when its interval overlaps the requested half-open range.

## Update safely

```powershell
$current = Get-RenderKitPublication -Id $publication.id
Set-RenderKitPublication `
    -Id $current.id `
    -ExpectedRevision $current.revision `
    -Status Publishing
```

Always send the revision that was read. A stale revision fails instead of
overwriting another writer. Status transitions are constrained:

- `Draft` can become `Scheduled` or `Cancelled`;
- `Scheduled` can return to `Draft`, start `Publishing`, or be cancelled;
- `Publishing` can become `Published` or `Failed`;
- `Failed` can be scheduled again or cancelled;
- `Published` and `Cancelled` are terminal.

Publication records reference project and client IDs explicitly. Snapshot
names preserve display context but do not create or update project/client
records. `Set-RenderKitPublication` supports `-WhatIf` and `-Confirm`.

