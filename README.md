# RenderKit
![Static Badge](https://img.shields.io/badge/Version-Alpha-blue)
![GitHub Release](https://img.shields.io/github/v/release/djtroi/RenderKit)


# Overview
**RenderKit** is a simple but powerful PowerShell module that helps you optimize your workflow while editing or producing videos.  
Please note that this module is not released yet.

## Public Functions
`Set-ProjectRoot`  
Sets the default base path for your projects (stored in `%APPDATA%\RenderKit\config.json`).
```powershell
Set-ProjectRoot -Path "D:\Editing_Projects"
```

`New-Project`  
Creates a new project folder structure from a template. If `-Template` is omitted, `default` is used. If `-Path` is omitted, the configured project root is used.
```powershell
New-Project WeddingFilm youtube
New-Project -Name "WeddingFilm" -Template "youtube"
New-Project -Name "WeddingFilm" -Path "D:\Projects"
```

`New-RenderKitTemplate`  
Creates a new user template in AppData.
```powershell
New-RenderKitTemplate -Name "my-template"
```

`Add-FolderToTemplate`  
Adds a folder path (and optional mapping) to a template.
```powershell
Add-FolderToTemplate -TemplateName "my-template" -FolderPath "01_Raw/01_Video"
Add-FolderToTemplate -TemplateName "my-template" -FolderPath "01_Raw/01_Video" -MappingId "video"
```

`New-RenderKitMapping`  
Creates a new mapping file in AppData.
```powershell
New-RenderKitMapping -Id "camera"
```

`Add-RenderKitTypeToMapping`  
Adds a file type and extensions to a mapping.
```powershell
Add-RenderKitTypeToMapping -MappingId "camera" -TypeName "Video" -Extensions ".mp4",".mov"
```

`Add-RenderKitMappingToTemplate`  
Registers a mapping in a template (supports multiple mappings per template).
```powershell
Add-RenderKitMappingToTemplate -TemplateName "my-template" -MappingId "camera"
```

`Backup-Project`  
Cleans a project and creates a backup archive (supports `-WhatIf` / `-Confirm`).
```powershell
Backup-Project -ProjectName "WeddingFilm" -Software "DaVinci" -KeepEmptyFolders
Backup-Project -ProjectName "WeddingFilm" -DryRun
```

`Get-RenderKitDriveCandidate`  
Detects mounted source-drive candidates (`FAT32`/`exFAT`, with `exFAT` priority).
```powershell
Get-RenderKitDriveCandidate
Get-RenderKitDriveCandidate -IncludeFixed
```

`Select-RenderKitDriveCandidate`  
Shows detected candidates in CLI and lets you confirm one by index.
```powershell
Select-RenderKitDriveCandidate
```

`Get-RenderKitDeviceWhitelist`  
Reads the device whitelist from `%APPDATA%\RenderKit\Devices.json` (file is auto-created if missing).
```powershell
Get-RenderKitDeviceWhitelist
```

`Add-RenderKitDeviceWhitelistEntry`  
Adds volume names and/or serial numbers to the whitelist.
```powershell
Add-RenderKitDeviceWhitelistEntry -VolumeName "EOS_DIGITAL"
Add-RenderKitDeviceWhitelistEntry -DriveLetter "E:"
Add-RenderKitDeviceWhitelistEntry -FromMountedVolumes
```

`Import-Media`  
Entry point for media import detection. Lists candidates or lets you select one.
```powershell
Import-Media
Import-Media -SelectSource
```

# Basic Usage
## Installation
```powershell 
Install-Module -Name RenderKit
```


# RoadMap

These are the ad hoc functions and improvements that I'm looking forward to implement. If you have the time and motivation, feel free to open a PR for one of the features.

## Fundamentals & Stability

- Add Error- / Exceptionhandling and Rollback

- Add Function to create a project with an absolute path

- Add Markdown template support

- Add Template management functions (show templates, create template, validate template(intern))

- Optimize Normalization and Validation of templates

- Add function to deliver files to a customer (grab and zip together your latest rendered files in your folder)

- Add function to use multiple "deliver" export-profiles 

- Add versioning for project-templates for rollback-possibilty

- Create Project-Statistics / Reporting

- Create Cmdlet Alias / Shortcuts

- Cloud Integration

- Maybe GUI / WEB-Frontend

- Create a Naming-Conventions into the configuration

- Create a Multi-Project-Management (list, filter, create status etc.)

- Pester Integration
