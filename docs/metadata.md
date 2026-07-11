# Metadata workflow

RenderKit 1.1.0 provides one metadata workflow for individual media files,
complete projects, templates, imports, exports, cached reads, and rollback. The
canonical field definitions are versioned with the module in
`src/Resources/Metadata/fields.json`; callers should query that registry rather
than maintain their own field list.

## Inspect and validate fields

```powershell
Get-RenderKitMetadataFieldRegistry -Field Title, Creator -IncludeRegistryMetadata
Get-RenderKitMetadataFieldRegistry -AppliesTo Audio -Category Descriptive
Test-RenderKitMetadataFieldValue -Field Keywords -Value @('interview', 'day-01')
```

`Test-RenderKitMetadataFieldValue -PassThru` returns normalized data when the
field definition supports normalization. Invalid enum values, shapes, lengths,
and media-kind constraints fail before a write begins.

## Read metadata

```powershell
Get-Metadata -Path '.\media\interview.wav' -IncludeMetadata
Get-Metadata -Path '.\media' -Recurse -Field Title, Creator, Duration
Get-Metadata -ProjectRoot 'D:\Projects\Documentary' -Store
Update-MetadataCache -ProjectRoot 'D:\Projects\Documentary' -ThrottleLimit 4
```

`Get-Metadata` combines technical inspection, embedded metadata, XMP sidecars,
and the RenderKit metadata store. `-IncludeMetadata` includes provenance and
adapter details; `-IncludeRaw` additionally exposes backend data for diagnosis.
Use `-NoStore` for a read that must not update the cache.

## Write and roll back metadata

```powershell
$result = Add-Metadata `
    -Path '.\media\interview.wav' `
    -Field Title `
    -Value 'Interview A'

Rollback-Metadata `
    -Path '.\media\interview.wav' `
    -Version ($result.MetadataVersion - 1)
```

Every successful logical change creates a new store version. Rollback restores
the selected earlier content as a new current version; it does not delete
history. `-NoEmbedded` limits a change to the RenderKit store. `-XmpSidecar`
requests a sidecar write for compatible XMP fields. `-Override` permits an
existing value to be replaced, while `-Force` is reserved for supported
validation or conflict overrides. Review `-WhatIf` before bulk writes.

Native RIFF writes are used for WAV/RF64 BWF and iXML fields. ID3v2.4 writes use
the bundled TagLibSharp backend, Matroska writes use MKVToolNix, and supported
XMP/IPTC writes use ExifTool. Each writer changes a temporary same-directory
copy, performs semantic readback, and only then replaces the original. Backend
availability and provenance are returned instead of being silently invented.

## Templates and batch exchange

```powershell
New-MetadataTemplate -Name interview -Description 'Interview defaults'
Add-MetadataTemplateField -Name interview -Field Copyright -Value 'Example Studio'
Set-MetadataTemplateField -Name interview -Field Keywords -Value @('interview')
Get-MetadataTemplate -Name interview -IncludeFields
Add-MetadataTemplate -Name interview -ProjectRoot 'D:\Projects\Documentary'

Export-Metadata `
    -ProjectRoot 'D:\Projects\Documentary' `
    -DestinationPath '.\documentary-metadata.json' `
    -IncludeHistory

Import-Metadata `
    -Path '.\documentary-metadata.json' `
    -ProjectRoot 'D:\Projects\Documentary' `
    -ConflictAction Skip
```

Import conflict actions are explicit; inspect the command syntax and use
`-WhatIf` before applying an exchange file to production assets. A batch result
can be reversed with `Rollback-Metadata -ProjectRoot <path> -BatchId <id>`.

## Runtime resolution

MediaInfo reads prefer a bundled native library, then configured native/host
or CLI candidates. ExifTool uses the supported executable interface and has
explicit bundled, configured-host, and system-CLI fallbacks. Relevant
overrides are documented in the repository [README](../README.md#third-party-components).

