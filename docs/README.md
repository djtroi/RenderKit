# RenderKit Documentation

This documentation covers installation, updates, and the use of every implemented public RenderKit function. Each function has its own Markdown file with the same structure: summary, syntax, prerequisites, parameters, example, output, safety guidance, and related links.

## Getting started

1. [Install or update RenderKit](installation.md)
2. Configure a project root: [`Set-ProjectRoot`](Set-ProjectRoot.md)
3. Create a project: [`New-Project`](New-Project.md)
4. Import media: [`Import-Media`](Import-Media.md)
5. Back up or deliver a project: [`Backup-Project`](Backup-Project.md), [`Send-Project`](Send-Project.md)

## Project management

- [`Set-ProjectRoot`](Set-ProjectRoot.md) – Configure the default project root
- [`New-Project`](New-Project.md) – Create a project from a template
- [`Copy-Project`](Copy-Project.md) – Copy a project with a new identity
- [`Rename-Project`](Rename-Project.md) – Rename a project while preserving its ID
- [`Remove-Project`](Remove-Project.md) – Remove a project
- [`Export-Project`](Export-Project.md) – Create a project manifest or self-contained package
- [`Import-Project`](Import-Project.md) – Import a project manifest or package
- [`Send-Project`](Send-Project.md) – Package deliverables for handoff or review
- [`Backup-Project`](Backup-Project.md) – Clean, archive, and verify a project

> [!NOTE]
> The implementation provides `Copy-Project`, while the current manifest and module loader export `Clone-Project`. This existing mismatch can affect which command name is available in a published module.

## Templates and mappings

- [`New-RenderKitTemplate`](New-RenderKitTemplate.md)
- [`Add-FolderToTemplate`](Add-FolderToTemplate.md)
- [`Add-RenderKitMappingToTemplate`](Add-RenderKitMappingToTemplate.md)
- [`Add-RenderKitDeliverableToTemplate`](Add-RenderKitDeliverableToTemplate.md)
- [`New-RenderKitMapping`](New-RenderKitMapping.md)
- [`Add-RenderKitTypeToMapping`](Add-RenderKitTypeToMapping.md)

## Media import and drive detection

- [`Import-Media`](Import-Media.md)
- [`Get-RenderKitDriveCandidate`](Get-RenderKitDriveCandidate.md)
- [`Select-RenderKitDriveCandidate`](Select-RenderKitDriveCandidate.md)
- [`Get-RenderKitDeviceWhitelist`](Get-RenderKitDeviceWhitelist.md)
- [`Add-RenderKitDeviceWhitelistEntry`](Add-RenderKitDeviceWhitelistEntry.md)

## PowerShell help

```powershell
Get-Command -Module RenderKit
Get-Help <FunctionName> -Full
Get-Help <FunctionName> -Examples
```