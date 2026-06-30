#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/.build/fixture-validator"
BIN_PATH="${BUILD_DIR}/validate_fixtures"

mkdir -p "${BUILD_DIR}"

swiftc \
  "${ROOT_DIR}/scripts/FixtureValidator.swift" \
  "${ROOT_DIR}/Skald/Services/Converters/DocumentConverter.swift" \
  "${ROOT_DIR}/Skald/Models/OutputFormat.swift" \
  "${ROOT_DIR}/Skald/Models/ConversionError.swift" \
  "${ROOT_DIR}/Skald/Models/ReadableModels.swift" \
  "${ROOT_DIR}/Skald/Support/Formatting/ReadableOutputFormatter.swift" \
  "${ROOT_DIR}/Skald/Support/Parsing/PlainTextParser.swift" \
  "${ROOT_DIR}/Skald/Services/Converters/TextConverter.swift" \
  "${ROOT_DIR}/Skald/Support/Parsing/DelimitedTextParser.swift" \
  "${ROOT_DIR}/Skald/Services/Converters/DelimitedTextConverter.swift" \
  "${ROOT_DIR}/Skald/Services/Converters/PropertyListConverter.swift" \
  "${ROOT_DIR}/Skald/Support/Parsing/TextFileReader.swift" \
  "${ROOT_DIR}/Skald/Services/Converters/JSONConverter.swift" \
  "${ROOT_DIR}/Skald/Services/Converters/XMLConverter.swift" \
  "${ROOT_DIR}/Skald/Services/Converters/IniConverter.swift" \
  "${ROOT_DIR}/Skald/Services/Converters/SourceTextConverter.swift" \
  -o "${BIN_PATH}"

"${BIN_PATH}" "${ROOT_DIR}"
