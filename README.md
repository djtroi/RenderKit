# RenderKit
![Static Badge](https://img.shields.io/badge/Version-Alpha-blue)
![GitHub Release](https://img.shields.io/github/v/release/djtroi/RenderKit)


# Overview
**RenderKit** is a Simple yet powerful Powershell Module that helps you optimize your Workflow while editing / producing videos.  <br>
Please Note, that this Modul is not released yet. 

## Functions
RenderKit provides you these Functions: 

- Set-ProjectRoot 
```powershell
Set-ProjectRoot "D:\Editing_Projects\"
```
Set-ProjectRoots lets you set a default Path for all your video project folders so you can save time, defining an absolute path everytime you create a new project. 

- New-Project 
```powershell
New-Project "WeddingFilm" "template"
``` 
New-Project creates for you your designated folder-structure for your project. The structure in .\Template\default.json defined. Feel free to edit it

-Backup-Project
```powershell
Backup-Project "Weddingfilm" -Software -KeepEmptyFolders -DryRun
``` 
Backup-Project creates structured backups of RenderKit projects, cleans temporary files, proxy files and software artifacts (WIP) before backup

# Basic Usage
## Installation
```powershell 
Install-Module -Name RenderKit
```


# RoadMap

These are the ad hoc functions and improvements that I'm looking forward to implement. If you have the time and motivation, feel free to open a PR for one of the features.

## Fundamentals & Stability

- Add Debugging & Logging Feature


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