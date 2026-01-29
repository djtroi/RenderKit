# RenderKit
![Static Badge](https://img.shields.io/badge/Version-Pre--Alpha-blue)
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
New-Project "WeddingFilm"
``` 
New-Project creates for you your designated folder-structure for your project. The structure in .\Template\default.json defined. Feel free to edit it

-Archive-Project
TBA

# Basic Usage
## Installation
```powershell 
Install-Module -Name RenderKit
```

# RoadMap

These are the ad hoc functions and improvements that I'm looking forward to implement. If you have the time and motivation, feel free to open a PR for one of the features. 

## Fundamentals & Stability

- Add Debugging & Logging Feature

- Add Cleanup Function (project)

- Add Error- / Exceptionhandling and Rollback

- Add Function to create a project with an absolute path

- Add a template management function (create projects with customized templates)

- Add Markdown template support

- Add Template management functions (show templates, create template, validate template(intern))

- Optimize Normalization and Validation of templates

- Add function to archive a project (deletes temporary files and empty folders and zips it to a path)

- Add function to deliver files to a customer (grab and zip together your latest rendered files in your folder)

- Add function to use multiple "deliver" export-profiles 

- Add versioning for project-templates for rollback-possibilty

- Create Project-Metadata 

- Create Project-Statistics / Reporting

- Create Cmdlet Alias / Shortcuts

- Cloud Integration

- Maybe GUI / WEB-Frontend

- Create a Naming-Conventions into the configuration

- Create a Multi-Project-Management (list, filter, create status etc.)


