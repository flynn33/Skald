# Contributing to Skald

Thank you for considering contributing to Skald. This project is developed and maintained by Jim Daley, and contributions are welcome to improve the app. Please follow these guidelines to ensure smooth collaboration.

## Code of Conduct

Be respectful, inclusive, and professional in all interactions.

## Contributor Attribution Policy

Skald keeps repository attribution human-owned.

- Do not use tool or service identities as commit authors, committers, or `Co-authored-by` trailers.
- Do not list tool or service identities under documentation sections such as `Tools`, `Tooling`, `Contributors`, `Credits`, `Acknowledgements`, or reviewer metadata.
- Do not commit synthetic visual assets or files that carry provenance metadata.

The attribution guard workflow enforces this policy on pushes, tags, and pull requests. It rejects matching commit messages, author or committer identities, changed file content, branch names, and changed file paths until a human-authored replacement is provided.

## Forsetti Reference Guidelines

Skald follows the Mac architecture guidance from the Forsetti reference repository. Forsetti is not linked, vendored, or resolved as a package dependency in Skald.

### Reference Boundary

The Forsetti repository may be read for templates, examples, module-boundary rules, and manifest expectations, but it must remain outside the Skald repository:

- **Allowed**: Follow the module-boundary, manifest, and object-oriented design guidance in app-owned Skald code.
- **Not allowed**: Adding Forsetti package products to the Xcode project, copying Forsetti source into Skald, or patching Forsetti internals for app behavior.

If reference material identifies a missing Skald-owned boundary or manifest requirement, implement that requirement in Skald without linking the reference repository.

### OOP and Architecture Rules

- Use `final class` for all production classes unless extension is intentional and documented.
- Prefer protocol-first design for contracts and behavior boundaries.
- Use constructor dependency injection for collaborators.
- Avoid hidden global state and implicit service lookup patterns.
- Keep dependencies one-way; no circular dependencies.
- Use native Apple technologies only (Swift, SwiftUI, Apple frameworks).

### Required Verification

Before submitting a pull request, run:

```bash
bash scripts/validate_fixtures.sh
bash scripts/validate_output_file_planner.sh

xcodebuild -project "Skald.xcodeproj" \
  -scheme "Skald" \
  -configuration Debug \
  -sdk macosx \
  build
```

## How to Contribute

1. **Fork the Repository**: Create a fork of the repo on GitHub.
2. **Create a Branch**: Use a descriptive name, e.g., `feature/add-new-converter` or `bugfix/fix-pdf-parsing`.
3. **Make Changes**: Follow Swift coding conventions and Forsetti architecture rules:
   - Use 4-space indentation.
   - Keep code modular and testable.
   - Mark all new classes as `final`.
   - Add comments where necessary.
   - Update documentation if features change.
4. **Test Your Changes**: Build and run the app in Xcode. Test conversions with sample files.
5. **Commit Changes**: Use [Conventional Commits](#commit-message-convention) format, e.g., `feat: add support for TXT files in TextConverter`.
6. **Submit a Pull Request**: Target the main branch. Include a description of changes, why they're needed, and any relevant issues.

## Commit Message Convention

This project uses [Conventional Commits](https://www.conventionalcommits.org/) to automate versioning and changelog generation via [release-please](https://github.com/googleapis/release-please).

Skald versions use `release.feature.patch` numbering. The repository baseline starts at `1.0.0`.

All commits to `main` must follow this format:

```
<type>[optional scope]: <description>
```

### Types

| Type | Purpose | Version Bump |
|------|---------|-------------|
| `feat:` | A new feature | Feature (e.g., 1.1.0) |
| `fix:` | A bug fix | Patch (e.g., 1.0.1) |
| `docs:` | Documentation only | No release |
| `chore:` | Maintenance tasks | No release |
| `refactor:` | Code restructuring | No release |
| `test:` | Adding or updating tests | No release |
| `ci:` | CI/CD changes | No release |

### Breaking Changes

Append `!` after the type for breaking changes. This triggers a release-line version bump.

```
feat!: redesign conversion pipeline API
```

### Examples

```
feat: add EPUB input format support
fix: handle non-UTF8 text files gracefully
docs: update wiki with new converter instructions
feat(pdf): add OCR fallback for scanned PDFs
```

### How It Works

When commits are pushed to `main`, release-please automatically:
1. Analyzes commit messages since the last release.
2. Creates or updates a release PR with a draft CHANGELOG.
3. When the release PR is merged, creates a GitHub Release and tag.
4. A post-release step syncs the new version to Xcode project settings, Forsetti manifests, and Swift source.

## Reporting Issues

- Use GitHub Issues to report bugs or suggest enhancements.
- Provide details: Steps to reproduce, expected vs. actual behavior, screenshots if applicable.
- Label issues appropriately (e.g., `bug`, `enhancement`, `documentation`).

## Development Setup

- macOS 26.2 or later with Xcode 26.2 or later.
- No third-party dependencies; uses Apple frameworks only.

## Review Process

Pull requests will be reviewed by Jim Daley or designated maintainers. Changes must:
- Align with the project's goals and maintain code quality.
- Follow Forsetti-informed architecture rules for module boundaries, final classes, and dependency injection.
- Pass build verification.

For questions, contact Jim Daley via repository issues.

*Last updated: March 5, 2026*
