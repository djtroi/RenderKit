# IPTC integration slices

The IPTC integration builds on RenderKit's bundled ExifTool runtime. IPTC is a
metadata profile and mapping concern; it does not need a second executable
adapter beside ExifTool.

## Slice 1 - IPTC Core read/write (complete)

- Add a versioned, declarative IPTC Core-to-RenderKit field map.
- Prefer current XMP values over legacy IIM values while reading.
- Keep list values as lists and never infer list boundaries from punctuation.
- Write XMP and compatible IIM/EXIF representations through ExifTool.
- Preserve non-default XMP language alternatives when updating default text.
- Verify field mapping, precedence, and embedded roundtrips.

## Slice 2 - IPTC Extension (complete)

- Map the flat Extension fields already represented by `fields.json`.
- Model structured Extension values explicitly instead of flattening ambiguous
  objects into invented scalar values.
- Add controlled-vocabulary URI mapping for fields such as Digital Source Type.
- Add reference-image compatibility tests.

## Slice 3 - broker and catalog semantics (complete)

- Carry embedded values, RenderKit overrides, source provenance, and conflicts
  through the broker contracts.
- Synchronize IPTC changes and rollback versions into the project media catalog.
- Distinguish unsupported, absent, stale, conflicting, and write-failed states.

## Slice 4 - Studio editing (complete)

- Add task-focused IPTC Core and IPTC Extension sections to the media viewer.
- Generate controls from the canonical field registry.
- Show the effective value and its source without exposing raw file paths.
- Support save, optimistic feedback, understandable errors, and rollback.

## Slice 5 - production workflows (complete)

- Apply IPTC fields through templates and batch operations.
- Include mapped IPTC values in metadata import/export.
- Add cache invalidation, large-project performance coverage, and cross-platform
  reference-image smoke tests.

The cross-platform reference smoke is opt-in so normal test runs stay
deterministic. Set `RENDERKIT_IPTC_REFERENCE_IMAGE` to an official IPTC
reference JPEG before running the metadata Pester suite.
