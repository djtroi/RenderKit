# 0.2.0 – 2026-02-11
## Minor Release

---

## Added

### Backup System
- Introduced `Backup-Project`
- Creates structured backups of RenderKit projects
- Cleans temporary files, proxy files and software artifacts (WIP) before backup
- ZIP packaging planned for future release

### Project Metadata System
- Introduced `.renderkit` folder
- Added `project.json` containing:
  - Unique Project GUID
  - Project Name
  - Creation timestamp (ISO 8601)
  - Operating System
  - RenderKit version
  - Template name
  - Template source

### Template Engine
- Added multiple project templates
- Introduced `New-Project -Template`
- Fallback to `default` template if specified template does not exist

### Backup Locking
- Implemented `backup.lock` mechanism
- Prevents concurrent modifications during backup

### Internal Improvements
- Added internal logging foundation (WIP)
- Added preparation for future Dry-Run functionality

---

## Changed

- Renamed `Template` folder to `Templates`
- Updated MIT License metadata

---

## Removed

- Removed all function aliases due to PowerShell resolution issues

---

## Fixed

- Fixed module version detection in `project.json`

---

## Deprecated

- None

---

## Security

- No changes

# 0.1.0 2026.01.29
## Added

- Added Function "New-Project"
- Added Function "Set-ProjectRoot"

## Changed

- Nothing

## Deprecated

- Nothing

## Removed

- Nothing

## Fixed

- Nothing

## Security

- Nothing