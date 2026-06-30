# Fixtures

This folder contains small input samples and expected outputs to validate readability and structure.

## How to use

1. Launch the Skald app.
2. Select `Fixtures/input` as the source folder.
3. Choose an empty target folder.
4. Convert once to Markdown, once to JSON.
5. Compare the generated outputs to `Fixtures/expected/markdown` and `Fixtures/expected/json`.

## Notes

- `convertedAt` is generated at runtime, so it will not match the expected JSON. Ignore or normalize that field when comparing.
- JSON output uses sorted keys and pretty printing.
- Markdown output is wrapped at 90 characters.

## Automated validation

Run the fixture validator script from the repo root:

```bash
./scripts/validate_fixtures.sh
```

It will compile a small Swift validation tool, run conversions for the fixtures, and compare outputs.
