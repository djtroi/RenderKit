# BWF, iXML, ID3 und Matroska: Integrations-Slices

Die vier Profile erweitern die bestehende kanonische Metadaten-Registry. Sie
führen keine parallelen Feldnamen ein. Ein Feld gilt nur dann als integriert,
wenn seine Containersemantik eindeutig auf ein vorhandenes Registry-Feld
abgebildet werden kann.

## Slice 1: Deklarative Leseprofile und Normalisierung

- Je Standard eine versionierte Map mit explizit gemappten und bewusst nicht
  gemappten Registry-Feldern.
- BWF/BEXT und iXML aus RIFF/WAVE über ExifTool, mit MediaInfo-Fallback für
  technische BWF-Werte.
- ID3v1, ID3v2.2, ID3v2.3 und ID3v2.4 über gruppierte ExifTool-Tags.
- Matroska Segment-, Tag- und Track-Werte über MediaInfo.
- Typisierte Normalisierung für Integer, Float, Boolean, Datums-/Zeitanteile,
  Track-/Disc-Brüche und strukturierte iXML-Werte.
- Fixture- und Referenzdatei-Tests; Paketprüfung für alle Maps.

Status: abgeschlossen.

## Slice 2: BWF- und iXML-Schreibadapter

- Eigener RIFF/RF64-Chunk-Writer für `bext` und `iXML`; ExifTool kann diese
  Chunks nur lesen.
- Bestehende unbekannte Chunks, Padding, Audio-Nutzdaten und RF64-Größen
  verlustfrei erhalten.
- BWF-Versionen 0/1/2, 64-Bit-TimeReference, UMID und die fünf
  Loudness-Felder korrekt kodieren.
- iXML als UTF-8-XML schreiben, Pflichtstrukturen validieren und wiederholte
  TRACK-/SYNC_POINT-Objekte erhalten.
- Atomarer Austausch, Backup/Rollback und Verify-after-write.

Status: offen.

## Slice 3: ID3-Schreibadapter

- Dedizierten ID3-Writer auswählen und samt Hashes, Lizenz und Notices
  paketieren; ExifTool ist für ID3 read-only.
- ID3v2.4 als Standard, kontrollierter ID3v2.3-Kompatibilitätsmodus und
  explizite Behandlung bestehender ID3v1-Tags.
- Mehrfachwerte, APIC, USLT/SYLT, CHAP/CTOC, TXXX/WXXX sowie unbekannte Frames
  verlustfrei behandeln.
- Padding, atomarer Austausch, Rollback und Byte-/Semantik-Verifikation.

Status: offen.

## Slice 4: Matroska-Schreibadapter

- `mkvpropedit`-basierte In-place-Änderungen mit gebündeltem/systemweitem
  Resolver, Hash-/Lizenzprüfung und klarer Nichtverfügbarkeitsmeldung.
- Segment-Tags, Track-Metadaten und Edition/Chapter-Ziele getrennt adressieren.
- Wiederholte SimpleTags als wiederholte Werte erhalten; keine
  Trennzeichen-Flattening-Heuristik.
- Tag-vs-TrackEntry-vs-Chapter-Präzedenz testen, atomaren Rollback anbieten.

Status: offen.

## Slice 5: Broker, Katalog und Verträge

- Profilzustände `Unsupported`, `Unavailable`, `Absent`, `Embedded`,
  `Conflicting` und `Invalid` pro Datei ausgeben.
- Feldprovenienz bis zum konkreten Standard, Adapter und Containerziel führen.
- Strukturierte Werte ohne Stringifizierung in `metadata.get`,
  `metadata.set`, Batch, Rollback und SQLite-Katalog erhalten.
- Capability-Verträge liefern nur tatsächlich verfügbare Writer.

Status: offen.

## Slice 6: Studio-Oberfläche

- BWF-, iXML-, ID3- und Matroska-Sektionen aus den Registry-/Map-Daten
  generieren.
- Stream- und Chapter-Ziele explizit auswählen; komplexe Listen als
  strukturierte Editoren darstellen.
- Read-only/Unavailable/Conflict-Zustände und konkrete Write-Targets sichtbar
  machen.
- Bestehende Metadaten sofort anzeigen und externe Reads progressiv ergänzen.

Status: offen.

## Slice 7: Produktions-Workflows und Härtung

- Import/Export, Templates, Batch, Cache-Refresh und Rollback um alle vier
  Profile erweitern.
- Referenzdateien für BWF v0/v1/v2, RF64, iXML-Varianten, ID3-Versionen und
  Matroska-Tags/Tracks/Chapters testen.
- Große Dateien ohne vollständiges Einlesen validieren; Abbruch,
  Parallelität und beschädigte Container abdecken.
- End-to-end-Tests RenderKit -> Broker -> Katalog -> Studio und Paket-Smokes.

Status: offen.
