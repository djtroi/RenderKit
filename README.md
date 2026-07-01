# RenderKit

![GitHub Release](https://img.shields.io/github/v/release/djtroi/RenderKit?label=release)
![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/RenderKit?label=PowerShell%20Gallery)
![Downloads](https://img.shields.io/powershellgallery/dt/RenderKit)
[![Quality Gate](https://github.com/djtroi/RenderKit/actions/workflows/quality-gate.yml/badge.svg)](https://github.com/djtroi/RenderKit/actions/workflows/quality-gate.yml)

**RenderKit** is a free and open-source PowerShell toolkit for video editors, media creators, and small production teams who want repeatable project folders, safer media imports, simple delivery packages, and auditable backups.

RenderKit is currently the workflow/engine foundation for a future local-first MAM/DAM-style tool. Think of it as the practical workflow layer around your editing software: project setup, ingest discipline, transfer checks, packaging, and backup structure.

---

## Why RenderKit exists

Video projects often become messy for boring reasons:

* every project folder looks slightly different;
* footage gets copied manually without verification;
* delivery folders are inconsistent;
* backups are hard to audit later;
* client/project handoffs are improvised every time;
* small teams need structure, but not another expensive platform.

RenderKit tries to solve that with a local, scriptable, transparent workflow toolkit.

The goal is simple:

> Make media-production project workflows repeatable, inspectable, and safe — without locking users into a paid platform.

---

## Who this is for

RenderKit is currently useful for:

* solo video editors;
* YouTubers and content creators with recurring project structures;
* small production teams;
* freelancers handling client projects;
* editors who like predictable folders and safe ingest workflows;
* technically comfortable users who do not mind using PowerShell.

RenderKit is probably **not** for you yet if you need:

* a polished desktop GUI today;
* thumbnail browsing;
* visual metadata panels;
* cloud team collaboration;
* NLE plugin integration;
* enterprise asset-management permissions;
* a full replacement for a professional MAM/DAM system.

Those areas may come later, but the current focus is the workflow foundation.

---

## What RenderKit can do

### Project setup

Create consistent project folders from reusable templates.

```powershell
Set-ProjectRoot -Path "D:\Editing_Projects"

New-Project -Name "ClientA_2026" -Template "youtube"
```

---

### Media import

Scan, filter, classify, and transfer source media into the right project folders.

```powershell
Import-Media
```

Or run it with explicit parameters:

```powershell
Import-Media `
  -ScanAndFilter `
  -SourcePath "E:\DCIM" `
  -FolderFilter "100EOSR" `
  -Wildcard "*.mp4","*.mov" `
  -Classify `
  -Transfer `
  -ProjectRoot "D:\Editing_Projects\ClientA_2026" `
  -TemplateName "youtube"
```

---

### Transfer safety

RenderKit can import media through transaction-style staging workflows instead of simply dragging files into a folder.

Depending on the selected mode and version, RenderKit can:

* copy into a temporary staging location;
* validate transfer completion;
* perform hash-based verification when required;
* commit the file into the final destination only after validation;
* preserve source files by default;
* expose transfer metrics for copy, verification, and end-to-end throughput.

This is designed for workflows where “I think I copied everything” is not good enough.

---

### Templates and media mappings

Define reusable project structures and map media types to folders.

```powershell
New-RenderKitTemplate -Name "client-delivery"

Add-FolderToTemplate `
  -TemplateName "client-delivery" `
  -FolderName "01_Footage"

New-RenderKitMapping -Name "camera-media"

Add-RenderKitTypeToMapping `
  -MappingName "camera-media" `
  -Extension ".mp4" `
  -TargetFolder "01_Footage"

Add-RenderKitMappingToTemplate `
  -TemplateName "client-delivery" `
  -MappingName "camera-media"
```

This makes it possible to reuse the same structure across projects instead of rebuilding folders by hand every time.

---

### Delivery packages

Prepare files for review, publishing, handoff, or archiving.

```powershell
Send-Project `
  -ProjectRoot "D:\Editing_Projects\ClientA_2026" `
  -DestinationPath "E:\Delivery\ClientA-review.zip" `
  -DeliveryRule "review" `
  -PackageMode Zip
```

RenderKit can help keep deliverables structured and repeatable instead of manually collecting files at the end of a project.

---

### Export and import projects

Export project metadata or create self-contained project packages.

```powershell
Export-Project `
  -ProjectRoot "D:\Editing_Projects\ClientA_2026" `
  -DestinationPath "E:\Transfer\ClientA_2026.rkit" `
  -Mode ManifestOnly
```

```powershell
Export-Project `
  -ProjectRoot "D:\Editing_Projects\ClientA_2026" `
  -DestinationPath "E:\Transfer\ClientA_2026.rkitpkg" `
  -Mode SelfContained
```

```powershell
Import-Project `
  -Path "E:\Transfer\ClientA_2026.rkitpkg" `
  -DestinationRoot "D:\Editing_Projects"
```

---

### Backups

Create project backups with structured manifests and integrity-oriented workflows.

```powershell
Backup-Project -ProjectName "ClientA_2026"
```

```powershell
Backup-Project `
  -ProjectName "ClientA_2026" `
  -DestinationRoot "E:\Backups" `
  -KeepSourceProject
```

---

## Installation

RenderKit is published through the PowerShell Gallery.

Recommended installation for current PowerShell environments:

```powershell
Install-PSResource -Name RenderKit -Scope CurrentUser -Repository PSGallery
Import-Module RenderKit
```

Legacy-compatible installation:

```powershell
Install-Module -Name RenderKit -Scope CurrentUser -Repository PSGallery
Import-Module RenderKit
```

If `Install-PSResource` is not available yet:

```powershell
Install-Module -Name Microsoft.PowerShell.PSResourceGet -Scope CurrentUser
```

---

## Requirements

RenderKit supports:

* Windows PowerShell 5.1
* PowerShell 7+
* Windows
* macOS
* Linux

Some workflows are naturally more useful on Windows-based editing systems, but the module is designed with cross-platform storage and path handling in mind.

---

## Quick start

### 1. Install and import RenderKit

```powershell
Install-PSResource -Name RenderKit -Scope CurrentUser -Repository PSGallery
Import-Module RenderKit
```

### 2. Create or select your editing root

```powershell
New-Item -ItemType Directory -Path "D:\Editing_Projects" -Force
Set-ProjectRoot -Path "D:\Editing_Projects"
```

### 3. Create a project

```powershell
New-Project -Name "ClientA_2026" -Template "youtube"
```

### 4. Import media

```powershell
Import-Media
```

### 5. Back up the project

```powershell
Backup-Project -ProjectName "ClientA_2026"
```

---

## Common commands

Check all exported RenderKit commands:

```powershell
Get-Command -Module RenderKit
```

Open full help for a command:

```powershell
Get-Help Import-Media -Full
```

Show examples:

```powershell
Get-Help Import-Media -Examples
```

---

## Safety notes

RenderKit can create, copy, package, archive, and remove project data depending on the command and parameters you choose.

Before using RenderKit on real client work:

* test your workflow with sample folders;
* use `-WhatIf` or `-DryRun` where available;
* verify source and destination paths;
* keep an independent backup strategy;
* do not treat any tool as your only copy of important footage.

RenderKit is designed to make workflows safer and more repeatable, but you are still responsible for verifying your production storage and backup process.

---

## Current status

RenderKit is usable, but still evolving.

The current focus is:

* project lifecycle workflows;
* media import and transfer safety;
* reusable templates and mappings;
* package/export/import workflows;
* backup manifests and auditability;
* local state foundations for future GUI or host integrations.

Planned or future areas may include:

* a user-friendly desktop interface;
* richer metadata workflows;
* preview and thumbnail workflows;
* deeper media catalog features;
* NLE integration;
* proxy/transcode workflows;
* team-oriented collaboration features.

---

## Feedback wanted

RenderKit is being built to solve real media-production workflow problems.

If you are a video editor, content creator, post-production technician, or media manager, feedback is very welcome.

Useful feedback includes:

* How do you structure your editing projects?
* What always goes wrong during media ingest?
* What would you want verified during file transfer?
* How do you package review files or final deliveries?
* What metadata would actually help you?
* What would make this useful for a small production team?
* What would you expect from a lightweight MAM/DAM-style tool?

You can share feedback by opening a GitHub issue or starting a discussion around your workflow pain points.

---

## License

RenderKit is released under the MIT License.

You can use it, modify it, and build on top of it freely.
