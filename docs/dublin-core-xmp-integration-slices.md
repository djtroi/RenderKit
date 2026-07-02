# Dublin Core / XMP integration slices

RenderKit treats Dublin Core as an application profile carried by the XMP
`dc` namespace. ExifTool remains the executable adapter.

## Slice 1 - embedded Dublin Core

- Map only DCMES 1.1 elements with a semantic equivalent in `fields.json`.
- Preserve repeated XMP values as lists where the registry supports lists.
- Apply an explicit first-value application-profile constraint where the
  registry intentionally exposes a scalar.
- Preserve non-default language alternatives for `lang-alt` properties.
- Keep semantically ambiguous DCMES elements explicitly unmapped.
- Verify normalization, write composition, and embedded roundtrips.

## Slice 2 - qualified Dublin Core and standard XMP namespaces

- Map selected DCMI terms only where `fields.json` has the same semantics.
- Add XMP Basic, XMP Rights, and XMP Media Management profiles.
- Keep technical file facts separate from descriptive `dc:format` values.
- Add controlled URI handling for identifiers, relations, and licenses.

## Slice 3 - XMP sidecars and provenance

- Resolve sidecars without exposing raw paths to the renderer.
- Define embedded-versus-sidecar precedence and conflict states.
- Retain value-level source provenance instead of flattening conflicts.
- Invalidate cached metadata when either the media file or sidecar changes.

## Slice 4 - broker, catalog, and Studio

- Carry Dublin Core values, cardinality, provenance, and conflicts through the
  broker and project media catalog.
- Generate Studio controls from the canonical registry and profile maps.
- Support save, understandable partial-write errors, and rollback.

## Slice 5 - production workflows

- Apply Dublin Core/XMP values through templates and batch operations.
- Include profile values and provenance in metadata import/export.
- Add reference-file, sidecar, large-project, and cross-platform coverage.
