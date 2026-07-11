# Security Policy

## Overview

RenderKit is a free and open-source media workflow toolkit for video editors, creators, and small production teams.

Because RenderKit works with real project folders, media files, archives, backups, import workflows, export packages, metadata, and local workflow state, security and data-safety issues are taken seriously.

This document explains how to report security-sensitive issues and what kind of information should not be shared publicly.

---

## Supported versions

Security and data-safety fixes are generally handled for the latest released version of RenderKit.

Please make sure you are using the latest version before reporting an issue:

```powershell id="n61w1v"
Get-Module RenderKit -ListAvailable

Find-PSResource RenderKit
```

If you installed RenderKit through PowerShellGet:

```powershell id="28v2t9"
Find-Module RenderKit
```

---

## What counts as a security or data-safety issue?

Please treat the following as security-sensitive or data-safety-sensitive:

* unexpected deletion of source or project files;
* unsafe move, copy, import, export, archive, restore, or backup behavior;
* failed rollback after a partially completed operation;
* path traversal in import, export, archive, or package extraction workflows;
* writing files outside the expected destination folder;
* reading files outside the expected source or project scope;
* unsafe handling of `.rkit`, `.rkitpkg`, ZIP, or other archive/package formats;
* incorrect hash verification or false-positive transfer success;
* corrupted backup or package output being reported as valid;
* metadata leakage through logs, manifests, packages, or state files;
* exposing private project paths, user names, client names, or machine-specific data unexpectedly;
* command behavior that differs between `-WhatIf`, `-DryRun`, and real execution in a dangerous way;
* unsafe handling of symbolic links, junctions, reparse points, or mounted volumes;
* any issue that could cause data loss, data corruption, or unauthorized file access.

---

## Please do not post sensitive data publicly

Do not include any of the following in public issues, pull requests, comments, logs, screenshots, or examples:

* private footage;
* client media;
* personal files;
* production project files;
* credentials;
* API keys;
* access tokens;
* private URLs;
* customer names;
* private project names;
* full real production paths if they reveal sensitive information;
* confidential metadata;
* logs containing private machine, user, or client information.

When possible, replace sensitive values with safe placeholders.

Example:

```text id="t9wkv3"
D:\Editing_Projects\ClientA_2026\MEDIA\A001C001.mov
```

can become:

```text id="kfnl2p"
D:\Editing_Projects\ExampleProject\MEDIA\example.mov
```

---

## How to report a security-sensitive issue

If the issue may put user files, client data, archives, backups, project metadata, or private paths at risk, please avoid posting full exploit details publicly.

Preferred options:

1. Use GitHub's private vulnerability reporting feature if it is enabled for this repository.
2. If private reporting is not available, open a minimal public issue stating that you found a security-sensitive or data-safety-sensitive problem and that details should be exchanged privately.
3. Include only safe, non-sensitive reproduction information in the public issue.

A minimal public issue can look like this:

```text id="zprz9e"
Title: Security-sensitive path handling issue in project import

I found a path handling issue that may allow files to be written outside the expected project destination during import. I have a minimal reproduction available, but I do not want to post full details publicly because it may affect user data safety.
```

---

## What to include in a safe report

A useful report should include:

* RenderKit version;
* PowerShell version;
* operating system;
* command used;
* expected behavior;
* actual behavior;
* whether real files were affected;
* whether `-WhatIf` or `-DryRun` was used;
* whether the issue affects import, export, backup, archive, package, metadata, or delete behavior;
* a minimal reproduction using dummy folders and dummy files.

Useful version information:

```powershell id="m4k74y"
$PSVersionTable

Get-Module RenderKit -ListAvailable

Get-Command -Module RenderKit
```

Example using dummy paths:

```powershell id="y3vy1h"
New-Item -ItemType Directory -Path "C:\Temp\RenderKitSecurityTest\Source" -Force
New-Item -ItemType Directory -Path "C:\Temp\RenderKitSecurityTest\Project" -Force
```

Please avoid reproductions that require private footage or real client projects.

---

## Data-loss issues

Data-loss issues are treated as high priority.

Please clearly mark reports that involve:

* deleted source files;
* deleted project folders;
* failed rollback;
* missing files after import;
* incomplete backup output;
* corrupted package output;
* hash mismatch;
* archive extraction problems;
* unexpected overwrite;
* wrong destination path;
* unsafe behavior with `-SourceDisposition Move`.

When in doubt, stop using the affected workflow on real project data until the issue has been investigated.

---

## Safe testing guidance

Before testing potentially destructive workflows:

* use dummy files;
* use temporary folders;
* use `-WhatIf` or `-DryRun` where available;
* keep a separate backup of real project data;
* do not test new workflows directly on client projects;
* verify source and destination paths before running commands.

RenderKit aims to make media workflows safer and more repeatable, but no tool should be treated as the only protection for important footage or project files.

---

## Maintainer response

Security-sensitive and data-safety-sensitive reports will be reviewed as soon as reasonably possible.

Depending on the issue, the response may include:

* confirmation of the report;
* request for a safe reproduction;
* temporary workaround;
* patch release;
* documentation update;
* test coverage;
* changelog entry;
* public advisory if appropriate.

---

## Disclosure expectations

Please give the maintainer reasonable time to investigate and fix security-sensitive or data-safety-sensitive issues before publishing full technical details.

Public write-ups are appreciated after a fix is available, as long as they do not expose private user data or put existing users at unnecessary risk.

---

## License

RenderKit is released under the MIT License.

Security and data-safety contributions are welcome and will be handled under the same license as the rest of the project.
