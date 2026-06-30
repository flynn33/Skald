# Skald Wiki

## Overview

Skald is a macOS document conversion utility built on the Forsetti Framework. It batch-converts documents from a source folder into human-readable Markdown or structured JSON output.

This wiki covers the application architecture, Forsetti Framework integration, and development guidelines.

## Forsetti Framework Integration

Skald uses the [Forsetti Framework v0.1.0](https://github.com/jdaley/Forsetti-Framework), a proprietary modular Swift runtime framework for native Apple applications created by James Daley. The framework provides modular architecture, runtime lifecycle management, and protocol-based service abstraction.

### Deployment Pattern

Skald uses **Forsetti Deployment Pattern A (Single-Module App)**:

- The entire application (UI and business logic) is encapsulated in a single `ForsettiAppModule`.
- The Forsetti Framework runs silently in the background.
- End users interact only with the Skald conversion interface.
- Framework developer controls are hidden (`showDeveloperControls: false`).

### Module Architecture

```
SkaldApp (Entry Point)
  └── ContentView (Forsetti host wrapper)
        ├── SkaldForsettiBootstrap
        ├── ModuleRegistry
        │     └── SkaldAppModule (ForsettiAppModule)
        ├── ForsettiHostController
        │     └── ForsettiRuntime
        └── ForsettiViewInjectionRegistry
              └── "com.daley.jim.skald.app-module.workspace" → SkaldAppModuleView
```

### Module Manifest

The module is discovered at runtime via its JSON manifest at `Resources/ForsettiManifests/SkaldAppModuleManifest.json`:

- **Module ID**: `com.daley.jim.skald.app-module`
- **Type**: `app` (ForsettiAppModule)
- **Platform**: macOS
- **Capabilities**: `storage`, `file_export`, `view_injection`
- **Entry Point**: `SkaldAppModule`
- **Default Role**: `ui`

### Bootstrap Flow

1. `SkaldApp` renders `ContentView`.
2. `ContentView` creates `SkaldForsettiBootstrap`.
3. The bootstrap registers the `SkaldAppModule` factory in a `ModuleRegistry`.
3. `ForsettiHostTemplateBootstrap.makeController()` assembles the runtime with platform services, entitlement provider, and the module registry.
4. View injections are registered — `SkaldAppModuleView` is mapped to the module workspace view ID.
5. In production mode, the bootstrap boots the runtime and activates only `com.daley.jim.skald.app-module`.
6. In development mode, `ForsettiHostRootView` can be used with developer controls enabled.
7. On boot, the runtime discovers the module manifest from `Bundle.main`, validates compatibility, and activates the module.
8. The activated module renders `SkaldAppModuleView` in the `module.workspace` slot.

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

### Forsetti Rules

- Forsetti is a **sealed external dependency** — use only public APIs and do not copy or modify the Forsetti repository inside Skald.
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
- **Framework**: Built with the Forsetti Framework v0.1.0 by James Daley
- **License**: Proprietary (see LICENSE.md)
- **Version**: 1.0.0 <!-- x-release-please-version -->
