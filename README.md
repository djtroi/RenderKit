# RenderKit
![Static Badge](https://img.shields.io/badge/Version-Alpha-blue)
![GitHub Release](https://img.shields.io/github/v/release/djtroi/RenderKit)
[![PSScriptAnalyzer](https://github.com/djtroi/RenderKit/actions/workflows/powershell_PSScriptAnalyzer.yml/badge.svg)](https://github.com/djtroi/RenderKit/actions/workflows/powershell_PSScriptAnalyzer.yml)


## Overview
**RenderKit** is a PowerShell module for structured video-production workflows.
It helps you create standardized projects, manage templates/mappings, import media with filter and transfer workflows, and archive projects safely.

## What's new in 0.3.5
- Deterministic module exports and loading for cleaner imports across Windows PowerShell and PowerShell 7
- Staged release packaging for PowerShell Gallery with lean artifacts and a generated publish bundle
- Maintainer scripts for building and publishing `0.3.5` without dragging `.git`, workflows, or tests into the package

## Core Features
### 1) End-to-end media import workflow (`Import-Media`)
You can now run a full scan → filter → selection → classification → transfer pipeline in one command.
# Interactive wizard
Import-Media
# Parameter-driven scan and filter
Import-Media -ScanAndFilter -SourcePath "E:\DCIM" -FolderFilter "100EOSR" -Wildcard "*.mp4","*.mov"
# Scan + classify + transfer (with integrity hash)
Import-Media -ScanAndFilter -SourcePath "E:\DCIM" -Classify -Transfer -ProjectRoot "D:\Projects\ClientA_2026" -TemplateName "default" -TransferHashAlgorithm SHA256

### 2) Production-ready backup pipeline (`Backup-Project`)
Backups now include cleanup profiles, archive creation, integrity verification, log injection, and manifest handling.
# Standard backup
Backup-Project -ProjectName "ClientA_2026"
# Backup preview without writing changes
Backup-Project -ProjectName "ClientA_2026" -Profile DaVinci -DryRun
# Backup and keep source project
Backup-Project -ProjectName "ClientA_2026" -DestinationRoot "E:\Backups" -KeepSourceProject

### 3) Drive detection + whitelist workflow
Source selection and whitelisting are integrated for faster import setup.
# Detect candidate drives
Get-RenderKitDriveCandidate
# Interactively select a source drive
Select-RenderKitDriveCandidate -IncludeFixed
# Add known media devices to whitelist
Add-RenderKitDeviceWhitelistEntry -FromMountedVolumes

---

## Public Functions

### Project & template setup
- `Set-ProjectRoot`
- `New-Project`
- `New-RenderKitTemplate`
- `Add-FolderToTemplate`
- `New-RenderKitMapping`
- `Add-RenderKitTypeToMapping`
- `Add-RenderKitMappingToTemplate`

### Import & source detection
- `Import-Media`
- `Get-RenderKitDriveCandidate`
- `Select-RenderKitDriveCandidate`
- `Get-RenderKitDeviceWhitelist`
- `Add-RenderKitDeviceWhitelistEntry`

### Backup
- `Backup-Project`

---

## Basic Usage

### Installation
```powershell
Install-Module -Name RenderKit
```

### Installation with PSResourceGet
```powershell
Install-PSResource -Name RenderKit -Repository PSGallery
```

### Minimal setup
```powershell
Set-ProjectRoot -Path "D:\Editing_Projects"
New-Project -Name "WeddingFilm" -Template "youtube"
```

## Maintainer Release Workflow

Build a clean release artifact:
```powershell
pwsh ./build/Build-RenderKitPackage.ps1
```

Publish the generated package to PowerShell Gallery:
```powershell
pwsh ./build/Publish-RenderKit.ps1 -Repository PSGallery -ApiKey '<APIKEY>'
```

---
## Roadmap

- Add markdown template support
- Add template management and validation functions
- Add delivery/export profile workflow
- Add project statistics/reporting
- Add multi-project management
- Explore cloud integration and optional GUI/Web frontend
