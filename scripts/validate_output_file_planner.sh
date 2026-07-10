#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/.build/output-file-planner-validator"
BIN_PATH="${BUILD_DIR}/validate_output_file_planner"

mkdir -p "${BUILD_DIR}"

swiftc \
  -warnings-as-errors \
  "${ROOT_DIR}/scripts/OutputFilePlannerValidator.swift" \
  "${ROOT_DIR}/Skald/Models/SourceFileDescriptor.swift" \
  "${ROOT_DIR}/Skald/Services/OutputFilePlanner.swift" \
  -o "${BIN_PATH}"

"${BIN_PATH}"
