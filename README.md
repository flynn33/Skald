# Skald

**Current Version: 1.0.0** <!-- x-release-please-version -->

The 1.0.0 application is under ingestion remediation. The shared writer, lossless CSV/TSV parser, canonical table, source intake, and P05 extraction passed the current native Debug/Release suite; named format expansion and full release gates remain open. The shared `Skald` scheme discovers `SkaldTests`, with the required work tracked in [the remediation test plan](docs/remediation/NATIVE_TEST_PLAN.md) and [task ledger](docs/remediation/TASK_LEDGER.md). This is not a completed release qualification.

Skald is a macOS SwiftUI app that batch-converts selected files and folders into human-readable Markdown (`.md`) or structured JSON (`.json`) in a target folder.

The app follows Forsetti Mac architecture guidance while remaining a standalone native macOS project. The Forsetti repository is used as implementation reference material only; it is not vendored, linked, or resolved as a package dependency.

## Table of Contents

- [What It Does](#what-it-does)
- [Forsetti-Guided Architecture](#forsetti-guided-architecture)
- [Supported Formats](#supported-formats)
- [Output Design](#output-design)
- [Architecture](#architecture)
- [Requirements](#requirements)
- [Versioning](#versioning)
- [Alpha Testing](#alpha-testing)
- [Quick Start](#quick-start)
- [How to Use](#how-to-use)
- [Build From Terminal](#build-from-terminal)
- [Project Structure](#project-structure)
- [Extending with New Converters](#extending-with-new-converters)
- [Known Limitations](#known-limitations)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)
- [Changelog](#changelog)

## What It Does

- Converts supported files from one folder to another in bulk.
- Supports two output formats:
  - Markdown for direct reading/editing.
  - JSON for downstream automation and data pipelines.
- Produces readable output:
  - Paragraph normalization.
  - Heading/list detection.
  - Page segmentation for PDFs.
  - Pretty-printed, sorted JSON.

## Forsetti-Guided Architecture

Skald follows the Forsetti Mac/iOS repository as architecture guidance:

- **App-owned module boundary**: Skald keeps its primary interface in `SkaldAppModuleView`, with conversion behavior delegated into models, view models, services, converters, and formatting/parsing support.
- **Manifest contract**: `SkaldAppModuleManifest.json` records the app module identity, platform, requested capabilities, and runtime requirements for Forsetti-aligned review.
- **Native macOS implementation**: Skald uses SwiftUI, AppKit, PDFKit, Vision, Foundation, and Xcode project settings directly.
- **No framework dependency**: Skald does not link Forsetti package products and does not include Forsetti source.

The Forsetti repository may sit near the project as reference documentation, templates, and examples, but it is not required to build Skald.

## Supported Formats

| Input Extension | Converter | Notes |
| --- | --- | --- |
| `pdf` | `PDFConverter` | Native text retained page-by-page; absent/unusable page text uses bounded Vision OCR. Locked PDFs require a password; extraction source, confidence, and partial pages are disclosed. |
| `docx`, `doc`, `rtf`, `rtfd`, `odt` | `AttributedDocumentConverter` | Non-HTML `NSAttributedString` import; attachments/tables and unverified DOC/DOCX/ODT container structures are reported partial. |
| `html`, `htm` | `AttributedDocumentConverter` | Strict resource-free markup extracted by a bounded Foundation parser on the background conversion task; unsupported tags and resource references fail, tables are partial. |
| `webarchive` | `AttributedDocumentConverter` | Recognized but fails with a resource-isolation diagnostic; no extracted output. |
| `txt`, `md`, `markdown`, `mdown` | `TextConverter` | UTF-8 text input with Markdown-aware parsing. |
| `csv`, `tsv` | `DelimitedTextConverter` | Preserved as canonical columns and records; Markdown uses recoverable JSON code blocks and JSON uses schema 2.0. |
| `json` | `JSONConverter` | Parsed via `JSONSerialization`; structure preserved as JSON `data` / nested Markdown list. |
| `xml` | `XMLConverter` | Ordered mixed text/CDATA/child nodes with separate attributes and namespace identity; schema 2.0. |
| `plist` | `PropertyListConverter` | Parsed via `PropertyListSerialization` into JSON-safe output. |
| `ini`, `cfg`, `properties`, `env` | `IniConverter` | `[section]` headers become nested objects; `key=value` / `key: value` become string entries. |
| `png`, `jpg`, `jpeg`, `heic`, `tiff`, `tif` | `ImageOCRConverter` | All ImageIO frames/pages OCR via Vision with orientation, per-frame confidence/warnings, and bounded dimensions. |
| `yaml`, `yml`, `toml`, `conf`, `log`, and common source-code extensions (`swift`, `py`, `js`, `ts`, `java`, `go`, `rs`, `sh`, `sql`, …) | `SourceTextConverter` | Preserved verbatim inside a fenced code block (Markdown) / a `code` block whose `text` holds exact contents (JSON). |

## Output Design

### Markdown output

Markdown output is generated by shared formatting logic and includes:

- Top-level title derived from input filename (suppressed when the document already opens with its own heading, to avoid a redundant title).
- Page headings for PDFs (`## Page N`).
- Converted headings and list items when detectable.
- Merged wrapped lines into readable paragraphs.
- Fenced code blocks for source/log/config files (preserved verbatim).

### JSON output

JSON is emitted as a readable document model (version `1.1` for unchanged formats; version `2.0` for CSV/TSV, PDF, images, and XML, with extraction status/provenance) with:

- `source` metadata: `fileName`, `fileExtension`, `convertedAt` (ISO-8601 UTC timestamp)
- `summary` metadata: `blockCount`, `pageCount` (present for paged content like PDF)
- `content` payload: `blocks` for single-stream documents (block `type` is `heading`, `paragraph`, `listItem`, or `code`), `pages` for paged documents, `data` for structured inputs (JSON/XML/INI/plist); CSV/TSV uses `canonicalTable` and its ID-keyed `data` projection

## Architecture

Skald uses a module-oriented macOS architecture:

- **`ContentView`**:
  - Hosts the Skald module UI as the app's root view.
- **`SkaldAppModule`**:
  - Defines app-owned module identity metadata that aligns with `SkaldAppModuleManifest.json`.
- **`SkaldAppModuleView`** (SwiftUI):
  - Collects source/target folder paths.
  - Selects output format.
  - Triggers conversion.
- **`SkaldAppModuleManifest.json`**:
  - Captures the app-owned module identity and runtime expectations used for architecture review.
- **`ConversionViewModel`**:
  - Owns UI state and delegates file conversion to `ConversionManager`.
- **`ConversionManager`**:
  - Snapshots selected files and folders, with optional recursive traversal and target exclusion.
  - Checks signatures or strict text before routing each regular input to a converter.
  - Writes output with `.md` or `.json` extension.
- **`DocumentConverter`** protocol:
  - Shared interface for all converters.
- **`ReadableOutputFormatter`**:
  - Shared formatter for Markdown and JSON output consistency.
  - Applies structural heuristics (heading/list/paragraph detection).

## Requirements

- macOS 26.2+ (the Xcode project deployment target is 26.2).
- Xcode 26.2+ (the project uses Swift 5 language mode).
- No third-party package dependencies.
- No local Forsetti package checkout is required for build.

Output schema migrations and extraction limits are described in [EXTRACTION_COMPLETENESS.md](docs/remediation/EXTRACTION_COMPLETENESS.md).

Current project settings in `Skald.xcodeproj`:
- `MARKETING_VERSION = 1.0.0`
- `CURRENT_PROJECT_VERSION = 1`

## Versioning

Skald uses `release.feature.patch` versioning. The initial public repository version is `1.0.0`.

- `release`: major release line.
- `feature`: feature-level increment within a release line.
- `patch`: bug fix or maintenance increment.

## Alpha Testing

Use [ALPHA_TESTING.md](ALPHA_TESTING.md) for the automated release gates, manual smoke-test matrix, data-integrity cases, and Alpha pass criteria.

## Quick Start

1. Clone the repository.
2. Open `Skald.xcodeproj` in Xcode.
3. Select the `Skald` scheme.
4. Build and run the app.

## How to Use

1. Launch the app.
2. Click **Choose** next to **Sources** and select one or more files or folders, or drop them on the source row.
3. Click **Choose** next to **Target** and choose an output directory.
4. Choose **Markdown** or **JSON**; enable nested folders and hidden files when needed.
5. For CSV/TSV, select encoding, delimiter, and header interpretation. Automatic header mode keeps the first record as data until you confirm it is a header. A custom delimiter must be one valid Unicode scalar; `sep=` preamble use is explicit.
6. Click **Convert**. Progress and **Cancel** are available while the batch runs.
7. Inspect output files and per-file import warnings in the target directory and conversion report.

Behavior notes:

- Unknown regular files are probed as strict UTF-8 text before conversion; binary, special, conflicting-signature, and inaccessible inputs receive explicit per-file outcomes.
- Skald writes a complete temporary file and publishes it only with native exclusive rename on supporting volumes. It does not replace a source file or a pre-existing target file. When a name is already occupied, the source extension and, when necessary, a numeric suffix are added. On unsupported volumes, it reports a capability error. See [output publication](docs/remediation/OUTPUT_PUBLICATION.md).
- The preferred output filename preserves the original base name and changes only the extension:
  - `example.pdf` -> `example.md` or `example.json`
  - A collision may produce `example-pdf.md`, `example-pdf-2.md`, and so on.
- Extension-only dotfiles such as `.env` are recognized and use a visible output base name such as `env.md`.

## Build From Terminal

```bash
xcodebuild -project "Skald.xcodeproj" \
  -scheme "Skald" \
  -configuration Debug \
  -sdk macosx \
  build
```

## Project Structure

```text
Skald/
├── Skald/
│   ├── App/
│   │   ├── SkaldApp.swift              # App entry point
│   │   └── ContentView.swift           # Root app view
│   ├── AppModule/
│   │   ├── SkaldAppModule.swift        # App module identity metadata
│   │   └── SkaldAppModuleView.swift    # Main conversion UI
│   ├── Models/
│   ├── Services/
│   │   └── Converters/
│   ├── Support/
│   │   ├── Formatting/
│   │   └── Parsing/
│   ├── ViewModels/
│   ├── Views/
│   ├── Resources/
│   │   └── ForsettiManifests/
│   │       └── SkaldAppModuleManifest.json
│   └── Assets.xcassets/
├── Skald.xcodeproj/
├── README.md
├── CONTRIBUTING.md
├── LICENSE
├── CHANGELOG.md
└── wiki.md
```

## Extending with New Converters

1. Create a new type that conforms to `DocumentConverter`.
2. Declare `supportedExtensions`.
3. Implement `convert(at:to:)`.
4. Prefer `ReadableOutputFormatter` for consistent Markdown/JSON output.
5. Register the converter in `ConversionManager` initializer.
6. Mark the class as `final` unless inheritance is intentionally required.

## Known Limitations

- Nested-folder traversal is optional. Directory symlinks and application bundles are not traversed by default.
- Formatting is heuristic-based, not layout-faithful.
- Scanned PDF pages use bounded Vision OCR when native text is absent or unusable. OCR recognition can be empty, ambiguous, or fail; page provenance and warnings disclose those outcomes. A paragraph that spans a page boundary is reported under the page where each part appears.
- `yaml`/`yml`/`toml` and other source/config formats are preserved verbatim as code blocks, not parsed into structured data (no native parser; avoids adding third-party dependencies).
- Tables, images, footnotes, and advanced styles may flatten to plain text.
- CSV/TSV uses strict UTF-8 or a leading UTF-8/16/32 BOM by default, with explicit Windows-1252, Latin-1, and other encoding choices. Other text-based converters retain their existing fallback behavior.
- Unknown extensions with confirmed strict UTF-8 text use the text converter; unknown binary content is skipped with a reason. The dispatch probe is bounded, while some converters still need P06 resource limits.

## Troubleshooting

- Build fails with SDK/deployment mismatch:
  - Align installed Xcode/macOS SDK with project deployment target.
  - Use an installed Xcode/macOS SDK that supports the project's macOS 26.2 deployment target.
- Xcode reports missing Forsetti package products:
  - Confirm the project file has no Forsetti package dependency; Skald does not link Forsetti.
- Empty or sparse output from PDF:
  - Confirm the PDF contains selectable text (not just images).
- Output not appearing:
  - Verify folder permissions and chosen target directory.
  - Check the per-file report for binary, signature-conflict, scope, or converter diagnostics.

## Contributing

This project is open source under Apache License, Version 2.0. You are welcome to use, modify, and redistribute the code under that license.

Outside contributions to this repository are not accepted. Pull requests and collaboration requests will not be reviewed or merged. See [CONTRIBUTING.md](CONTRIBUTING.md).


## License

Copyright 2026 James Daley

This project is licensed under the Apache License, Version 2.0.
See the [LICENSE](LICENSE) file for the full terms.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).
