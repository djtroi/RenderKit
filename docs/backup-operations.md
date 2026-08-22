# Backup operations and job control

`Backup-Project` can plan or execute a foreground backup, enqueue durable
background work, select configuration profiles and adapters, create reports,
and apply resource/system constraints. Start with `-DryRun` and a destination
outside the source project.

## Start and observe a backup

```powershell
Backup-Project -ProjectName 'Documentary' -DryRun

$job = Backup-Project `
    -ProjectName 'Documentary' `
    -DestinationRoot 'E:\RenderKit-Backups' `
    -Background `
    -StartWorker

Get-BackupJob -JobId $job.JobId -Watch
Get-RenderKitJobStatus -JobId $job.JobId -IncludeLogs -Tail 100
```

Use `-KeepSourceProject` unless the configured and verified workflow is
intended to remove source data. Compression, proxy/preview generation, storage
tiers, reporting, retry behavior, and resource limits are opt-in parameters;
inspect `Get-Help Backup-Project -Full` before combining them.

## Pause, resume, and stop

```powershell
Pause-BackupJob -JobId $job.JobId -Reason 'Destination maintenance'
Resume-BackupJob -JobId $job.JobId -Reason 'Destination available'
Stop-BackupJob -JobId $job.JobId -Reason 'Operator cancelled'
```

`Resume-BackupProjectJob`, `Suspend-BackupProjectJob`, and
`Stop-BackupProjectJob` expose the BackupProject-specific engine operations.
The shorter `Pause-BackupJob`, `Resume-BackupJob`, and `Stop-BackupJob`
commands are the normal operator-facing controls.

## Profiles and adapters

```powershell
New-BackupConfigProfile -Name archive-fast -BaseProfile Balanced
Get-BackupConfigProfile -Name archive-fast
Test-BackupConfigProfile -Name archive-fast -CheckAdapters
Export-BackupConfigProfile -Name archive-fast -Path '.\archive-fast.json'
Import-BackupConfigProfile -Path '.\archive-fast.json' -ConflictAction Rename

Get-BackupAdapter
Get-BackupAdapter -Type Encoder
```

`Set-BackupConfigProfile` supports optimistic generation checks and semantic
version bumps. `Update-BackupConfigProfile` migrates stored profiles to the
current schema. Custom adapters are trusted in-process code: register only
implementations you control, and remove them with `Remove-BackupAdapter` when
they are no longer available.

## Workers

```powershell
Start-RenderKitJobWorker -QueueName default -RunOnce

$job = Backup-Project -ProjectName 'Documentary' -Background
Start-RenderKitJobWorker `
    -WorkerId 'desktop-worker-01' `
    -JobId $job.JobId `
    -JobType BackupProject `
    -QueueName backup `
    -RunOnce

Get-RenderKitJobWorkerStatus -IncludeLogs -Tail 100
```

`-JobId` provides an additive targeted worker mode for orchestrators that need
to bind a one-shot worker to a specific queued job. Targeted workers require
`-RunOnce`; normal queue workers keep their existing priority and FIFO claim
behavior when `-JobId` is omitted.

Detached workers are long-lived local processes. Prefer `-RunOnce` during
development and validate handler/adaptor availability before unattended use.
See [Background Jobs](jobs.md) and [Job Workers](job-workers.md) for lease,
retry, actor-context, and handler-catalog semantics.

