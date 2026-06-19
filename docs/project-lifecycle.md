# Project lifecycle

RenderKit now stores an internal lifecycle status in project metadata. The
status is engine-owned by default and is intended to support future workflow
automation, event handling, GUI filters, and cloud synchronization.

## Statuses

The initial internal statuses are:

- `Unknown` for older projects without lifecycle metadata;
- `Draft` for newly created projects;
- `Active` for imported or copied projects and projects that received media;
- `Delivered` for future delivery workflows;
- `Archived` for completed backups that keep the source project; and
- `Cancelled` for terminal cancelled work.

## Transition rules

Same-status transitions are no-ops and do not create history entries.
`Cancelled` and `Archived` are terminal for the local project and cannot become
`Active` again. Archived or cancelled projects can still be copied later because
copying creates a new project identity.

Delivered projects may move down to active or draft when follow-up work is
needed.

## Update points

The engine updates lifecycle status internally:

- `New-Project` creates metadata with `Draft`;
- `Import-Media` marks confirmed target projects `Active`;
- `Import-Project` imports projects as `Active`;
- `Copy-Project` creates the copy as `Active`;
- `Backup-Project -KeepSourceProject` marks the source project `Archived`; and
- `Rename-Project`, `Remove-Project`, and `Export-Project` do not directly
  change lifecycle status.

No public lifecycle cmdlet is introduced in this phase. Public cmdlet names
remain subject to explicit product approval.