# Changelog for Skald

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-03-05
### Added
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
- `MARKETING_VERSION` updated from 1.0 to 2.0.
- `README.md` rewritten to document Forsetti Framework integration and updated architecture.
- `CONTRIBUTING.md` updated with Forsetti development guidelines and sealed framework constraints.
- `LICENSE.md` updated to reference Forsetti Framework licensing.
- `.gitignore.txt` renamed to `.gitignore` and updated with Forsetti-specific entries.

### Removed
- `Persistence.swift` and CoreData model (unused in application flow).
- Direct `ContentView` root in `SkaldApp` (now rendered through Forsetti view injection).

## [1.0.0] - 2025-12-31
### Added
- Initial release of Skald.
- Core functionality: Conversion of PDF, DOCX, DOC, RTF, ODT, HTML, HTM, and TXT files to Markdown or JSON.
- SwiftUI-based user interface for folder selection and conversion.
- Modular converters using protocols for extensibility.
- CoreData persistence for preview data.
- Error handling and security-scoped resource management.
- Support for macOS; basic notes for Windows compatibility.
