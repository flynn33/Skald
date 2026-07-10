# Skald Alpha Testing Guide

This guide defines the release gate and manual test matrix for the first external Skald Alpha.

## Supported Alpha Environment

- macOS 26.2 or later.
- Xcode 26.2 or later.
- Forsetti Framework v0.1.0 checked out beside this repository at `../Forsetti-Framework-Mac-iOS-main/`.
- A writable source folder containing test documents.
- A writable target folder for generated Markdown and JSON.

The full application build is a local gate because Forsetti is a sealed sibling package and is not available to GitHub-hosted runners. The repository workflow validates the dependency-light conversion core and output safety rules.

## Automated Gates

Run these commands from the repository root before every Alpha build:

```bash
bash scripts/validate_fixtures.sh
bash scripts/validate_output_file_planner.sh

xcodebuild -project "Skald.xcodeproj" \
  -scheme "Skald" \
  -configuration Debug \
  -sdk macosx \
  build
```

Expected result:

- All committed conversion fixtures match their expected Markdown and JSON.
- Output planning tests confirm that source files and existing outputs are never overwritten.
- The Xcode build completes without warnings or errors attributable to Skald.

## Manual Smoke Test

### 1. Startup and Framework Activation

1. Launch Skald from Xcode.
2. Confirm the Skald conversion workspace appears.
3. Confirm no Forsetti activation error is displayed.
4. If startup fails, copy the complete on-screen diagnostic into the Alpha issue.

### 2. Folder Access

1. Select a source folder.
2. Select a different target folder.
3. Confirm the status changes to **Ready to convert**.
4. Repeat with the same folder selected for source and target.
5. Confirm conversion completes without modifying any original file.

### 3. Markdown and JSON Conversion

Convert the complete `Fixtures/input` folder to both formats and verify:

- Every supported fixture is reported as converted.
- Unsupported files and directories are reported as skipped with a reason.
- Invalid files are reported as failed without stopping the remaining batch.
- Generated JSON parses successfully with `JSONSerialization` or another standards-compliant parser.
- Generated Markdown renders without broken tables or prematurely closed code fences.

### 4. Data-Integrity Cases

Verify these committed fixtures specifically:

| Fixture | Required result |
| --- | --- |
| `.env` | Recognized as configuration input and emitted as `env.md` or `env.json`. |
| `sample-numbers.json` | `9007199254740993` and the high-precision decimal remain exact. |
| `sample-table-edge.csv` | Pipe characters are escaped and embedded newlines render as `<br>` in Markdown. |
| `sample-verbatim.log` | Indentation, embedded backtick fences, and trailing newlines remain intact. |

### 5. Collision and Overwrite Safety

1. Place `report.pdf` and `report.txt` in the same source folder.
2. Convert both to Markdown.
3. Confirm both outputs exist under distinct names.
4. Run the conversion again without clearing the target folder.
5. Confirm existing outputs remain unchanged and new outputs receive deterministic suffixes.
6. Convert an existing `.md` file to Markdown with the same source and target folder.
7. Confirm the original file remains byte-for-byte unchanged.

### 6. Format Coverage

Exercise at least one real-world file from each Alpha category:

- Digital PDF.
- DOCX or RTF.
- Plain text or Markdown.
- CSV or TSV.
- JSON, XML, plist, and INI/environment configuration.
- PNG, JPEG, or HEIC OCR.
- Source code, YAML/TOML, or log input.

## Alpha Pass Criteria

An Alpha build passes when all of the following are true:

- No crash, hang, or unrecoverable startup failure occurs during the smoke test.
- No source file or pre-existing target file is overwritten.
- Every per-file failure is visible in the conversion report.
- Core validation and output-planning validation pass.
- The local Xcode build passes with the required Forsetti checkout.
- Generated data preserves the values covered by the committed integrity fixtures.

## Known Alpha Limitations

- Folder traversal is not recursive.
- PDF extraction requires a selectable text layer; scanned PDFs do not use the image OCR converter.
- Document formatting is heuristic and is not layout-faithful.
- YAML, TOML, source code, and log files are preserved as verbatim code blocks rather than structurally parsed.
- Existing outputs are preserved, so repeated conversions create suffixed files instead of replacing prior results.

## Reporting an Alpha Defect

Include:

- Skald commit SHA.
- macOS and Xcode versions.
- Forsetti Framework version or commit SHA.
- Input file type and a minimal reproducible sample when licensing permits.
- Selected output format.
- Expected and actual result.
- Complete conversion-report or startup diagnostic text.
- Whether source and target folders were the same.
