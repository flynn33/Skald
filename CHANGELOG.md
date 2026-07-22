# Changelog for Skald

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project uses `release.feature.patch` versioning.

## [1.0.1](https://github.com/flynn33/Skald/compare/v1.0.0...v1.0.1) (2026-07-22)


### Bug Fixes

* keep Skald standalone from Forsetti reference ([335fa41](https://github.com/flynn33/Skald/commit/335fa414408815c69b2ff832989472539780e257))
* keep Skald standalone from Forsetti reference ([611c626](https://github.com/flynn33/Skald/commit/611c6264637e7c865946d81852bb63a261211b6a))
* prepare alpha conversion safeguards ([3bd2361](https://github.com/flynn33/Skald/commit/3bd2361c4a8c91d4456fa7f7871d28e700bc641f))
* prepare Skald for Alpha testing ([aad2e20](https://github.com/flynn33/Skald/commit/aad2e20c20e8b02d6a0dd32634d44bdd1014c1d1))

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
