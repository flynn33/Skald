#!/usr/bin/env bash
set -euo pipefail

# Validates the committed digital-PDF fixture against expected output. Links
# PDFKit, so it is kept separate from validate_fixtures.sh. Pass --write to
# regenerate the expected outputs. PDF extraction can vary across macOS
# versions; treat this as a best-effort local check.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/.build/pdf-fixture-validator"
BIN_PATH="${BUILD_DIR}/validate_pdf_fixture"

mkdir -p "${BUILD_DIR}"

swiftc \
  -warnings-as-errors \
  "${ROOT_DIR}/scripts/PDFFixtureValidator.swift" \
  "${ROOT_DIR}/Skald/Services/Converters/DocumentConverter.swift" \
  "${ROOT_DIR}/Skald/Models/OutputFormat.swift" \
  "${ROOT_DIR}/Skald/Models/ConversionError.swift" \
  "${ROOT_DIR}/Skald/Models/SourceFileDescriptor.swift" \
  "${ROOT_DIR}/Skald/Models/ReadableModels.swift" \
  "${ROOT_DIR}/Skald/Support/Formatting/ReadableOutputFormatter.swift" \
  "${ROOT_DIR}/Skald/Support/Parsing/PlainTextParser.swift" \
  "${ROOT_DIR}/Skald/Support/Parsing/AttributedTextParser.swift" \
  "${ROOT_DIR}/Skald/Support/Parsing/PDFTextParser.swift" \
  "${ROOT_DIR}/Skald/Services/Converters/PDFConverter.swift" \
  -o "${BIN_PATH}"

"${BIN_PATH}" "${ROOT_DIR}" "$@"
