# RenderKit file formats

RenderKit-owned portable artifacts use a RenderKit-specific extension. The
extension identifies the domain artifact; its underlying serialization remains
available to standard tooling.

## Active project formats

| Extension | Artifact | Container | Media type |
| --- | --- | --- | --- |
| `.rkit` | Project manifest and portable resources | ZIP | `application/vnd.renderkit.project+zip` |
| `.rkitpkg` | Self-contained project package including project files | ZIP | `application/vnd.renderkit.project-package+zip` |

Both formats are valid ZIP archives and contain `project.xml` at the archive
root. Operating-system integration may therefore classify them as ZIP-based
archives without changing their RenderKit-specific extension.

The machine-readable format identifiers used by Core and packaging integrations
are stored in `src/Resources/FileFormats/RenderKit.FileFormats.json`.

## Reserved portable artifact extensions

The following extensions are reserved for future or migrated portability
commands. Reserving them does not change the internal JSON files used by the
RenderKit runtime.

| Extension | Intended artifact |
| --- | --- |
| `.rkittemplate` | Portable project or metadata template |
| `.rkitmapping` | Portable media mapping |
| `.rkitprofile` | Portable backup or workflow profile |
| `.rkitmetadata` | Portable metadata export |
| `.rkitjobs` | Portable job-history collection |

RenderKit types remain part of a mapping. A separate type extension should only
be introduced if types become independently versioned and portable artifacts.
