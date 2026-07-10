# Fixtures

This folder contains small input samples and expected outputs that validate readability, structure, and data integrity.

## How to use

1. Launch the Skald app.
2. Select `Fixtures/input` as the source folder.
3. Choose an empty target folder.
4. Convert once to Markdown, once to JSON.
5. Compare the generated outputs to `Fixtures/expected/markdown` and `Fixtures/expected/json`.

## Integrity coverage

The fixture set includes:

- Structured text, tables, configuration, property lists, XML, and plain text.
- Extension-only `.env` input.
- Integers above JavaScript's exact-number range and high-precision decimals.
- CSV cells containing pipe characters and embedded newlines.
- Verbatim source/log content containing an embedded Markdown fence and trailing newlines.

## Notes

- `convertedAt` is generated at runtime, so the validator normalizes that field before comparison.
- JSON output uses sorted keys and pretty printing.
- Markdown prose is wrapped at 90 characters.
- Markdown table cells escape pipe characters and render embedded newlines as `<br>`.

## Automated validation

Run both validators from the repository root:

```bash
bash scripts/validate_fixtures.sh
bash scripts/validate_output_file_planner.sh
```

The first command compiles a dependency-light Swift conversion tool and compares every fixture. The second validates collision-free output naming and overwrite prevention.
