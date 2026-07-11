# Client registry

RenderKit owns one global client registry below the active state root. Studio,
the broker, the CLI, and future hosts therefore resolve the same stable client
IDs. Projects and free-text metadata never create client records implicitly.

## Storage and lifecycle

The versioned `ClientRegistry` artifact is stored as `Clients.json` below the
active `RENDERKIT_HOME`. A missing file represents an empty registry. Writes
use the shared transaction lock, schema validation, atomic replacement, and
backup behavior.

Clients have a generated GUID, a display name, an `Active`, `Inactive`, or
`Archived` status, timestamps, and an integer revision. Optional legal name,
tags, notes, contacts, addresses, consent, and retention fields are bounded and
validated. Archive is the supported removal behavior; permanent deletion and
bulk mutation are intentionally unavailable.

Contact details, addresses, and notes are personal data. They are returned only
by detail reads, not list summaries, and must not be copied into normal logs or
support summaries. Local JSON storage is not described as encrypted.

## PowerShell commands

```powershell
$client = New-RenderKitClient `
    -DisplayName 'Example Studio' `
    -Tags @('priority')

Get-RenderKitClient
Get-RenderKitClient -Search 'Example' -Status Active
Get-RenderKitClient -Id $client.id

Set-RenderKitClient `
    -Id $client.id `
    -ExpectedRevision $client.revision `
    -Status Archived
```

`Set-RenderKitClient` uses optimistic concurrency. Callers must send the
revision they read; a stale revision fails rather than overwriting a newer
record.

## Host operations

The engine facade exposes:

- `Get-RenderKitEngineClientList` with bounded offset/limit paging and
  search/status/tag filters;
- `Get-RenderKitEngineClientDetail`;
- `New-RenderKitEngineClient`;
- `Set-RenderKitEngineClient`.

List results deliberately omit contacts, addresses, notes, consent, and
retention. Mutations require an actor context and return stable validation,
not-found, conflict, access-context, or storage errors in a `RenderKitResult`
envelope.

## Administration and debugging

Override the state root only for an isolated session or test:

```powershell
$env:RENDERKIT_HOME = 'C:\Temp\RenderKit-test'
```

Run the focused registry and engine tests from the repository root:

```powershell
Invoke-Pester Tests/Client
```

When diagnosing a conflict, read the client again and compare its `revision`;
do not edit `Clients.json` directly. A malformed artifact or failed write
should be investigated through the normal RenderKit state repair and storage
diagnostics so transaction and backup guarantees remain intact.

Project/job relationships, explicit personal-data export, retention-driven
deletion, and enterprise synchronization remain separate future contracts.
