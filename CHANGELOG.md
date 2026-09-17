# Changelog for Skald

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project uses `release.feature.patch` versioning.

## [Unreleased]

## [1.1.0] - 2026-09-17
### Added
- A **Both** output mode that creates Markdown and JSON for each input in one conversion run.
- An optional bundled delivery mode that atomically publishes one folder containing the original source and all requested generated outputs.
- Collision-safe bundle and internal filenames that retain the original name and qualify generated files when extensions overlap.
- Production-path coverage for combined output, bundled delivery, source preservation, occupied bundle names, concurrent publishers, failed publication cleanup, and view-model option routing.

- Conversion reports now retain every published output URL for multi-output runs.
- Native ZIP32 collection and XLSX/ODS/BIFF8 XLS workbook readers with typed sparse cells, formula/cache/date/merge metadata, member provenance, and explicit unsupported-variant diagnostics.
- Deterministic actual-format fixtures for stored/deflated ZIP, SpreadsheetML/ODF, and CFB/BIFF8, plus traversal, collision, expansion, entity, encryption, and chain-loop negatives.
- Validated per-format byte, record, column, cell, field, nesting, pixel, worklist, batch, and output ceilings with typed safe failure diagnostics and path-free native logging.
- Pinned macOS native CI with Debug/Release builds and tests, analysis, fixture validators, required-test discovery, and retained result bundles.
- P08 qualification record for signed Debug/Release, 107-test native and IDE matrices, separate sanitizers, signed sandbox inspection, named manual scenarios, and a separate Xcode interaction scheme that passed a direct two-file Finder drop.
- Per-page PDF and per-frame image extraction provenance, status, OCR confidence, and warnings; scanned pages use bounded Vision OCR.
- Ordered XML mixed-content schema 2.0 and resource-free offline HTML extraction on a background task, with partial-outcome reporting for attributed structures.
- Shared Xcode scheme and native unit/integration test target for the ingestion remediation.
- Isolated baseline writer-failure probe and parser regression corpus; the recorded failures remain open until the production path is repaired.
### Fixed
- Rejected BIFF8 worksheets missing their EOF before the next sheet, preventing cross-sheet record consumption; reduced repeated XML text concatenation copies.
- Removed source-path interpolation from conversion logs after signed IDE runtime inspection exposed those paths in its privileged console.
- Deferred picker, output-selection, Convert, and Cancel view-model mutations to the next main-actor turn, removing the observed SwiftUI state-publication warning; made long conversion reports vertically scrollable.
- Bounded previously whole-file JSON/plist/XML/INI/text imports and PDF/image/attributed preflight; reduced CSV decode copies, added read/parse cancellation, and escaped untrusted Markdown markup.
- Replaced the production writer's incompatible write flags with complete same-directory temporary files and exclusive, bounded publication. Existing source and target bytes remain protected under tested collision and concurrent-publisher cases.
- Replaced the CSV/TSV parser's CRLF, whitespace, empty-record, and malformed-quote behavior with strict scalar-state parsing; added BOM-aware UTF-8/16/32 decoding and explicit Windows-1252/Latin-1 choices.
- Preserved the first record in automatic header mode, added explicit delimiter/header/encoding controls, and recorded applied import settings in CSV/TSV JSON schema `1.2` and the conversion report.
- Replaced CSV/TSV header-key records with ordered canonical columns and stable IDs, preserving duplicate/blank labels, ragged records, missing versus empty fields, and extra cells in JSON schema `2.0` and recoverable Markdown. Removed width-driven Markdown table padding.
- Added multi-file/folder source selection, drag/drop, optional recursive and hidden discovery, identity-deduplicated worklists, RTFD package classification, strict unknown-text probing, special/symlink rejection, per-file access/conflict outcomes, service-level single-run protection, progress, cancellation, and restart.

## [1.0.0] - 2026-06-30
### Added
- Initial Skald macOS document conversion app.
- Forsetti Framework integration: Skald is now built on the Forsetti Framework v0.1.0 modular runtime.
- `SkaldAppModule` implementing `ForsettiAppModule` for single-module app deployment (Pattern A).
- `SkaldForsettiBootstrap` for Forsetti runtime initialization and view injection registration.
- `SkaldModuleRegistry` for module factory registration.
- Module manifest (`SkaldAppModuleManifest.json`) for runtime discovery and compatibility validation.
- Forsetti Framework resolved as an external local Swift Package.
- `.swiftlint.yml` configuration aligned with Forsetti coding standards.
- `wiki.md` for GitHub wiki documentation.
- `.gitattributes` for consistent file handling.

### Changed
- `SkaldApp` now bootstraps the Forsetti runtime and uses `ForsettiHostRootView` as the root view.
- All converter classes (`ConversionManager`, `PDFConverter`, `AttributedDocumentConverter`, `TextConverter`) marked as `final` per Forsetti OOP guidelines.
- `MARKETING_VERSION` set to 1.0.0.
- `README.md` rewritten to document Forsetti Framework integration and updated architecture.
- `CONTRIBUTING.md` updated with Forsetti development guidelines and sealed framework constraints.
- `LICENSE.md` updated to reference Forsetti Framework licensing.
- `.gitignore.txt` renamed to `.gitignore` and updated with Forsetti-specific entries.

### Removed
- `Persistence.swift` and CoreData model (unused in application flow).
- Direct `ContentView` root in `SkaldApp` (now rendered through Forsetti view injection).
