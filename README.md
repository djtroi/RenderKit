# RenderKit
![GitHub Release](https://img.shields.io/github/v/release/djtroi/RenderKit?label=release)
![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/RenderKit?label=PowerShell%20Gallery)
![PowerShell Gallery Downloads](https://img.shields.io/powershellgallery/dt/RenderKit)
[![PSScriptAnalyzer](https://github.com/djtroi/RenderKit/actions/workflows/powershell_PSScriptAnalyzer.yml/badge.svg)](https://github.com/djtroi/RenderKit/actions/workflows/powershell_PSScriptAnalyzer.yml)

**RenderKit** is a PowerShell toolkit for repeatable media-production project workflows: create project structures, manage templates and mappings, import camera media, verify transfers, and archive finished work with confidence.

## Table of Contents

- [What is RenderKit?](#what-is-renderkit)
- [Quickstart](#quickstart)
- [Why RenderKit Exists](#why-renderkit-exists)
- [Core Features](#core-features)
- [Architecture](#architecture)
- [Documentation](#documentation)
- [Public Functions](#public-functions)
- [Maintainer Release Workflow](#maintainer-release-workflow)
- [Roadmap](#roadmap)

## What is RenderKit?

RenderKit helps editors and media teams standardize the repetitive parts of a production pipeline. Instead of manually creating folders, remembering naming conventions, sorting camera files, and building backup archives by hand, RenderKit gives you composable commands for the full lifecycle of a project.

Use it to:

- define reusable project templates and media mappings;
- create consistent editing project folders;
- detect media drives and pick source folders interactively;
- scan, filter, classify, and transfer media into the right destinations;
- back up projects with manifests, integrity checks, and archive workflows.

## Quickstart

### 1. Install RenderKit
```powershell
Install-Module -Name RenderKit -Scope CurrentUser
```

Or with PSResourceGet:
```powershell
Install-PSResource -Name RenderKit -Scope CurrentUser
```

### 2. Create your project root

```powershell
Set-ProjectRoot -Path "D:\Editing_Projects"
```

### 3. Create a project from a template

```powershell
New-Project -Name "ClientA_2026" -Template "youtube"
```

### 4. Import media interactively

```powershell
Import-Media
```

### 5. Import media with parameters

```powershell
Import-Media `
  -ScanAndFilter `
  -SourcePath "E:\DCIM" `
  -FolderFilter "100EOSR" `
  -Wildcard "*.mp4","*.mov" `
  -Classify `
  -Transfer `
  -ProjectRoot "D:\Editing_Projects\ClientA_2026" `
  -TemplateName "default" `
  -TransferHashAlgorithm SHA256
```

### Tutorial placeholders

GIF walkthroughs are planned for future README updates:

| Tutorial | Preview |
| --- | --- |
| Install and first project | _GIF coming soon: `docs/assets/tutorial-install.gif`_ |
| Interactive media import | _GIF coming soon: `docs/assets/tutorial-import.gif`_ |
| Backup and archive workflow | _GIF coming soon: `docs/assets/tutorial-backup.gif`_ |

> [!WARNING]
> RenderKit can copy, archive, and optionally remove project data depending on the command and parameters you choose. Test new workflows with `-DryRun` where available and verify your destination paths before running production operations.

## Why RenderKit Exists

Video projects tend to fail in quiet, boring ways: inconsistent folder names, forgotten camera cards, copied files without hashes, missing delivery folders, and archives that cannot be audited later. RenderKit exists to make those operational details explicit, repeatable, and scriptable.

The goal is not to replace your editor, NLE, DAM, or backup strategy. RenderKit focuses on the glue around them: the project scaffolding, import discipline, transfer safety, and metadata that make handoffs and long-term storage easier.
### Interactive import workflow

Run a scan → filter → selection → classification → transfer pipeline from one command:
_GIF coming soon
```powershell
Import-Media
```
### Drive detection and whitelisting
```powershell
Get-RenderKitDriveCandidate

Select-RenderKitDriveCandidate -IncludeFixed

t
Add-RenderKitDeviceWhitelistEntry -FromMountedVolumes
```


### Production-ready backup pipeline

```powershell
Backup-Project -ProjectName "ClientA_2026"
Backup-Project -ProjectName "ClientA_2026" -Profile DaVinci -DryRun
Backup-Project -ProjectName "ClientA_2026" -DestinationRoot "E:\Backups" -KeepSourceProject
```

### Template and mapping management

```powershell
New-RenderKitTemplate -Name "client-delivery"
Add-FolderToTemplate -TemplateName "client-delivery" -FolderName "01_Footage"
New-RenderKitMapping -Name "camera-media"
Add-RenderKitTypeToMapping -MappingName "camera-media" -Extension ".mp4" -TargetFolder "01_Footage"
Add-RenderKitMappingToTemplate -TemplateName "client-delivery" -MappingName "camera-media"
```

## Architecture

- [ADR-001: Project Identity and Local Registry](architecture/ADR-001-project-identity-and-registry.md)
- [ADR-002: Project Lifecycle State Machine](architecture/ADR-002-project-lifecycle.md)
- [ADR-003: Domain Events, Durable Jobs, and Automation](architecture/ADR-003-domain-events-and-jobs.md)
- [ADR-004: Artifact and Business Versioning](architecture/ADR-004-artifact-versioning.md)
- [ADR-005: Cross-Platform Storage and Path Handling](architecture/ADR-005-cross-platform-storage.md)
- [ADR-006: Local Engine Security Baseline](architecture/ADR-006-security-baseline.md)
- [Architecture implementation plan](architecture/phase-implementation-plan.md)

## Documentation

Detailed German-language usage documentation is available in [`docs/README.md`](docs/README.md). It includes:

- installation and update instructions for PSResourceGet and PowerShellGet;
- a guided first-run workflow;
- one consistently structured Markdown reference page per implemented public function;
- parameter, safety, output, and usage guidance for every documented command.

## Public Functions


### Project lifecycle

- `Set-ProjectRoot`
- `New-Project`
- `Rename-Project`
- `Remove-Project`
- `Import-Project`
- `Export-Project`
- `Clone-Project`
- `Send-Project`

### Template and mapping setup

- `New-RenderKitTemplate`
- `Add-FolderToTemplate`
- `Add-RenderKitDeliverableToTemplate`
- `New-RenderKitMapping`
- `Add-RenderKitTypeToMapping`
- `Add-RenderKitMappingToTemplate`

### Import and source detection

- `Import-Media`
- `Get-RenderKitDriveCandidate`
- `Select-RenderKitDriveCandidate`
- `Get-RenderKitDeviceWhitelist`
- `Add-RenderKitDeviceWhitelistEntry`

### Backup
- `Backup-Project`

## Maintainer Release Workflow

Build a clean release artifact:

```powershell
pwsh ./build/Build-RenderKitPackage.ps1
```

Publish the generated package to PowerShell Gallery:

```powershell
pwsh ./build/Publish-RenderKit.ps1 -Repository PSGallery -ApiKey '<APIKEY>'
```
