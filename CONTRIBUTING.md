# Contributing to RenderKit

Thank you for your interest in contributing to RenderKit.

RenderKit is a free and open-source PowerShell toolkit for repeatable media-production workflows. The long-term goal is to build a practical, honest, local-first MAM/DAM-style system for video editors, creators, and small production teams.

The current foundation focuses on project setup, media import, transfer safety, packaging, backup workflows, templates, mappings, metadata, and future host or GUI integrations.

This document explains how to contribute code, documentation, bug reports, feature proposals, workflow proposals, templates, and mappings.

---

## Project direction

RenderKit is built around real media-production workflows.

The project is moving toward a lightweight, practical MAM/DAM-style ecosystem that can help with:

* structured media project organization;
* repeatable ingest workflows;
* metadata and classification;
* safe media transfer and verification;
* project search and discovery;
* reusable templates and mappings;
* delivery packaging;
* backup and archive workflows;
* local auditability;
* future GUI and host integrations;
* future NLE-adjacent workflows.

The current PowerShell module is the workflow and engine foundation. Contributions should support that direction without sacrificing safety, transparency, or local-first usability.

---

## How to contribute

The preferred contribution flow is:

1. Check existing issues and pull requests.
2. Open an issue using the appropriate template.
3. Discuss the approach if the change is larger than a small fix.
4. Create a focused branch.
5. Add or update tests.
6. Update documentation if user-facing behavior changes.
7. Open a pull request using the pull request template.

Small bug fixes, documentation corrections, and test-only improvements can usually go directly to a pull request.

Larger workflow, architecture, metadata, GUI, or MAM/DAM-related changes should start with an issue or proposal first.

---

## Using issue templates

Please use the available issue templates whenever possible.

Typical template categories should include:

* bug report;
* feature request;
* workflow proposal;
* template or mapping request;
* documentation improvement;
* performance issue;
* safety or data-loss concern;
* metadata proposal;
* MAM/DAM workflow proposal.

The templates exist to keep reports structured and actionable.

A good issue should explain:

* what you expected to happen;
* what actually happened;
* the RenderKit version;
* the PowerShell version;
* the operating system;
* the command or workflow used;
* relevant logs or error messages;
* whether the issue affects real project data.

For transfer, backup, import, delete, archive, or metadata-related issues, please include whether you used `-WhatIf`, `-DryRun`, `-TransferVerificationMode`, or `-SourceDisposition`.

---

## Bug reports

When reporting a bug, please include a minimal reproduction whenever possible.

Good bug reports include:

```powershell
Import-Module RenderKit

Set-ProjectRoot -Path "D:\Editing_Projects"

Import-Media `
  -ScanAndFilter `
  -SourcePath "E:\DCIM" `
  -Wildcard "*.mp4" `
  -Classify `
  -Transfer `
  -ProjectRoot "D:\Editing_Projects\ClientA_2026" `
  -TemplateName "youtube"
```

Please also include:

```powershell
$PSVersionTable

Get-Module RenderKit

Get-Command -Module RenderKit
```

If the bug involves file operations, describe the folder layout using paths that do not expose private client names or sensitive data.

Example:

```text
Source:
E:\DCIM\100EOSR\A001C001.mov

Project:
D:\Editing_Projects\ClientA_2026\MEDIA
```

Do not upload confidential footage, client files, private project metadata, credentials, API keys, or personal data.

---

## Feature requests

Feature requests should describe the workflow problem first.

Instead of only saying:

```text
Add metadata support.
```

Please describe the actual workflow:

```text
When importing footage from multiple cameras, I want RenderKit to store camera model, card name, import date, original source path, checksum, and project association so I can audit where each clip came from later.
```

A good feature request should include:

* the problem;
* the current workaround;
* the desired behavior;
* example commands or UI expectations;
* whether the feature should be scriptable, interactive, GUI-based, or all of these;
* whether it affects project files, user state, templates, mappings, metadata, search, backups, or package formats.

---

## Workflow proposals

RenderKit is workflow-driven.

If you want to propose a new workflow, please use the workflow proposal template.

Good workflow proposals include:

* who the workflow is for;
* when it starts;
* what inputs are required;
* what files, metadata, or state are created;
* what should happen on failure;
* what should be reversible;
* what should be logged or audited;
* what should be searchable later;
* what the command-line experience might look like;
* what a future GUI experience might look like.

Example:

```powershell
Import-Media `
  -SourcePath "E:\DCIM" `
  -ProjectRoot "D:\Editing_Projects\ClientA_2026" `
  -TemplateName "documentary" `
  -Transfer `
  -TransferVerificationMode Full
```

Please keep workflow proposals practical and grounded in real editing, post-production, archiving, or media-management work.

---

## MAM/DAM-related proposals

RenderKit is intentionally moving toward a practical MAM/DAM-style system.

MAM/DAM-related proposals are welcome, especially when they are connected to real production workflows.

Useful proposal areas include:

* media catalogs;
* metadata extraction;
* clip classification;
* searchable project indexes;
* camera/card/source tracking;
* asset usage tracking;
* proxy workflows;
* archive and restore workflows;
* project-to-asset relationships;
* tags, ratings, labels, and notes;
* thumbnail and preview generation;
* duplicate detection;
* missing media detection;
* delivery and version tracking;
* NLE-adjacent workflow integration.

A good MAM/DAM proposal should explain:

* what asset or project information should be stored;
* where the information should come from;
* how it should be updated;
* how users should search or filter it;
* what should be visible in CLI output;
* what should eventually be visible in a GUI;
* what privacy or safety concerns exist.

---

## Templates and mappings

RenderKit uses templates and mappings to describe repeatable project structures and media classification rules.

Template and mapping contributions are welcome when they are broadly useful.

Examples:

* YouTube project template;
* podcast production template;
* documentary project template;
* commercial client delivery template;
* DaVinci Resolve-oriented folder structure;
* Premiere Pro-oriented folder structure;
* camera media mapping;
* audio production mapping;
* image sequence mapping;
* drone footage mapping;
* delivery package presets.

Template contributions should avoid highly personal naming conventions unless they are clearly documented as examples.

A good template contribution should include:

* the intended use case;
* folder structure;
* mapping rules;
* deliverable rules if applicable;
* example command usage;
* documentation explaining how to adapt it.

---

## Pull requests

Please keep pull requests focused.

A good pull request should:

* solve one clear problem;
* include tests where reasonable;
* update documentation for user-facing changes;
* avoid unrelated formatting changes;
* avoid large rewrites unless discussed first;
* keep backward compatibility in mind;
* explain safety implications for file operations;
* explain metadata or state changes when relevant.

Before opening a pull request, run the test suite:

```powershell
pwsh ./build/Invoke-RenderKitTests.ps1
```

If you changed packaging or module export behavior, also run:

```powershell
pwsh ./build/Build-RenderKitPackage.ps1
pwsh ./build/Test-RenderKitPackage.ps1
pwsh ./build/Test-RenderKitLocalInstall.ps1
```

If you cannot run all tests locally, explain what you did run and what remains unverified.

---

## Coding guidelines

RenderKit is written in PowerShell.

Please follow these general guidelines:

* support Windows PowerShell 5.1 where required;
* support PowerShell 7+;
* avoid platform-specific assumptions unless explicitly guarded;
* use explicit parameters and clear validation;
* prefer predictable object output over formatted text;
* keep user-facing commands documented;
* use `ShouldProcess`, `-WhatIf`, or `-DryRun` where destructive behavior is possible;
* avoid silent data loss;
* return structured errors where possible;
* keep internal helpers private unless they are intentionally part of the public API;
* design metadata and state changes with future GUI usage in mind.

For file operations, safety is more important than cleverness.

Any command that copies, moves, deletes, archives, imports, exports, verifies, indexes, or modifies project state should be designed with failure handling in mind.

---

## Testing guidelines

Tests should be added or updated for:

* bug fixes;
* new public commands;
* new parameters;
* changed output contracts;
* import, export, transfer, backup, or delete behavior;
* metadata behavior;
* search/index behavior;
* path handling;
* cross-platform behavior;
* regression cases.

Prefer tests that are deterministic and do not depend on machine-specific timing.

For concurrency, performance, or scheduler behavior, avoid assertions that are likely to be flaky across Windows, macOS, Linux, local machines, and GitHub Actions runners.

Good tests should verify behavior, not incidental timing.

---

## Documentation guidelines

User-facing changes should update documentation.

This may include:

* README examples;
* command documentation in `docs/`;
* parameter descriptions;
* safety notes;
* changelog entries;
* template documentation;
* metadata documentation;
* migration notes for breaking or behavior-changing updates.

Documentation should be written for users first.

Avoid explaining internal architecture in user-facing docs unless it helps the user make a safer or better workflow decision.

---

## Safety and data-loss concerns

RenderKit deals with real project files.

Safety-related issues are high priority.

Please clearly mark issues or pull requests that involve:

* unexpected deletion;
* failed rollback;
* corrupted archive output;
* hash mismatch;
* incomplete copy;
* incorrect source/destination path handling;
* import/export path traversal;
* backup integrity problems;
* incorrect metadata assignment;
* commands behaving differently with `-WhatIf` or `-DryRun`.

When in doubt, preserve source data and fail safely.

---

## Security

Do not report security-sensitive issues with public exploit details if the issue could put users' project data at risk.

Open a minimal public issue that states a security-sensitive report exists, or contact the maintainer directly if a private reporting channel is available.

Never include:

* private footage;
* credentials;
* API keys;
* private client data;
* personal data;
* production paths that reveal sensitive information.

---

## Commit messages

Use clear commit messages.

Good examples:

```text
Fix media import path reservation for duplicate filenames
Add regression test for failed staging rollback
Document full transfer verification mode
Add podcast production template
Add metadata proposal template
Add source card tracking to import transactions
```

Avoid vague commit messages such as:

```text
fix
changes
update stuff
wip
```

---

## Versioning and changelog

User-facing changes should include a changelog entry.

Use the existing changelog structure:

```markdown
### Added
### Changed
### Fixed
### Removed
### Deprecated
### Security
```

For breaking changes, clearly explain:

* what changed;
* who is affected;
* how to migrate;
* whether existing project metadata remains readable.

---

## License

By contributing to RenderKit, you agree that your contribution will be licensed under the MIT License.

RenderKit is free and open-source. Contributions should preserve that spirit.
