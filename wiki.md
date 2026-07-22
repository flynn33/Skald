# Skald Wiki

## Overview

Skald is a macOS document conversion utility with Forsetti-guided module boundaries. It batch-converts documents from a source folder into human-readable Markdown or structured JSON output.

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
| PDF | `PDFConverter` | PDFKit page-by-page text extraction |
| DOCX | `AttributedDocumentConverter` | NSAttributedString officeOpenXML |
| DOC | `AttributedDocumentConverter` | NSAttributedString docFormat |
| RTF | `AttributedDocumentConverter` | NSAttributedString rtf |
| RTFD | `AttributedDocumentConverter` | NSAttributedString rtfd |
| ODT | `AttributedDocumentConverter` | NSAttributedString openDocument |
| HTML/HTM | `AttributedDocumentConverter` | NSAttributedString html |
| WebArchive | `AttributedDocumentConverter` | NSAttributedString webArchive |
| TXT/MD | `TextConverter` | UTF-8 plain text with Markdown-aware parsing |
| CSV/TSV | `DelimitedTextConverter` | Parsed into Markdown tables and JSON data arrays |
| PLIST | `PropertyListConverter` | PropertyListSerialization to JSON-safe output |
| PNG/JPG/JPEG/HEIC/TIFF/TIF | `ImageOCRConverter` | Vision OCR |

### Output Formats

- **Markdown**: Structural headings, list items, and normalized paragraphs with page segmentation for PDFs.
- **JSON**: Version-tagged document model with source metadata, summary statistics, blocks/pages, and optional tables/data payloads for structured inputs.

### Processing Pipeline

1. `ConversionManager` enumerates files in the source directory.
2. Each file is matched to a converter by extension.
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
- **License**: Proprietary (see LICENSE.md)
- **Version**: 1.0.1 <!-- x-release-please-version -->
