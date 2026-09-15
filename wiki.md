# Skald Wiki

## Overview

Skald is a macOS document conversion utility with Forsetti-guided module boundaries. It batch-converts selected files and folders into human-readable Markdown or structured JSON output.

This wiki covers the application architecture, Forsetti reference alignment, and development guidelines.

## Forsetti Reference Alignment

Skald uses the Forsetti Mac/iOS repository as reference material for modular architecture, manifest structure, and app-owned boundaries. The reference repository is not linked, vendored, or resolved as a package dependency.

### Deployment Shape

Skald follows the single-module app shape:

- The primary application UI is contained in `SkaldAppModuleView`.
- Conversion behavior is separated into view models, services, converters, parsers, and formatters.
- End users interact only with the Skald conversion interface.
- The app does not expose framework controls or require framework runtime activation.

### Module Architecture

```
SkaldApp (Entry Point)
  └── ContentView
        └── SkaldAppModuleView
              └── ConversionViewModel
                    └── ConversionManager
                          └── DocumentConverter implementations

SkaldAppModule
  └── App-owned module identity metadata aligned with SkaldAppModuleManifest.json
```

### Module Manifest

Skald keeps a JSON manifest at `Resources/ForsettiManifests/SkaldAppModuleManifest.json` for reference-aligned architecture review:

- **Module ID**: `com.daley.jim.skald.app-module`
- **Type**: `app`
- **Platform**: macOS
- **Capabilities**: `storage`, `file_export`, `view_injection`
- **Entry Point**: `SkaldAppModule`
- **Default Role**: `ui`

### App Flow

1. `SkaldApp` renders `ContentView`.
2. `ContentView` renders `SkaldAppModuleView`.
3. `SkaldAppModuleView` owns screen state through `ConversionViewModel`.
4. `ConversionViewModel` delegates conversion work to `ConversionManager`.
5. `ConversionManager` routes each supported file to a matching converter.
6. Output is written as Markdown or JSON in the selected target folder.

## Conversion Pipeline

### Supported Input Formats

| Format | Converter | Method |
|--------|-----------|--------|
| PDF | `PDFConverter` | PDFKit native pages and bounded Vision OCR for scanned pages |
| DOCX | `AttributedDocumentConverter` | NSAttributedString officeOpenXML |
| DOC | `AttributedDocumentConverter` | NSAttributedString docFormat |
| RTF | `AttributedDocumentConverter` | NSAttributedString rtf |
| RTFD | `AttributedDocumentConverter` | NSAttributedString rtfd |
| ODT | `AttributedDocumentConverter` | NSAttributedString openDocument |
| HTML/HTM | `AttributedDocumentConverter` | resource-free Foundation text extraction on a background task |
| WebArchive | `AttributedDocumentConverter` | recognized, resource-isolation failure |
| TXT/MD | `TextConverter` | UTF-8 plain text with Markdown-aware parsing |
| CSV/TSV | `DelimitedTextConverter` | Strict BOM-aware decoding and lossless syntactic records; header/delimiter/encoding choices, with canonical table projection in schema 2.0 |
| PLIST | `PropertyListConverter` | PropertyListSerialization to JSON-safe output |
| PNG/JPG/JPEG/HEIC/TIFF/TIF | `ImageOCRConverter` | Vision OCR for all oriented frames/pages |

### Output Formats

- **Markdown**: Structural headings, list items, and normalized paragraphs with page segmentation for PDFs.
- **JSON**: Version-tagged document model with source metadata, summary statistics, blocks/pages, and optional tables/data payloads for structured inputs.

### Processing Pipeline

1. `SourceWorklistBuilder` snapshots selected files and folders, with optional recursive traversal and nested-target exclusion.
2. `ConversionManager` checks content signatures or strict text before dispatching to a converter.
3. The converter extracts text and delegates to `ReadableOutputFormatter`.
4. The formatter applies heuristic-based structure detection (headings, lists, paragraphs).
5. Output is written to the target directory with the appropriate extension.

## Development Guidelines

### Forsetti-Informed Rules

- Treat the Forsetti repository as external reference material only.
- Do not add Forsetti package products to the Xcode project.
- Do not copy or modify the Forsetti repository inside Skald.
- All classes must be marked `final` unless extension is intentional and documented.
- Use constructor dependency injection; avoid hidden globals.
- Use native Apple technologies only (Swift, SwiftUI, Apple frameworks).
- Dependencies must flow one-way; no circular dependencies.

### Adding New Converters

1. Create a `final class` conforming to `DocumentConverter`.
2. Declare `supportedExtensions`.
3. Implement `convert(at:to:)` using `ReadableOutputFormatter` for consistent output.
4. Register in `ConversionManager`'s default converter list.

## About

- **Developer**: Jim Daley
- **Architecture**: Forsetti-guided native macOS module boundaries
- **License**: Apache License 2.0 (see LICENSE)
- **Version**: 1.0.0 <!-- x-release-please-version -->

## Native remediation checks

The shared Xcode scheme includes `SkaldTests`. The writer, CSV/TSV parser, canonical table, intake, extraction, resource bounds, and focused XLSX/BIFF8 XLS/ODS/ZIP tests pass native checks. Version 1.0.0 still awaits the final full release gates. CSV/TSV uses canonical column IDs; PDF, image, ordered XML, workbook, and ZIP collection outputs use schema `2.0`, distinct from app version `1.0.0`. See `docs/remediation/NATIVE_TEST_PLAN.md`, `docs/remediation/NAMED_FORMAT_READERS.md`, `docs/remediation/RESOURCE_BOUNDS_AND_PRIVACY.md`, `docs/remediation/OUTPUT_PUBLICATION.md`, and `docs/remediation/TASK_LEDGER.md` for evidence and limits.
